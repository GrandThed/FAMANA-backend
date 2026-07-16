-- Turns equippable inventory items (weapons/tools) into Roblox Tools in the
-- player's hotbar. Fires a SwingRemote so the client plays the animation, and
-- dispatches to registered handlers so gathering (step 4) and combat (step 5) can hook in.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")
local Workspace = game:GetService("Workspace")

-- RemoteEvent used to tell the client which swing style to animate.
local Remotes = ReplicatedStorage:FindFirstChild("Remotes") or Instance.new("Folder", ReplicatedStorage)
Remotes.Name = "Remotes"
local SwingRemote = Remotes:FindFirstChild("SwingRemote") or Instance.new("RemoteEvent", Remotes)
SwingRemote.Name = "SwingRemote"

local Items = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Items"))
local ArtKit = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("ArtKit"))
local ItemModels = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("ItemModels"))
local Config = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Config"))
-- Aliased: `Remotes` above is already taken by the raw ReplicatedStorage
-- folder this file hand-rolls instead of using the shared factory module.
local RemotesModule = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Remotes"))
local PlayerService = require(script.Parent.PlayerService)

local ToolService = {}

-- Item types that become held Tools. "placeable" covers world-placed
-- deployables (Acampada) — equip it, aim, click to place; see CampService.
local EQUIPPABLE = { weapon = true, tool = true, placeable = true }

local SWING_COOLDOWN = 0.4

-- [itemType] = function(player, tool, def)  registered by later systems.
ToolService.activatedHandlers = {}

function ToolService.registerActivated(itemType, handler)
	ToolService.activatedHandlers[itemType] = handler
end

-- Optional hook (e.g. Agile Hands trait synergy): function(player) -> multiplier,
-- where the effective cooldown is SWING_COOLDOWN * multiplier. Lower = faster swings.
local swingCooldownMultFn = nil

function ToolService.registerSwingCooldownMult(fn)
	swingCooldownMultFn = fn
end

-- Optional per-item-type override, for item types whose REAL cooldown isn't
-- the generic combat swing cooldown (e.g. gathering tools: GatheringService
-- enforces its own longer GATHER_COOLDOWN). function(player) -> seconds.
-- Registering one here makes the animation AND the client-side cooldown
-- indicator match the actual rule instead of the 0.4s default — otherwise
-- the swing looks "ready" well before the handler will actually do anything.
local cooldownForType = {}

function ToolService.registerCooldownFor(itemType, fn)
	cooldownForType[itemType] = fn
end

local function swingCooldownFor(player, def)
	local override = def and cooldownForType[def.type]
	if override then
		return override(player)
	end
	local mult = swingCooldownMultFn and swingCooldownMultFn(player) or 1
	return SWING_COOLDOWN * mult
end

-- Per-player swing debounce so the animation can't be spammed.
local lastSwing = {}

-- A click that lands this close to the end of the cooldown gets queued and
-- fires the moment the cooldown expires, instead of being eaten (dropped
-- inputs read as lag, especially on the long gather cooldown).
local INPUT_BUFFER = 0.35

local pendingSwing = {} -- [userId] = true while a buffered activation waits

-- Procedural swing per item kind: the tool itself is rotated in the hand by
-- tweening the engine-made RightGrip weld out and back (same server-side
-- cosmetic-tween approach as the magic missile). Layered on top of the arm
-- animation so the swing reads even when the stock anim doesn't fit the rig.
local SWING_STYLES = {
	slash = { rot = CFrame.Angles(math.rad(-60), 0, math.rad(-70)), time = 0.15 }, -- diagonal cut
	chop = { rot = CFrame.Angles(math.rad(-100), 0, 0), time = 0.18 }, -- overhead chop
	cast = { rot = CFrame.Angles(math.rad(-35), 0, 0), time = 0.22 }, -- staff raise
	draw = { rot = CFrame.Angles(0, math.rad(-25), 0), time = 0.16 }, -- bow draw-back
}

local function swingStyleFor(def)
	if def.type == "tool" then
		return SWING_STYLES.chop
	elseif def.type == "placeable" then
		return SWING_STYLES.cast
	elseif def.weaponType == "ranged" then
		if def.damageKind == "physical" then
			return SWING_STYLES.draw
		end
		return SWING_STYLES.cast
	end
	return SWING_STYLES.slash
end

local function gripWeld(character)
	local hand = character:FindFirstChild("RightHand") -- R15
		or character:FindFirstChild("Right Arm") -- R6
	return hand and hand:FindFirstChild("RightGrip")
end

-- Returns true if the swing passed the debounce (and was actually played).
-- This is the single source of truth for "did this Activated call count" —
-- callers must gate any damage/gather handler on the return value, not just
-- the cosmetic animation, or spam-clicking bypasses the cooldown entirely.
local function playSwing(player, def)
	local now = os.clock()
	local cooldown = swingCooldownFor(player, def)
	if now - (lastSwing[player.UserId] or 0) < cooldown then
		return false
	end
	lastSwing[player.UserId] = now

	-- Replicated so the client can draw a cooldown veil on the hotbar slot —
	-- same pattern as SpellService's SpellCd_<id> attributes (server-clock
	-- expiry + duration, since the effective cooldown varies with the Agile
	-- Hands attack-speed trait).
	player:SetAttribute("SwingCdExpiry", Workspace:GetServerTimeNow() + cooldown)
	player:SetAttribute("SwingCdDuration", cooldown)

	local character = player.Character
	if not character then
		return
	end

	-- Tell every nearby client to play the swing animation/sound locally
	-- (server-side LoadAnimation is not visible to other clients) — not
	-- just the activating player, so it's heard around them too.
	local styleName = "slash"
	if def.type == "tool" then
		styleName = "chop"
	elseif def.type == "placeable" then
		styleName = "cast"
	elseif def.weaponType == "ranged" then
		if def.damageKind == "physical" then
			styleName = "draw"
		else
			styleName = "cast"
		end
	end
	local root = character:FindFirstChild("HumanoidRootPart")
	if root then
		RemotesModule.fireNearby("SwingRemote", root.Position, Config.CombatSfxHearRadius, styleName)
	else
		SwingRemote:FireClient(player, styleName)
	end

	-- Procedural grip-weld tween is cosmetic and fine to run on the server.
	local weld = gripWeld(character)
	if weld then
		local style = swingStyleFor(def)
		local tween = TweenService:Create(
			weld,
			TweenInfo.new(style.time, Enum.EasingStyle.Quad, Enum.EasingDirection.Out, 0, true),
			{ C0 = weld.C0 * style.rot }
		)
		tween:Play()
	end

	return true
end

-- Fallback looks for equippables without an ItemModels entry yet.
local DEFAULT_SPECS = {
	weapon = { { name = "Handle", size = Vector3.new(0.35, 3, 0.35), color = "steel" } },
	tool = { { name = "Handle", size = Vector3.new(0.4, 3, 0.4), color = "trunk" } },
}

-- Builds the Tool's part assembly: if a custom model exists in
-- ReplicatedStorage.Assets with the itemId, we clone it and ensure it has a
-- Handle part with all other parts welded to it. Otherwise, we fallback to
-- the shared ItemModels catalog.
local function buildHandle(def)
	local assets = ReplicatedStorage:FindFirstChild("Assets")
	local customModel = assets and assets:FindFirstChild(def.id)

	if customModel then
		local clone = customModel:Clone()
		if clone:IsA("BasePart") then
			clone.Name = "Handle"
			clone.Anchored = false
			clone.CanCollide = false
			return clone
		elseif clone:IsA("Model") then
			local handle = clone:FindFirstChild("Handle")
			if not handle and clone.PrimaryPart then
				handle = clone.PrimaryPart
				handle.Name = "Handle"
			elseif not handle then
				handle = clone:FindFirstChildOfClass("BasePart")
				if handle then
					handle.Name = "Handle"
				end
			end

			if not handle then
				handle = Instance.new("Part")
				handle.Name = "Handle"
				handle.Size = Vector3.new(0.5, 0.5, 0.5)
				handle.Transparency = 1
				handle.CanCollide = false
				handle.Parent = clone
			end

			handle.Anchored = false

			for _, part in ipairs(clone:GetDescendants()) do
				if part:IsA("BasePart") and part ~= handle then
					part.Anchored = false
					part.CanCollide = false

					-- Child check, not GetJoints(): the clone isn't parented to a
					-- WorldModel yet so GetJoints warns (and returns nothing), and
					-- welds conventionally live under the part anyway.
					local hasWeld = part:FindFirstChildWhichIsA("WeldConstraint") ~= nil
						or part:FindFirstChildWhichIsA("Weld") ~= nil

					if not hasWeld then
						local weld = Instance.new("WeldConstraint")
						weld.Part0 = handle
						weld.Part1 = part
						weld.Parent = part
					end
				end
			end

			for _, child in ipairs(clone:GetChildren()) do
				if child ~= handle then
					child.Parent = handle
				end
			end

			return handle
		end
	end

	local specs = ItemModels.get(def.id) or DEFAULT_SPECS[def.type]
	local handle = ArtKit.part(specs[1])
	handle.Name = "Handle"
	handle.Anchored = false
	local details = table.clone(specs)
	table.remove(details, 1)
	ArtKit.weld(handle, details)
	return handle
end

-- ---- held-item tracking (the hand rule, docs/TRAITS_V2.md §1.4) -----------
-- Which item is actually OUT in the player's hands right now. SynergyService
-- swaps weapon/tool trait contributions on this (armor/rings always count).
local heldItem = {} -- [userId] = itemId of the equipped Tool, or nil

local heldChangedCallbacks = {}
function ToolService.onHeldChanged(fn)
	table.insert(heldChangedCallbacks, fn)
end

function ToolService.getHeldItemId(player)
	return heldItem[player.UserId]
end

local function setHeld(player, itemId)
	if heldItem[player.UserId] == itemId then
		return
	end
	heldItem[player.UserId] = itemId
	for _, fn in ipairs(heldChangedCallbacks) do
		task.spawn(fn, player)
	end
end

local function buildTool(player, itemId)
	local def = Items.get(itemId)
	local tool = Instance.new("Tool")
	tool.Name = def.name
	tool.RequiresHandle = true
	tool.CanBeDropped = false
	tool:SetAttribute("itemId", itemId)
	tool.Equipped:Connect(function()
		setHeld(player, itemId)
	end)
	tool.Unequipped:Connect(function()
		if heldItem[player.UserId] == itemId then
			setHeld(player, nil)
		end
	end)
	local handle = buildHandle(def)
	handle.Parent = tool

	-- Automatically set the Grip offset to match the RightGripAttachment if present in the Handle
	local gripAttachment = handle:FindFirstChild("RightGripAttachment")
	if gripAttachment and gripAttachment:IsA("Attachment") then
		tool.Grip = gripAttachment.CFrame
	end

	-- Any "Orb" part in the model glows (e.g. the magic staff's head, the
	-- torch's flame). Range/brightness default to the staff's subtle glow;
	-- an item can override them (see torch's orbLightRange/orbLightBrightness
	-- in Items.lua) to shine brighter/further without touching this shared path.
	local orb = handle:FindFirstChild("Orb")
	if orb then
		local light = Instance.new("PointLight")
		light.Color = orb.Color
		light.Range = def.orbLightRange or 8
		light.Brightness = def.orbLightBrightness or 2
		light.Parent = orb
	end

	-- playSwing IS the debounce: if it returns false we're still inside
	-- the cooldown window, so the handler (damage/gather) must not run
	-- either — otherwise spam-clicking deals damage on every click even
	-- though the animation is being throttled. A click in the cooldown's
	-- tail (INPUT_BUFFER) is queued and re-fired at expiry instead.
	local function activate()
		if not playSwing(player, def) then
			local remaining = swingCooldownFor(player, def)
				- (os.clock() - (lastSwing[player.UserId] or 0))
			if remaining > 0 and remaining <= INPUT_BUFFER and not pendingSwing[player.UserId] then
				pendingSwing[player.UserId] = true
				task.delay(remaining + 0.02, function()
					pendingSwing[player.UserId] = nil
					-- Only if this exact tool is still the one in hand.
					if tool.Parent == player.Character then
						activate()
					end
				end)
			end
			return
		end
		local handler = ToolService.activatedHandlers[def.type]
		if handler then
			handler(player, tool, def)
		end
	end

	tool.Activated:Connect(activate)

	return tool
end

local function heldTools(player)
	local tools = {}
	local backpack = player:FindFirstChildOfClass("Backpack")
	if backpack then
		for _, child in ipairs(backpack:GetChildren()) do
			if child:IsA("Tool") then
				table.insert(tools, child)
			end
		end
	end
	if player.Character then
		for _, child in ipairs(player.Character:GetChildren()) do
			if child:IsA("Tool") then
				table.insert(tools, child)
			end
		end
	end
	return tools
end

-- Reconcile the player's Tools with the equippable items in their inventory.
function ToolService.syncTools(player)
	local profile = PlayerService.get(player)
	local backpack = player:FindFirstChildOfClass("Backpack")
	if not profile or not backpack then
		return
	end

	local desired = {}
	for _, entry in ipairs(profile.inventory) do
		local def = Items.get(entry.itemId)
		if def and EQUIPPABLE[def.type] then
			desired[entry.itemId] = true
		end
	end

	-- Drop tools that are no longer wanted; note which desired ones we already have.
	local have = {}
	for _, tool in ipairs(heldTools(player)) do
		local itemId = tool:GetAttribute("itemId")
		if desired[itemId] and not have[itemId] then
			have[itemId] = true
		else
			tool:Destroy()
		end
	end

	-- Create any missing tools.
	for itemId in pairs(desired) do
		if not have[itemId] then
			buildTool(player, itemId).Parent = backpack
		end
	end
end

function ToolService.start()
	-- Rebuild tools whenever the inventory changes (equippable items gained/lost).
	PlayerService.onInventoryChanged(function(player)
		ToolService.syncTools(player)
	end)

	local function watchPlayer(player)
		player.CharacterAdded:Connect(function()
			-- Backpack is recreated on every (re)spawn; wait for it then sync.
			local backpack = player:WaitForChild("Backpack", 5)
			if backpack then
				ToolService.syncTools(player)
			end
		end)
		if player.Character and player:FindFirstChildOfClass("Backpack") then
			ToolService.syncTools(player)
		end
	end

	Players.PlayerAdded:Connect(watchPlayer)
	-- Players who connected while the server was still booting fired their
	-- PlayerAdded before the connect above (same sweep as PlayerService) —
	-- without this their hotbar has no Tools until the first inventory change.
	for _, player in ipairs(Players:GetPlayers()) do
		watchPlayer(player)
	end

	Players.PlayerRemoving:Connect(function(player)
		lastSwing[player.UserId] = nil
		heldItem[player.UserId] = nil
		pendingSwing[player.UserId] = nil
	end)
end

return ToolService