-- Ground drops. Enemy deaths roll loot tables into physical drops; players
-- can also throw items out of their inventory (the DropItem remote). Drops
-- are magnetic: they fly to the nearest eligible player within MAGNET_RANGE
-- and are added to the inventory via the backend on contact. A thrown drop
-- ignores its owner until they've stepped away from it once, so everyone
-- else has pickup priority (and throws can't boomerang straight back).
-- Drops despawn after a timeout.

local Players = game:GetService("Players")
local Workspace = game:GetService("Workspace")
local RunService = game:GetService("RunService")
local HttpService = game:GetService("HttpService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Items = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Items"))
local Traits = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Traits"))
local Rarity = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Rarity"))
local ArtKit = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("ArtKit"))
local ItemModels = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("ItemModels"))
local Remotes = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Remotes"))
local PlayerService = require(script.Parent.PlayerService)
local EnemyService = require(script.Parent.EnemyService)
local GatheringService = require(script.Parent.GatheringService)

local DropService = {}

local DROP_LIFETIME = 120
local RETRY_DELAY = 1 -- if inventory is full, wait before letting the same drop retry
local MAGNET_RANGE = 10 -- studs: drops start flying to a player inside this
local PICKUP_RANGE = 1.3 -- studs: close enough to be collected
local MAGNET_SPEED = 14 -- studs/second while flying to a player
local OWNER_REARM_DISTANCE = MAGNET_RANGE + 2 -- thrower must get this far away once to re-enable pickup

-- Loot tables: [source] = { { itemId, chance, min, max }, ... }
local LOOT = {
	slime = {
		{ itemId = "slime_goo", chance = 1.0, min = 1, max = 1 },
		{ itemId = "wood", chance = 0.25, min = 1, max = 1 },
	},
	goblin = {
		{ itemId = "goblin_ear", chance = 1.0, min = 1, max = 1 },
		{ itemId = "stone", chance = 0.4, min = 1, max = 2 },
		{ itemId = "sword_iron", chance = 0.05, min = 1, max = 1 }, -- rare
	},
}

-- Rolled trait gear: [source] = { chance, pool }. On a hit, one base item
-- from the pool drops with instance meta rolled by shared/Traits — its item
-- level is the mob's level ±1, so tougher spawns drop stronger rolls.
local GEAR_LOOT = {
	slime = { chance = 0.08, pool = { "ring_vitality", "ring_focus" } },
	goblin = {
		chance = 1.0, -- goblins ALWAYS drop a rolled piece (decided 2026-07-06)
		pool = {
			"sword_basic",
			"helmet_leather",
			"chest_leather",
			"gloves_leather",
			"legs_leather",
			"boots_leather",
		},
	},
}

local MAX_ROLLED_LEVEL = 20

local function rollGear(source, mobLevel)
	local gear = GEAR_LOOT[source]
	if not gear or math.random() > gear.chance then
		return nil
	end
	local itemId = gear.pool[math.random(#gear.pool)]
	local itemLevel = math.clamp((mobLevel or 1) + math.random(-1, 1), 1, MAX_ROLLED_LEVEL)
	local meta = Traits.roll(Items.get(itemId), itemLevel)
	if not meta then
		return nil
	end
	return itemId, meta
end

local DROP_VISUAL_SIZE = 1.6 -- max extent of a drop's miniature model, studs
local dropScale = {} -- [itemId] = cached uniform scale for the drop visual

-- Scale that fits the item's model inside DROP_VISUAL_SIZE, or nil if the
-- item has no model (falls back to the generic glowing cube).
local function visualScale(itemId)
	local cached = dropScale[itemId]
	if cached then
		return cached
	end
	local model = ItemModels.build(itemId)
	if not model then
		return nil
	end
	local size = model:GetExtentsSize()
	model:Destroy()
	local scale = DROP_VISUAL_SIZE / math.max(size.X, size.Y, size.Z)
	dropScale[itemId] = scale
	return scale
end

local dropFolder
local flyFolder -- cosmetic flying pickups; kept out of dropFolder so the
-- magnet/bob loop never touches them

local FLY_SPEED = 16 -- studs/s at launch; accelerates so it always catches up
local FLY_ARRIVE = 1.5 -- studs from the player at which it vanishes
local FLY_TIMEOUT = 4 -- seconds before a stray visual gives up

-- Cosmetic: a mini item model that flies from `position` to the player and
-- vanishes on arrival. The item itself was already granted (gathering adds
-- through the backend first) — this just makes the pickup visible.
local function flyToPlayer(itemId, position, player)
	local part = Instance.new("Part")
	part.Name = "FlyingPickup"
	part.Size = Vector3.new(0.6, 0.6, 0.6)
	part.Anchored = true
	part.CanCollide = false
	part.CanQuery = false
	part.Transparency = 1
	part.CFrame = CFrame.new(position)

	local scale = visualScale(itemId)
	if scale then
		ArtKit.weld(part, ItemModels.get(itemId), scale * 0.7)
	else
		part.Transparency = 0
		part.Color = Color3.fromRGB(230, 200, 90)
		part.Material = Enum.Material.Neon
	end
	part.Parent = flyFolder

	task.spawn(function()
		local born = os.clock()
		while os.clock() - born < FLY_TIMEOUT and part.Parent do
			local dt = RunService.Heartbeat:Wait()
			local character = player.Character
			local root = character and character:FindFirstChild("HumanoidRootPart")
			if not root then
				break
			end
			local offset = root.Position - part.Position
			local dist = offset.Magnitude
			if dist <= FLY_ARRIVE then
				break
			end
			local speed = FLY_SPEED + (os.clock() - born) * 40
			part.CFrame = CFrame.new(part.Position + offset.Unit * math.min(speed * dt, dist))
				* CFrame.Angles(0, os.clock() * 6, 0)
		end
		part:Destroy()
	end)
end

local function rollLoot(source)
	local lootTable = LOOT[source]
	if not lootTable then
		return {}
	end
	local results = {}
	for _, entry in ipairs(lootTable) do
		if math.random() <= entry.chance then
			results[#results + 1] = {
				itemId = entry.itemId,
				quantity = math.random(entry.min, entry.max),
			}
		end
	end
	return results
end

-- The nearest player who may collect this drop right now: alive, within
-- magnet range, and not the excluded thrower (who has no priority on their
-- own throw until they've stepped well away from it once).
local function nearestEligiblePlayer(part)
	local droppedBy = part:GetAttribute("droppedBy")
	local best, bestRoot, bestDist
	for _, candidate in ipairs(Players:GetPlayers()) do
		local character = candidate.Character
		local root = character and character:FindFirstChild("HumanoidRootPart")
		local humanoid = character and character:FindFirstChildOfClass("Humanoid")
		if not (root and humanoid and humanoid.Health > 0) then
			continue
		end
		local dist = (root.Position - part.Position).Magnitude
		if candidate.UserId == droppedBy and not part:GetAttribute("ownerRearmed") then
			if dist > OWNER_REARM_DISTANCE then
				part:SetAttribute("ownerRearmed", true)
			end
			continue
		end
		if dist <= MAGNET_RANGE and (not bestDist or dist < bestDist) then
			best, bestRoot, bestDist = candidate, root, dist
		end
	end
	return best, bestRoot, bestDist
end

-- +1 loot de los drops, lo maneja NotificationUI
local function notifyPickup(player, itemId, added)
	local def = Items.get(itemId)
	local total = PlayerService.getItemCount(player, itemId)
	Remotes.get("Notify"):FireClient(player, string.format("+%d %s (%d)", added, def and def.name or itemId, total))
end

-- -1 al tirar un ítem al piso, mismo estilo que notifyPickup pero restando.
local function notifyDrop(player, itemId, quantity)
	local def = Items.get(itemId)
	local total = PlayerService.getItemCount(player, itemId)
	Remotes.get("Notify"):FireClient(player, string.format("-%d %s (%d)", quantity, def and def.name or itemId, total))
end

local function releaseClaimLater(part)
	-- Inventory full or backend error: release the claim after a beat so the
	-- player can grab it again once they've made room.
	task.delay(RETRY_DELAY, function()
		if part.Parent then
			part:SetAttribute("claimed", false)
		end
	end)
end

local function tryPickup(player, part)
	if part:GetAttribute("claimed") then
		return
	end
	-- Claim before the (yielding) backend call so overlapping touches can't
	-- double-pick the same drop.
	part:SetAttribute("claimed", true)

	local itemId = part:GetAttribute("itemId")
	local quantity = part:GetAttribute("quantity")
	local def = Items.get(itemId)
	local stackable = def and def.stackable or false

	-- Rolled items carry their instance meta on the drop (JSON attribute).
	local meta
	local rawMeta = part:GetAttribute("meta")
	if typeof(rawMeta) == "string" and rawMeta ~= "" then
		local decodeOk, decoded = pcall(HttpService.JSONDecode, HttpService, rawMeta)
		if decodeOk and typeof(decoded) == "table" then
			meta = decoded
		end
	end

	-- Stackables pick up partially (whatever fits); the rest stays on the
	-- ground with no fuss (decided UX: full inventory shows no toast).
	local ok, added = PlayerService.addItem(player, itemId, quantity, stackable, meta)
	if ok and added >= quantity then
		part:Destroy()
		notifyPickup(player, itemId, added)
	elseif ok and added > 0 then
		local left = quantity - added
		part:SetAttribute("quantity", left)
		local billboard = part:FindFirstChildOfClass("BillboardGui")
		local label = billboard and billboard:FindFirstChildOfClass("TextLabel")
		if label then
			label.Text = (def and def.name or itemId) .. (left > 1 and (" x" .. left) or "")
		end
		notifyPickup(player, itemId, added)
		releaseClaimLater(part)
	else
		releaseClaimLater(part)
	end
end

local function spawnDrop(itemId, quantity, position, opts)
	local def = Items.get(itemId)
	local spot = position + Vector3.new(math.random(-30, 30) / 10, 2, math.random(-30, 30) / 10)

	-- The root part is the touch/pickup zone; the item's miniature model is
	-- welded onto it (it follows the root's bob/spin CFrame updates).
	local part = Instance.new("Part")
	part.Name = "Drop"
	part.Size = Vector3.new(1.2, 1.2, 1.2)
	part.Anchored = true
	part.CanCollide = false
	part.CanQuery = false -- pickup works via Touched; don't block ground raycasts
	part.CFrame = CFrame.new(spot)
	part:SetAttribute("itemId", itemId)
	part:SetAttribute("quantity", quantity)
	part:SetAttribute("baseY", spot.Y)

	-- Thrown by a player: they lose pickup priority (see nearestEligiblePlayer).
	if opts and opts.droppedBy then
		part:SetAttribute("droppedBy", opts.droppedBy)
	end

	-- Rolled instance data rides the drop as JSON (attributes can't hold tables).
	local meta = opts and opts.meta
	if typeof(meta) == "table" then
		part:SetAttribute("meta", HttpService:JSONEncode(meta))
	end

	local scale = visualScale(itemId)
	if scale then
		part.Transparency = 1
		ArtKit.weld(part, ItemModels.get(itemId), scale)
	else
		part.Color = Color3.fromRGB(230, 200, 90)
		part.Material = Enum.Material.Neon
	end

	local billboard = Instance.new("BillboardGui")
	billboard.Size = UDim2.new(0, 80, 0, 20)
	billboard.StudsOffsetWorldSpace = Vector3.new(0, 1.4, 0)
	billboard.AlwaysOnTop = true
	billboard.Parent = part

	local label = Instance.new("TextLabel")
	label.Size = UDim2.new(1, 0, 1, 0)
	label.BackgroundTransparency = 1
	label.Font = Enum.Font.GothamBold
	label.TextSize = 13
	-- Above-common drops read in their tier's color; common stays plain
	-- white (the tier's beige is too dim against the world).
	local rarity = Rarity.forEntry({ meta = meta }, def)
	label.TextColor3 = rarity.hasGlow and rarity.textColor or Color3.new(1, 1, 1)
	label.TextStrokeTransparency = 0.4
	local displayName = def and def.name or itemId
	if typeof(meta) == "table" and meta.itemLevel then
		displayName = ("%s [Lv %d]"):format(displayName, meta.itemLevel)
	end
	label.Text = displayName .. (quantity > 1 and (" x" .. quantity) or "")
	label.Parent = billboard

	part.Parent = dropFolder

	task.delay(DROP_LIFETIME, function()
		if part.Parent then
			part:Destroy()
		end
	end)
end

-- Public: spawn a ground drop. Other systems (e.g. item stands) use this so
-- everything a player can pick up flows through the same claim/persist path.
-- opts: { droppedBy = userId } marks a player throw (they lose priority).
function DropService.spawn(itemId, quantity, position, opts)
	spawnDrop(itemId, quantity, position, opts)
end

function DropService.start()
	dropFolder = Instance.new("Folder")
	dropFolder.Name = "Drops"
	dropFolder.Parent = Workspace

	flyFolder = Instance.new("Folder")
	flyFolder.Name = "FlyingPickups"
	flyFolder.Parent = Workspace

	-- Spawn loot when an enemy dies: the regular table plus a chance at a
	-- rolled trait item leveled off the mob.
	EnemyService.onKilled(function(source, position, _killer, level)
		for _, drop in ipairs(rollLoot(source)) do
			spawnDrop(drop.itemId, drop.quantity, position)
		end
		local gearId, gearMeta = rollGear(source, level)
		if gearId then
			spawnDrop(gearId, 1, position, { meta = gearMeta })
		end
	end)

	-- Gathering: the harvested resource visibly flies from the node to the
	-- player (it's already in their inventory; this is pure show).
	GatheringService.onGathered(function(player, itemId, _amount, position)
		flyToPlayer(itemId, position, player)
	end)

	-- Drag-out-to-drop from the inventory UI: remove the stack (backend
	-- validates the position) and throw it in front of the character.
	local dropItem = Remotes.getFunction("DropItem")
	dropItem.OnServerInvoke = function(player, ref)
		if typeof(ref) ~= "table" then
			return { ok = false }
		end
		local containerId = ref.containerId
		local x, y = tonumber(ref.x), tonumber(ref.y)
		if (containerId ~= "main" and containerId ~= "equipment") or not x or not y then
			return { ok = false }
		end
		local ok, itemId, quantity, meta = PlayerService.dropItem(player, {
			containerId = containerId,
			x = math.floor(x),
			y = math.floor(y),
		})
		if not ok then
			return { ok = false }
		end
		notifyDrop(player, itemId, quantity)
		local character = player.Character
		local root = character and character:FindFirstChild("HumanoidRootPart")
		local position = root and (root.Position + root.CFrame.LookVector * 5 - Vector3.new(0, 2, 0))
			or Vector3.zero
		-- meta rides along so a thrown rolled item keeps its roll on the ground.
		spawnDrop(itemId, quantity, position, { droppedBy = player.UserId, meta = meta })
		return { ok = true }
	end

	-- Spin + bob the drops; magnet them onto the nearest eligible player.
	RunService.Heartbeat:Connect(function(dt)
		local t = os.clock()
		for _, part in ipairs(dropFolder:GetChildren()) do
			if not part:IsA("BasePart") then
				continue
			end
			local flying = false
			if not part:GetAttribute("claimed") then
				local target, root, dist = nearestEligiblePlayer(part)
				if target and root then
					if dist <= PICKUP_RANGE then
						-- tryPickup yields on the backend call; never in Heartbeat.
						task.spawn(tryPickup, target, part)
					else
						local direction = (root.Position - part.Position).Unit
						local newPos = part.Position + direction * math.min(MAGNET_SPEED * dt, dist)
						part:SetAttribute("baseY", newPos.Y)
						part.CFrame = CFrame.new(newPos) * CFrame.Angles(0, t * 2, 0)
						flying = true
					end
				end
			end
			if not flying then
				local baseY = part:GetAttribute("baseY") or part.Position.Y
				local y = baseY + math.sin(t * 3) * 0.3
				part.CFrame = CFrame.new(part.Position.X, y, part.Position.Z) * CFrame.Angles(0, t * 2, 0)
			end
		end
	end)
end

return DropService
