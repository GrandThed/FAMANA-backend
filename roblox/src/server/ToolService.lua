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

-- Optional per-item-type gate: function(player, def) -> boolean, checked
-- FIRST in activate() — before cooldown, sound, or animation. Returning
-- false means the Tool doesn't swing AT ALL this click: no animation, no
-- sound, no cooldown consumed, no activated handler call. This is for cases
-- where clicking shouldn't do anything at all (e.g. a bow/staff with
-- nothing locked in range — "attacking the air"), as opposed to
-- registerCanPlaySound, where the swing still happens but silently (e.g. out
-- of mana/arrows — the handler still runs to show its own warning toast).
local canSwingFor = {}

function ToolService.registerCanSwing(itemType, fn)
	canSwingFor[itemType] = fn
end

-- Optional per-item-type gate: function(player, def) -> boolean. Checked right
-- before playSwing plays its animation/sound; if it returns false, the swing
-- still counts (cooldown/animation happen normally, and the activated
-- handler still runs so it can show its own "no mana"/"no arrows" toast) but
-- the SwingRemote sound is skipped — e.g. staff/bow shouldn't make a
-- cast/draw noise when the player has no mana or arrows to actually fire.
local canPlaySoundFor = {}

function ToolService.registerCanPlaySound(itemType, fn)
	canPlaySoundFor[itemType] = fn
end

-- Optional per-item-type variant resolver: function(player, def) -> variant
-- key (e.g. "combo1"/"combo2"/"combo3") or nil for the default style. Called
-- ONLY once a swing actually passes the cooldown gate (see playSwing) so
-- state like combo progress advances exactly once per real swing — never on
-- a click that gets debounced away. The chosen variant is used both for the
-- cosmetic tween (SWING_STYLES) and forwarded to the activated handler so
-- e.g. EnemyService can apply the matching damage multiplier to the SAME
-- combo step the player saw/heard.
local swingVariantFor = {}

function ToolService.registerSwingVariant(itemType, fn)
	swingVariantFor[itemType] = fn
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
	-- Combo melee de 3 golpes (espadas, etc.): cada paso tiene su propia
	-- cosmética para que "se sienta" distinto pegar 1-2-3 en fila, no solo
	-- más daño. Resuelto por swingVariantFor["weapon"] (ver EnemyService's
	-- resolveWeaponVariant), que además decide el multiplicador de daño.
	combo1 = { rot = CFrame.Angles(math.rad(-60), 0, math.rad(-70)), time = 0.15 }, -- tajo diagonal (abajo-derecha)
	combo2 = { rot = CFrame.Angles(math.rad(-55), 0, math.rad(65)), time = 0.15 }, -- tajo diagonal opuesto (abajo-izquierda)
	combo3 = { rot = CFrame.Angles(math.rad(-115), 0, 0), time = 0.24 }, -- remate: golpe grande, más lento y con más peso
	-- "slash" queda como fallback genérico para melee sin variant resuelta.
	slash = { rot = CFrame.Angles(math.rad(-60), 0, math.rad(-70)), time = 0.15 }, -- diagonal cut
	chop = { rot = CFrame.Angles(math.rad(-100), 0, 0), time = 0.18 }, -- overhead chop

	-- Combo de 3 casteos (báculo/magia): mismo espíritu que combo1-3 de
	-- espada — dos gestos rápidos que alternan de lado y un remate más
	-- grande y lento. Resuelto por resolveWeaponVariant en EnemyService
	-- (rama ranged + damageKind == "magic").
	castCombo1 = { rot = CFrame.Angles(math.rad(-30), math.rad(12), 0), time = 0.18 }, -- alzada rápida, leve giro a la derecha
	castCombo2 = { rot = CFrame.Angles(math.rad(-34), math.rad(-14), 0), time = 0.18 }, -- alzada rápida, giro opuesto a la izquierda
	castCombo3 = { rot = CFrame.Angles(math.rad(-58), 0, 0), time = 0.28 }, -- remate: invocación grande por sobre la cabeza, más lenta
	-- "cast" queda como fallback genérico (placeable, o ranged sin variant resuelta).
	cast = { rot = CFrame.Angles(math.rad(-35), 0, 0), time = 0.22 }, -- staff raise

	-- Combo de 3 tiros (arco): dos tensadas cortas que alternan de lado
	-- (como pisando distinto con cada disparo) y una tensada final más
	-- profunda y lenta para el remate. Resuelto por resolveWeaponVariant
	-- (rama ranged + damageKind == "physical").
	drawCombo1 = { rot = CFrame.Angles(0, math.rad(-22), 0), time = 0.14 }, -- tensada corta hacia la izquierda
	drawCombo2 = { rot = CFrame.Angles(0, math.rad(20), math.rad(-6)), time = 0.14 }, -- tensada corta hacia la derecha
	drawCombo3 = { rot = CFrame.Angles(math.rad(-10), math.rad(-32), 0), time = 0.22 }, -- remate: tensada más profunda, más lenta
	-- "draw" queda como fallback genérico para ranged sin variant resuelta.
	draw = { rot = CFrame.Angles(0, math.rad(-25), 0), time = 0.16 }, -- bow draw-back
}

local function swingStyleFor(def, variant)
	if variant and SWING_STYLES[variant] then
		return SWING_STYLES[variant]
	end
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

-- The grip weld's TRUE rest pose (no swing rotation applied), captured once
-- per equip (see buildTool's tool.Equipped below) — NOT read live off
-- weld.C0 during a swing, since mid-tween that's already rotated. Every
-- swing tweens from this cached baseline and back to it, so rotations never
-- compound onto each other.
local restGripC0 = {} -- [userId] = CFrame

-- The in-flight swing tween, if any, so a new swing can cancel it before
-- starting — otherwise a swing that fires before the previous one's
-- reverses=true "return trip" finishes (easily possible: that return trip is
-- 2x style.time, e.g. 0.48s for the combo3 finisher, longer than the 0.4s
-- swing cooldown) reads a not-yet-rested C0 and stacks its own rotation on
-- top of it — the sword drifts a little further off its grip every hit until
-- it's clipping through the character.
local activeSwingTween = {} -- [userId] = Tween

-- Returns true if the swing passed the debounce (and was actually played).
-- This is the single source of truth for "did this Activated call count" —
-- callers must gate any damage/gather handler on the return value, not just
-- the cosmetic animation, or spam-clicking bypasses the cooldown entirely.
-- Second return value is the resolved variant (see registerSwingVariant),
-- so the caller can forward the SAME combo step to the activated handler.
local function playSwing(player, def, playSound, resolveVariant)
	if playSound == nil then
		playSound = true
	end
	local now = os.clock()
	local cooldown = swingCooldownFor(player, def)
	if now - (lastSwing[player.UserId] or 0) < cooldown then
		return false
	end
	lastSwing[player.UserId] = now

	-- Resolved only now that the swing is confirmed real (past the cooldown
	-- gate) — a debounced click must never advance combo progress.
	local variant = resolveVariant and resolveVariant(player, def) or nil

	-- Replicated so the client can draw a cooldown veil on the hotbar slot —
	-- same pattern as SpellService's SpellCd_<id> attributes (server-clock
	-- expiry + duration, since the effective cooldown varies with the Agile
	-- Hands attack-speed trait).
	player:SetAttribute("SwingCdExpiry", Workspace:GetServerTimeNow() + cooldown)
	player:SetAttribute("SwingCdDuration", cooldown)

	local character = player.Character
	if not character then
		return false, variant
	end

	-- Tell every nearby client to play the swing animation/sound locally
	-- (server-side LoadAnimation is not visible to other clients) — not
	-- just the activating player, so it's heard around them too. The combo
	-- variant (e.g. "combo3") doubles as the styleName here so CombatSfx can
	-- pick a matching sound/pitch per hit, same as "slash"/"draw"/"cast".
	local styleName = variant or "slash"
	if not variant then
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
	end
	if playSound then
		local root = character:FindFirstChild("HumanoidRootPart")
		if root then
			RemotesModule.fireNearby("SwingRemote", root.Position, Config.CombatSfxHearRadius, styleName)
		else
			SwingRemote:FireClient(player, styleName)
		end
	end

	-- Procedural grip-weld tween is cosmetic and fine to run on the server.
	local weld = gripWeld(character)
	if weld then
		local style = swingStyleFor(def, variant)

		-- Cancel any swing tween still in flight and snap back to the true
		-- rest pose before starting the next one (see restGripC0/
		-- activeSwingTween above) — always tween FROM the cached rest, never
		-- from the weld's live C0.
		local existingTween = activeSwingTween[player.UserId]
		if existingTween then
			existingTween:Cancel()
		end
		local rest = restGripC0[player.UserId]
		if not rest then
			rest = weld.C0
			restGripC0[player.UserId] = rest
		else
			weld.C0 = rest
		end

		local tween = TweenService:Create(
			weld,
			TweenInfo.new(style.time, Enum.EasingStyle.Quad, Enum.EasingDirection.Out, 0, true),
			{ C0 = rest * style.rot }
		)
		activeSwingTween[player.UserId] = tween
		tween:Play()
	end

	return true, variant
end

-- Fallback looks for equippables without an ItemModels entry yet.
local DEFAULT_SPECS = {
	weapon = { { name = "Handle", size = Vector3.new(0.35, 3, 0.35), color = "steel" } },
	tool = { { name = "Handle", size = Vector3.new(0.4, 3, 0.4), color = "trunk" } },
	placeable = { { name = "Handle", size = Vector3.new(0.8, 0.8, 0.8), color = "trunk" } },
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

	local specs = ItemModels.get(def.id) or DEFAULT_SPECS[def.type] or DEFAULT_SPECS.placeable
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
		-- Each weapon can have a different RightGripAttachment offset, so the
		-- cached rest pose from a previous tool doesn't apply here — force
		-- playSwing to recapture it fresh off the (now correct) weld.C0 on
		-- this tool's first swing.
		restGripC0[player.UserId] = nil
		local existingTween = activeSwingTween[player.UserId]
		if existingTween then
			existingTween:Cancel()
			activeSwingTween[player.UserId] = nil
		end
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
		local canSwing = canSwingFor[def.type]
		if canSwing and not canSwing(player, def) then
			return
		end
		local canPlaySound = canPlaySoundFor[def.type]
		local playSound = not canPlaySound or canPlaySound(player, def)
		local resolveVariant = swingVariantFor[def.type]
		local ok, variant = playSwing(player, def, playSound, resolveVariant)
		if not ok then
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
			handler(player, tool, def, variant)
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
		restGripC0[player.UserId] = nil
		activeSwingTween[player.UserId] = nil
	end)
end

return ToolService