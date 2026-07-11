-- Camp furniture: crafting "cofre_campamento" or "carpa_campamento" (shared/
-- Recipes.lua) lets a player plant them, but ONLY inside the zone of an
-- Acampada they can currently access (their own, or their party's — see
-- CampService.campFor). No count limit per camp, the zone's own footprint
-- (30x30 studs) is the only budget, same spirit as the request. Furniture
-- lives and dies with its camp: CampService.onTeardown tears every piece
-- down when the camp expires.
--
-- The chest is real shared storage — its own small grid (Config.CampFurniture
-- .chestColumns x .chestRows), same ItemGrid component the inventory/store
-- use on the client (client/ChestUI.lua). It's in-memory only, same
-- philosophy as the camp itself: NOT persisted to the backend. If the camp
-- expires with items still inside, they're dropped on the ground at the
-- camp's center (DropService) rather than deleted — nothing is silently
-- lost. The tent is decorative only for now.
--
-- Placement: PlaceFurniture (RemoteFunction) mirrors CampService.PlaceAcampada
-- — client sends intent (itemId, x, z), server re-validates camp access,
-- zone bounds, distance, spacing from other furniture, and item ownership.
-- Chest transfers: ChestDeposit / ChestWithdraw (RemoteFunctions) move a
-- whole stack at a time between the player's real (backend-authoritative)
-- inventory and the chest's local grid — deposits are all-or-nothing
-- (rejected if the chest can't fit the WHOLE stack), withdrawals fill
-- whatever room the player's inventory has (partial fill), same posture as
-- item pickups.

local Players = game:GetService("Players")
local Workspace = game:GetService("Workspace")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared:WaitForChild("Config"))
local ArtKit = require(Shared:WaitForChild("ArtKit"))
local Items = require(Shared:WaitForChild("Items"))
local Remotes = require(Shared:WaitForChild("Remotes"))

local PlayerService = require(script.Parent.PlayerService)
local CampService = require(script.Parent.CampService)
local DropService = require(script.Parent.DropService)

local CampFurnitureService = {}

local CAMP = Config.Camp
local FURNITURE = Config.CampFurniture
local MAX_CHEST_DISTANCE = 10 -- studs; using the chest, not placing it

-- itemId -> what it becomes. Extend this table (+ Items/Recipes/ItemModels)
-- to add more furniture later.
local FURNITURE_DEFS = {
	cofre_campamento = { kind = "chest" },
	carpa_campamento = { kind = "tent" },
}

local CHEST_SPECS = {
	{ name = "Base", size = Vector3.new(2, 1, 1.4), color = "trunk", primary = true },
	{ name = "Lid", size = Vector3.new(2.1, 0.35, 1.5), offset = Vector3.new(0, 0.68, 0), color = "trunkDark" },
	{ name = "BandFront", size = Vector3.new(2.05, 0.2, 0.1), offset = Vector3.new(0, 0.1, 0.72), color = "steelDark" },
	{ name = "BandBack", size = Vector3.new(2.05, 0.2, 0.1), offset = Vector3.new(0, 0.1, -0.72), color = "steelDark" },
	{ name = "Lock", size = Vector3.new(0.25, 0.25, 0.15), offset = Vector3.new(0, 0.5, 0.78), color = "gold" },
}

local TENT_SPECS = {
	{ name = "Base", size = Vector3.new(3, 0.2, 3), offset = Vector3.new(0, 0.1, 0), color = "dirt", canCollide = false, primary = true },
	{ name = "PoleL", size = Vector3.new(0.25, 2.2, 0.25), offset = Vector3.new(-1.3, 1.2, 0), color = "trunkDark" },
	{ name = "PoleR", size = Vector3.new(0.25, 2.2, 0.25), offset = Vector3.new(1.3, 1.2, 0), color = "trunkDark" },
	{ name = "RoofL", shape = "Wedge", size = Vector3.new(3, 1.6, 2.6), offset = Vector3.new(-0.75, 2.1, 0), rot = Vector3.new(0, 90, 0), color = "leather" },
	{ name = "RoofR", shape = "Wedge", size = Vector3.new(3, 1.6, 2.6), offset = Vector3.new(0.75, 2.1, 0), rot = Vector3.new(0, -90, 0), color = "leatherDark" },
	{ name = "Flap", size = Vector3.new(0.1, 1.4, 1.6), offset = Vector3.new(0, 1.0, 0), color = "leatherDark", canCollide = false },
}

local furnitureFolder
local notifyRemote
local chestUpdatedRemote

-- [ownerUserId] = { [pieceId] = piece }; piece = { id, itemId, kind, center,
-- ownerId, model, storage? (chest only) }
local piecesByCamp = {}
-- [pieceId] = piece; chests only, for O(1) lookup from the transfer remotes
local chestsById = {}
local nextPieceId = 0

local function notify(player, message)
	if player and notifyRemote then
		notifyRemote:FireClient(player, message)
	end
end

local function findGroundY(x, z)
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	params.FilterDescendantsInstances = { furnitureFolder }
	local result = Workspace:Raycast(Vector3.new(x, 300, z), Vector3.new(0, -1000, 0), params)
	return result and result.Position.Y or 0
end

-- ---- chest storage (in-memory grid, no rotation — kept simple) -------------

local function rectsOverlap(ax, ay, aw, ah, bx, by, bw, bh)
	return ax < bx + bw and bx < ax + aw and ay < by + bh and by < ay + ah
end

local function footprintFree(storage, planned, x, y, w, h)
	if x < 0 or y < 0 or x + w > storage.columns or y + h > storage.rows then
		return false
	end
	for _, entry in pairs(storage.items) do
		local ew, eh = Items.sizeFor(entry.itemId, false)
		if rectsOverlap(x, y, w, h, entry.x, entry.y, ew, eh) then
			return false
		end
	end
	for _, entry in ipairs(planned) do
		if rectsOverlap(x, y, w, h, entry.x, entry.y, entry.w, entry.h) then
			return false
		end
	end
	return true
end

-- Plans fitting `quantity` of itemId into the chest — tops up existing
-- same-item stacks first, then finds first-fit cells for the remainder.
-- Returns nil if it doesn't ALL fit (nothing is mutated); otherwise a plan
-- for applyDeposit to commit.
local function planDeposit(storage, itemId, quantity)
	local maxStack = Items.maxStackFor(itemId)
	local remaining = quantity

	local topUps = {}
	for id, entry in pairs(storage.items) do
		if remaining <= 0 then
			break
		end
		if entry.itemId == itemId and entry.quantity < maxStack then
			local room = maxStack - entry.quantity
			local take = math.min(room, remaining)
			topUps[id] = take
			remaining -= take
		end
	end

	local newSlots = {}
	if remaining > 0 then
		local w, h = Items.sizeFor(itemId, false)
		for y = 0, storage.rows - h do
			for x = 0, storage.columns - w do
				if remaining <= 0 then
					break
				end
				if footprintFree(storage, newSlots, x, y, w, h) then
					local take = math.min(maxStack, remaining)
					table.insert(newSlots, { x = x, y = y, w = w, h = h, quantity = take })
					remaining -= take
				end
			end
			if remaining <= 0 then
				break
			end
		end
	end

	if remaining > 0 then
		return nil
	end
	return { topUps = topUps, newSlots = newSlots }
end

local function applyDeposit(storage, itemId, plan)
	for id, amount in pairs(plan.topUps) do
		storage.items[id].quantity += amount
	end
	for _, slot in ipairs(plan.newSlots) do
		storage.nextLocalId += 1
		storage.items[storage.nextLocalId] = { itemId = itemId, quantity = slot.quantity, x = slot.x, y = slot.y }
	end
end

local function snapshotChest(storage)
	local list = {}
	for id, entry in pairs(storage.items) do
		table.insert(list, { id = id, itemId = entry.itemId, quantity = entry.quantity, x = entry.x, y = entry.y })
	end
	return list
end

local function broadcastChest(piece)
	local snapshot = snapshotChest(piece.storage)
	for _, otherPlayer in ipairs(Players:GetPlayers()) do
		local camp = CampService.campFor(otherPlayer)
		if camp and camp.ownerUserId == piece.ownerId then
			chestUpdatedRemote:FireClient(otherPlayer, { chestId = piece.id, items = snapshot })
		end
	end
end

-- Player must currently have camp access (own/party) to THIS chest's camp,
-- and be standing close to it — same posture as CampService's placement
-- distance check, just re-checked against the piece instead of a claimed
-- ground point.
local function nearOwnChest(player, piece)
	local camp = CampService.campFor(player)
	if not camp or camp.ownerUserId ~= piece.ownerId then
		return false
	end
	local character = player.Character
	local root = character and character:FindFirstChild("HumanoidRootPart")
	if not root or not piece.model or not piece.model.PrimaryPart then
		return false
	end
	return (root.Position - piece.model.PrimaryPart.Position).Magnitude <= MAX_CHEST_DISTANCE
end

-- ---- building ---------------------------------------------------------------

local function buildPiece(kind, itemId, center, ownerId)
	nextPieceId += 1
	local id = nextPieceId
	local origin = CFrame.new(center)
	local piece = { id = id, itemId = itemId, kind = kind, center = center, ownerId = ownerId }

	if kind == "chest" then
		local model = ArtKit.build("Cofre", origin, CHEST_SPECS)
		model.Parent = furnitureFolder
		piece.model = model
		piece.storage = {
			columns = FURNITURE.chestColumns,
			rows = FURNITURE.chestRows,
			items = {}, -- [localId] = { itemId, quantity, x, y }
			nextLocalId = 0,
		}
		chestsById[id] = piece

		local prompt = Instance.new("ProximityPrompt")
		prompt.ActionText = "Open"
		prompt.ObjectText = "Chest"
		prompt.HoldDuration = 0.15
		prompt.MaxActivationDistance = MAX_CHEST_DISTANCE
		prompt.RequiresLineOfSight = false
		prompt.Parent = model.PrimaryPart

		local openChest = Remotes.get("OpenChest")
		prompt.Triggered:Connect(function(triggeringPlayer)
			if not nearOwnChest(triggeringPlayer, piece) then
				notify(triggeringPlayer, "You need to be in this camp's party to use its chest.")
				return
			end
			openChest:FireClient(triggeringPlayer, {
				chestId = id,
				columns = piece.storage.columns,
				rows = piece.storage.rows,
				items = snapshotChest(piece.storage),
				position = model.PrimaryPart.Position,
			})
		end)
	elseif kind == "tent" then
		local model = ArtKit.build("Carpa", origin, TENT_SPECS)
		model.Parent = furnitureFolder
		piece.model = model
	end

	return piece
end

-- ---- remotes ------------------------------------------------------------

local function handlePlaceFurniture(player, itemId, x, z)
	if typeof(itemId) ~= "string" or typeof(x) ~= "number" or typeof(z) ~= "number" then
		return { ok = false, error = "bad_request" }
	end
	local def = FURNITURE_DEFS[itemId]
	if not def then
		return { ok = false, error = "bad_request" }
	end

	local camp = CampService.campFor(player)
	if not camp then
		notify(player, "You need an active Acampada to place that.")
		return { ok = false, error = "no_camp" }
	end

	local character = player.Character
	local root = character and character:FindFirstChild("HumanoidRootPart")
	if not root then
		return { ok = false, error = "no_character" }
	end

	-- Anti-exploit: never trust the client's claimed point (same posture as
	-- CampService/CraftingService/ToolService).
	local flatDistance = (Vector3.new(x, root.Position.Y, z) - root.Position).Magnitude
	if flatDistance > CAMP.maxPlacementDistance then
		notify(player, "Too far away to place it there.")
		return { ok = false, error = "too_far" }
	end

	local half = CampService.ZONE_HALF
	if math.abs(x - camp.center.X) > half or math.abs(z - camp.center.Z) > half then
		notify(player, "Furniture has to go inside the camp's zone.")
		return { ok = false, error = "outside_zone" }
	end

	local pieces = piecesByCamp[camp.ownerUserId]
	if pieces then
		for _, piece in pairs(pieces) do
			local dx, dz = piece.center.X - x, piece.center.Z - z
			if math.sqrt(dx * dx + dz * dz) < FURNITURE.minSpacing then
				notify(player, "Too close to another piece of furniture.")
				return { ok = false, error = "too_close" }
			end
		end
	end

	if PlayerService.getItemCount(player, itemId) < 1 then
		notify(player, "You don't have that to place.")
		return { ok = false, error = "missing_item" }
	end
	if not PlayerService.removeItem(player, itemId, 1) then
		notify(player, "You don't have that to place.")
		return { ok = false, error = "missing_item" }
	end

	local center = Vector3.new(x, findGroundY(x, z), z)
	local piece = buildPiece(def.kind, itemId, center, camp.ownerUserId)

	piecesByCamp[camp.ownerUserId] = piecesByCamp[camp.ownerUserId] or {}
	piecesByCamp[camp.ownerUserId][piece.id] = piece

	local itemDef = Items.get(itemId)
	notify(player, (itemDef and itemDef.name or itemId) .. " placed.")
	return { ok = true }
end

local function handleChestDeposit(player, chestId, ref)
	local piece = chestsById[tonumber(chestId)]
	if not piece then
		return { ok = false, error = "bad_request" }
	end
	if not nearOwnChest(player, piece) then
		return { ok = false, error = "too_far" }
	end
	if typeof(ref) ~= "table" then
		return { ok = false, error = "bad_request" }
	end
	local x, y = tonumber(ref.x), tonumber(ref.y)
	if not x or not y then
		return { ok = false, error = "bad_request" }
	end
	x, y = math.floor(x), math.floor(y)

	local profile = PlayerService.get(player)
	if not profile then
		return { ok = false, error = "offline" }
	end
	local entry
	for _, candidate in ipairs(profile.inventory) do
		if candidate.containerId == "main" and candidate.x == x and candidate.y == y then
			entry = candidate
			break
		end
	end
	if not entry then
		return { ok = false, error = "bad_line" }
	end
	if entry.meta then
		-- Keep the chest simple for now: no rolled gear instances.
		notify(player, "Can't store that in a chest yet.")
		return { ok = false, error = "not_supported" }
	end

	local plan = planDeposit(piece.storage, entry.itemId, entry.quantity)
	if not plan then
		notify(player, "The chest doesn't have room for that.")
		return { ok = false, error = "chest_full" }
	end

	local ok, itemId, quantity = PlayerService.dropItem(player, { containerId = "main", x = x, y = y })
	if not ok or not itemId then
		return { ok = false, error = "bad_line" }
	end

	applyDeposit(piece.storage, itemId, plan)
	broadcastChest(piece)
	return { ok = true }
end

local function handleChestWithdraw(player, chestId, localId)
	local piece = chestsById[tonumber(chestId)]
	if not piece then
		return { ok = false, error = "bad_request" }
	end
	if not nearOwnChest(player, piece) then
		return { ok = false, error = "too_far" }
	end
	localId = tonumber(localId)
	local entry = localId and piece.storage.items[localId]
	if not entry then
		return { ok = false, error = "bad_line" }
	end

	-- Partial fill, same posture as picking up a ground drop: whatever room
	-- the player's inventory has, they get; the rest stays in the chest.
	local ok, added = PlayerService.addItem(player, entry.itemId, entry.quantity, true)
	if not ok or added <= 0 then
		notify(player, "Not enough room in your inventory.")
		return { ok = false, error = "no_space" }
	end

	entry.quantity -= added
	if entry.quantity <= 0 then
		piece.storage.items[localId] = nil
	end
	broadcastChest(piece)
	return { ok = true, added = added }
end

function CampFurnitureService.start()
	notifyRemote = Remotes.get("Notify")
	chestUpdatedRemote = Remotes.get("ChestUpdated")

	furnitureFolder = Instance.new("Folder")
	furnitureFolder.Name = "CampFurniture"
	furnitureFolder.Parent = Workspace

	CampService.onTeardown(function(ownerId, camp)
		local pieces = piecesByCamp[ownerId]
		if not pieces then
			return
		end
		piecesByCamp[ownerId] = nil
		for _, piece in pairs(pieces) do
			if piece.kind == "chest" then
				chestsById[piece.id] = nil
				-- Nothing gets silently deleted: whatever's left in the
				-- chest lands on the ground at the (now-gone) camp's center.
				for _, entry in pairs(piece.storage.items) do
					DropService.spawn(
						entry.itemId,
						entry.quantity,
						camp.center + Vector3.new(math.random(-30, 30) / 10, 2, math.random(-30, 30) / 10)
					)
				end
			end
			if piece.model then
				piece.model:Destroy()
			end
		end
	end)

	local placeFurniture = Remotes.getFunction("PlaceFurniture")
	placeFurniture.OnServerInvoke = handlePlaceFurniture

	local chestDeposit = Remotes.getFunction("ChestDeposit")
	chestDeposit.OnServerInvoke = handleChestDeposit

	local chestWithdraw = Remotes.getFunction("ChestWithdraw")
	chestWithdraw.OnServerInvoke = handleChestWithdraw
end

return CampFurnitureService
