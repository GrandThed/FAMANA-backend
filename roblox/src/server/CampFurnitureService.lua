-- Camp furniture: crafting "cofre_campamento", "carpa_campamento",
-- "crafting_table", or "simple_forge" (shared/Recipes.lua) lets a player
-- plant them, but ONLY inside the zone of an Acampada they can currently
-- access (their own, or their party's — see CampService.campFor). Budget is
-- the zone's footprint (tier-dependent) AND a max piece count per tier
-- (Config.Camp.tiers[tier].maxFurniture, docs/CAMP_TIERS.md §2).
--
-- crafting_table/simple_forge are real workbenches while planted: they
-- register with CraftingService (registerStation/moveStation/
-- unregisterStation) under the same station id ("crafting_table"/
-- "simple_forge") as the fixed ones in town, so station-gated recipes
-- unlock near either kind — CraftingService doesn't know or care which.
--
-- Persistence: furniture doesn't live/die with the CAMP INSTANCE anymore —
-- it lives with the OWNER. Whenever a camp is torn down (CampService.
-- onTeardown), the current layout (piece positions relative to the camp
-- center, plus chest contents) is snapshotted and saved via
-- PlayerService.setCampLayout. Whenever that owner plants a NEW Acampada
-- (CampService.onPlace), the saved layout is rebuilt exactly. Nothing is
-- ever dropped on the ground or destroyed — nothing "breaks", it just
-- disappears with the old camp and reappears with the next one.
--
-- The chest is real shared storage — its own small grid (Config.CampFurniture
-- .chestColumns x .chestRows), same ItemGrid component the inventory/store
-- use on the client (client/ChestUI.lua).
--
-- Placement: PlaceFurniture (RemoteFunction) mirrors CampService.PlaceAcampada
-- — client sends intent (itemId, x, z), server re-validates camp access,
-- zone bounds, distance, spacing from other furniture, and item ownership.
-- Once placed, a piece can be repositioned (MoveFurniture) or returned to
-- the owner's inventory (PickupFurniture, chest must be empty first) via the
-- "Manage" ProximityPrompt — see client/FurnitureManageUI.lua.
-- Chest transfers: ChestDeposit / ChestWithdraw (RemoteFunctions) move a
-- whole stack at a time between the player's real (backend-authoritative)
-- inventory and the chest's local grid — deposits are all-or-nothing
-- (rejected if the chest can't fit the WHOLE stack), withdrawals fill
-- whatever room the player's inventory has (partial fill), same posture as
-- item pickups.

local Players = game:GetService("Players")
local Workspace = game:GetService("Workspace")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared:WaitForChild("Config"))
local ArtKit = require(Shared:WaitForChild("ArtKit"))
local Items = require(Shared:WaitForChild("Items"))
local Remotes = require(Shared:WaitForChild("Remotes"))

local DayNightService = require(script.Parent.DayNightService)
local MeshAssetService = require(script.Parent.MeshAssetService)
local PlayerService = require(script.Parent.PlayerService)
local CampService = require(script.Parent.CampService)
local CraftingService = require(script.Parent.CraftingService)
local SleepingService = require(script.Parent.SleepingService)
local SittingService = require(script.Parent.SittingService)
local GuildPlotService = require(script.Parent.GuildPlotService)

local CampFurnitureService = {}

local lightSources = {} -- [model] = { light, particle, defaultBrightness }
local isCurrentNight = false

local function registerLightSource(model, light, particle, defaultBrightness)
	lightSources[model] = {
		light = light,
		particle = particle,
		defaultBrightness = defaultBrightness,
	}

	local isNight = DayNightService.isNight()
	if isNight then
		light.Enabled = true
		light.Brightness = defaultBrightness
		if particle then
			particle.Enabled = true
		end
	else
		light.Enabled = false
		light.Brightness = 0
		if particle then
			particle.Enabled = false
		end
	end
end

function CampFurnitureService.setNightLighting(isNight)
	isCurrentNight = isNight
	for model, data in pairs(lightSources) do
		if model and model.Parent then
			if isNight then
				data.light.Enabled = true
				TweenService:Create(data.light, TweenInfo.new(1.5), { Brightness = data.defaultBrightness }):Play()
				if data.particle then
					data.particle.Enabled = true
				end
			else
				local tween = TweenService:Create(data.light, TweenInfo.new(1.5), { Brightness = 0 })
				tween:Play()
				tween.Completed:Connect(function()
					if not isCurrentNight and data.light and data.light.Parent then
						data.light.Enabled = false
					end
				end)
				if data.particle then
					data.particle.Enabled = false
				end
			end
		else
			lightSources[model] = nil
		end
	end
end

local CAMP = Config.Camp
local FURNITURE = Config.CampFurniture
local MAX_CHEST_DISTANCE = 10 -- studs; using the chest, not placing it
local AUTOSAVE_INTERVAL = 120 -- seconds; see the loop in start() below

-- itemId -> what it becomes. Extend this table (+ Items/Recipes/ItemModels)
-- to add more furniture later. `station`, when present, is the id this
-- piece registers with CraftingService while it's standing (see buildPiece)
-- — the exact same station a matching fixed world workbench answers to, so
-- a recipe requiring "crafting_table" doesn't care whether the nearby one is
-- the town's or a camp-planted one.
local FURNITURE_DEFS = {
	cofre_campamento = { kind = "chest" },
	cofre_gremio = { kind = "guild_chest" },
	puesto_mercado = { kind = "market" },
	-- Purely decorative, no station — the first "cosmetic" piece, predates
	-- the tier system so it's not gated (minCampTier absent = tier 0 ok).
	-- Counts toward coziness (§3) like the newer cosmetics below.
	carpa_campamento = { kind = "tent", cosmetic = true },
	crafting_table = { kind = "crafting_table", station = "crafting_table" },
	simple_forge = { kind = "forge", station = "simple_forge" },
	-- Plantable from camp tier 1 onward (docs/CAMP_TIERS.md §7) —
	-- deliberately early so cooking is testable well before endgame, not
	-- gated behind the same tier as the tripod campfire dressing.
	-- station == itemId, same convention as crafting_table/simple_forge
	-- above (CraftUI.lua's station label assumes this to look up a
	-- friendly name via Items.get(def.station)).
	olla_campamento = { kind = "cauldron", station = "olla_campamento", minCampTier = 1 },

	-- Cosmetics (docs/CAMP_TIERS.md §4): no station, `cosmetic = true` so
	-- they count toward coziness (§3 — see the regen hook in start() below).
	-- Gated by minCampTier same as the cauldron. This is a starter set, not
	-- the full catalog from the doc (banner/watchtower/statue/garden are
	-- future content, same "ships functional but not fully populated"
	-- pattern as the cauldron's still-empty recipe list).
	alfombra_campamento = { kind = "rug", cosmetic = true, minCampTier = 1 },
	farol_campamento = { kind = "lantern", cosmetic = true, minCampTier = 1 },
	trofeo_campamento = { kind = "trophy", cosmetic = true, minCampTier = 2 },
	bolsa_dormir = { kind = "bed", cosmetic = true },
	cama_campamento = { kind = "bed", cosmetic = true },
	silla_campamento = { kind = "chair", cosmetic = true },
	banco_campamento = { kind = "chair", cosmetic = true },
	mesa_investigacion_gremio = { kind = "guild_research" },
	antorcha_campamento = { kind = "torch", cosmetic = true },
	hoguera_gremio = { kind = "campfire", cosmetic = true },
	lampara_gremio = { kind = "lamp", cosmetic = true },
	mesa_arquitectura_gremio = { kind = "guild_architecture", station = "mesa_arquitectura_gremio" },
	maceta_hierbas = { kind = "planter", cosmetic = true },
	letrero_bienvenida = { kind = "welcome_sign", cosmetic = true },
	portal_gremio = { kind = "guild_portal" },
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

-- Same shapes as CraftingService's fixed Workbench_crafting_table so a
-- camp-planted one looks like the town's.
local CRAFTING_TABLE_SPECS = {
	{ name = "Top", size = Vector3.new(3.2, 0.3, 1.8), offset = Vector3.new(0, 1.55, 0), color = "trunk", primary = true },
	{ name = "LegA", size = Vector3.new(0.3, 1.5, 0.3), offset = Vector3.new(-1.3, 0.7, -0.7), color = "trunkDark" },
	{ name = "LegB", size = Vector3.new(0.3, 1.5, 0.3), offset = Vector3.new(1.3, 0.7, -0.7), color = "trunkDark" },
	{ name = "LegC", size = Vector3.new(0.3, 1.5, 0.3), offset = Vector3.new(-1.3, 0.7, 0.7), color = "trunkDark" },
	{ name = "LegD", size = Vector3.new(0.3, 1.5, 0.3), offset = Vector3.new(1.3, 0.7, 0.7), color = "trunkDark" },
	{ name = "Brace", size = Vector3.new(2.6, 0.2, 1.3), offset = Vector3.new(0, 0.75, 0), color = "trunkDark" },
}

-- Same shapes as CraftingService's fixed Workbench_simple_forge.
local FORGE_SPECS = {
	{ name = "Base", size = Vector3.new(2.6, 1.8, 2.2), offset = Vector3.new(0, 0.9, 0), color = "stone", primary = true },
	{ name = "Firebox", size = Vector3.new(1.2, 0.9, 0.4), offset = Vector3.new(0, 0.65, 1.1), color = "stoneDark" },
	{ name = "Ember", size = Vector3.new(0.7, 0.5, 0.1), offset = Vector3.new(0, 0.6, 1.32), color = "gold" },
	{ name = "Chimney", size = Vector3.new(0.7, 1.4, 0.7), offset = Vector3.new(0, 2.5, -0.4), color = "steelDark" },
	{ name = "ChimneyCap", size = Vector3.new(0.9, 0.2, 0.9), offset = Vector3.new(0, 3.3, -0.4), color = "steel" },
}

-- Cooking station (docs/CAMP_TIERS.md §7) — iron tripod holding a pot over
-- embers. Purely its own furniture piece, separate from the campfire
-- dressing CampService draws at the zone's center (that one is cosmetic
-- only, tier-scaled, and never has a cauldron baked into it — see
-- CampService.CAMPFIRE_TIERS[2]).
local CAULDRON_SPECS = {
	{ name = "Base", shape = "Cylinder", size = Vector3.new(0.3, 1.4, 1.4), offset = Vector3.new(0, 0.15, 0), rot = Vector3.new(0, 0, 90), color = "stoneDark", primary = true },
	{ name = "LegA", size = Vector3.new(0.15, 1.6, 0.15), offset = Vector3.new(0.7, 0.8, 0.5), rot = Vector3.new(0, 0, -15), color = "steelDark" },
	{ name = "LegB", size = Vector3.new(0.15, 1.6, 0.15), offset = Vector3.new(-0.7, 0.8, 0.5), rot = Vector3.new(0, 0, 15), color = "steelDark" },
	{ name = "LegC", size = Vector3.new(0.15, 1.6, 0.15), offset = Vector3.new(0, 0.8, -0.8), rot = Vector3.new(15, 0, 0), color = "steelDark" },
	{ name = "Pot", shape = "Ball", size = Vector3.new(1.6, 1.1, 1.6), offset = Vector3.new(0, 1.7, 0), color = "steelDark" },
	{ name = "Ember", size = Vector3.new(0.9, 0.3, 0.9), offset = Vector3.new(0, 0.32, 0), color = "gold" },
}

-- Cosmetics (docs/CAMP_TIERS.md §4) — purely decorative, no station, no
-- gameplay function beyond feeding the coziness bonus (§3). Placeholder
-- proportions like everything else in this file — a visual pass in Studio,
-- not final art.
local RUG_SPECS = {
	{ name = "Base", size = Vector3.new(2.6, 0.1, 1.8), offset = Vector3.new(0, 0.05, 0), color = "ruby", canCollide = false, primary = true },
	{ name = "Trim", size = Vector3.new(2.8, 0.06, 2), offset = Vector3.new(0, 0.02, 0), color = "leatherDark", canCollide = false },
}

local LANTERN_SPECS = {
	{ name = "Post", size = Vector3.new(0.2, 2, 0.2), offset = Vector3.new(0, 1, 0), color = "trunkDark", primary = true },
	{ name = "Hook", size = Vector3.new(0.5, 0.1, 0.1), offset = Vector3.new(0, 1.95, 0), color = "steelDark" },
	{ name = "Ember", shape = "Ball", size = Vector3.new(0.5, 0.5, 0.5), offset = Vector3.new(0, 1.65, 0), color = "slime", canCollide = false },
}

local TROPHY_SPECS = {
	{ name = "Plaque", size = Vector3.new(1.2, 1.6, 0.15), offset = Vector3.new(0, 0.8, 0), color = "trunk", primary = true },
	{ name = "EarL", size = Vector3.new(0.5, 0.35, 0.1), offset = Vector3.new(-0.3, 1.15, 0.1), rot = Vector3.new(0, 0, 20), color = "goblin" },
	{ name = "EarR", size = Vector3.new(0.5, 0.35, 0.1), offset = Vector3.new(0.3, 1.15, 0.1), rot = Vector3.new(0, 0, -20), color = "goblinDark" },
	{ name = "Trim", size = Vector3.new(1.3, 0.15, 0.2), offset = Vector3.new(0, 0.1, 0.1), color = "gold" },
}

local furnitureFolder
local notifyRemote
local chestUpdatedRemote
local openChestRemote
local openGuildBankRemote
local manageRemote

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

-- Second ProximityPrompt (key F) on every piece — opens the client's
-- move/pick-up popup (client/FurnitureManageUI.lua). Separate from the
-- chest's own "Open" prompt so both can coexist on the same part.
local function attachManagePrompt(piece, model)
	local prompt = Instance.new("ProximityPrompt")
	prompt.ActionText = "Administrar"
	local itemDef = Items.get(piece.itemId)
	prompt.ObjectText = itemDef and itemDef.name or "Mueble"
	prompt.KeyboardKeyCode = Enum.KeyCode.F
	prompt.GamepadKeyCode = Enum.KeyCode.ButtonX
	prompt.HoldDuration = 0.15
	prompt.MaxActivationDistance = MAX_CHEST_DISTANCE
	prompt.RequiresLineOfSight = false
	prompt.Exclusivity = Enum.ProximityPromptExclusivity.OnePerButton
	prompt.UIOffset = Vector2.new(0, 55)
	prompt.Parent = model.PrimaryPart

	prompt.Triggered:Connect(function(triggeringPlayer)
		if not nearOwnChest(triggeringPlayer, piece) then
			notify(triggeringPlayer, "You need to be in this camp's party to manage that.")
			return
		end
		manageRemote:FireClient(triggeringPlayer, {
			pieceId = piece.id,
			itemId = piece.itemId,
			position = model.PrimaryPart.Position,
		})
	end)
end

-- ---- building ---------------------------------------------------------------

-- Style-A mesh per furniture kind (shared/MeshAssets world keys) + the
-- invisible anchor that stands in for the old ArtKit primary part: prompts,
-- distance checks and station registration all hang off model.PrimaryPart.
-- Sizes mirror each spec's primary so placement/spacing feel unchanged.
local MESH_LOOK = {
	chest = { key = "chest", anchor = Vector3.new(2, 1, 1.4), collide = true },
	guild_chest = { key = "chest", anchor = Vector3.new(2, 1, 1.4), collide = true },
	market = { key = "crafting_table", anchor = Vector3.new(3.2, 1.7, 1.8), collide = true },
	tent = { key = "tent", anchor = Vector3.new(0.6, 2.2, 0.6), collide = false },
	crafting_table = { key = "crafting_table", anchor = Vector3.new(3.2, 1.7, 1.8), collide = true },
	forge = { key = "simple_forge", anchor = Vector3.new(2.6, 1.8, 2.2), collide = true },
	cauldron = { key = "cauldron", anchor = Vector3.new(1.2, 2.2, 1.2), collide = true },
	rug = { key = "rug", anchor = Vector3.new(2.6, 0.15, 1.8), collide = false },
	lantern = { key = "lantern", anchor = Vector3.new(0.4, 2, 0.4), collide = true },
	torch = { key = "lantern", anchor = Vector3.new(0.6, 3.5, 0.6), collide = true },
	campfire = { key = "simple_forge", anchor = Vector3.new(3, 1, 3), collide = true },
	lamp = { key = "lantern", anchor = Vector3.new(0.6, 2.5, 0.6), collide = true },
	guild_architecture = { key = "crafting_table", anchor = Vector3.new(3.2, 1.7, 1.8), collide = true },
	planter = { key = "cauldron", anchor = Vector3.new(1.6, 1.2, 1.6), collide = true },
	welcome_sign = { key = "trophy", anchor = Vector3.new(2.5, 3.5, 0.4), collide = true },
}

-- Mesh-first furniture model; falls back to the ArtKit specs when the mesh
-- template didn't load (same pattern as the world builders elsewhere).
local function buildFurnitureModel(kind, artName, specs, origin, itemId)
	-- Check for custom models in ReplicatedStorage > Assets > Furniture
	local assetsFolder = ReplicatedStorage:FindFirstChild("Assets")
	local furnitureFolderAssets = assetsFolder and assetsFolder:FindFirstChild("Furniture")
	if furnitureFolderAssets then
		local customTemplate = (itemId and furnitureFolderAssets:FindFirstChild(itemId))
			or (artName and furnitureFolderAssets:FindFirstChild(artName))

		if not customTemplate then
			-- Flexible name aliases per kind
			if kind == "chair" then
				customTemplate = furnitureFolderAssets:FindFirstChild("silla")
					or furnitureFolderAssets:FindFirstChild("Silla")
					or furnitureFolderAssets:FindFirstChild("wood chair")
					or furnitureFolderAssets:FindFirstChild("wood_chair")
			elseif kind == "bed" then
				customTemplate = furnitureFolderAssets:FindFirstChild("cama")
					or furnitureFolderAssets:FindFirstChild("Cama")
					or furnitureFolderAssets:FindFirstChild("bolsa")
					or furnitureFolderAssets:FindFirstChild("Bolsa")
			elseif kind == "torch" then
				customTemplate = furnitureFolderAssets:FindFirstChild("antorcha")
					or furnitureFolderAssets:FindFirstChild("Antorcha")
			elseif kind == "campfire" then
				customTemplate = furnitureFolderAssets:FindFirstChild("hoguera")
					or furnitureFolderAssets:FindFirstChild("Hoguera")
			elseif kind == "lamp" then
				customTemplate = furnitureFolderAssets:FindFirstChild("farol")
					or furnitureFolderAssets:FindFirstChild("Farol")
			elseif kind == "planter" then
				customTemplate = furnitureFolderAssets:FindFirstChild("maceta")
					or furnitureFolderAssets:FindFirstChild("Maceta")
			elseif kind == "welcome_sign" then
				customTemplate = furnitureFolderAssets:FindFirstChild("letrero")
					or furnitureFolderAssets:FindFirstChild("Letrero")
			elseif kind == "guild_architecture" or kind == "crafting_table" then
				customTemplate = furnitureFolderAssets:FindFirstChild("mesa")
					or furnitureFolderAssets:FindFirstChild("Mesa")
			end
		end

		if customTemplate and customTemplate:IsA("Model") then
			local clone = customTemplate:Clone()
			clone.Name = artName
			if not clone.PrimaryPart then
				local primary = clone:FindFirstChildWhichIsA("BasePart")
				if primary then
					clone.PrimaryPart = primary
				end
			end
			clone:PivotTo(origin * CFrame.new(0, 1.2, 0))
			for _, part in ipairs(clone:GetDescendants()) do
				if part:IsA("BasePart") then
					part.Anchored = true
				end
			end
			return clone
		end
	end

	local look = MESH_LOOK[kind]
	local mesh = look and MeshAssetService.place(look.key, origin)
	if not mesh then
		return ArtKit.build(artName, origin, specs)
	end
	local model = Instance.new("Model")
	model.Name = artName
	mesh.Parent = model
	local anchor = Instance.new("Part")
	anchor.Name = "Anchor"
	anchor.Size = look.anchor
	anchor.CFrame = origin * CFrame.new(0, look.anchor.Y / 2, 0)
	anchor.Transparency = 1
	anchor.Anchored = true
	anchor.CanCollide = look.collide
	anchor.Parent = model
	model.PrimaryPart = anchor
	return model
end

local function buildPiece(kind, itemId, center, ownerId, rotY)
	nextPieceId += 1
	local id = nextPieceId
	local origin = CFrame.new(center) * CFrame.Angles(0, math.rad(rotY or 0), 0)
	local piece = { id = id, itemId = itemId, kind = kind, center = center, ownerId = ownerId, rotY = rotY or 0 }

	if kind == "chest" then
		local model = buildFurnitureModel(kind, "Cofre", CHEST_SPECS, origin)
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
		prompt.Exclusivity = Enum.ProximityPromptExclusivity.OnePerButton
		prompt.UIOffset = Vector2.new(0, 0)
		prompt.Parent = model.PrimaryPart

		local clickDetector = Instance.new("ClickDetector")
		clickDetector.MaxActivationDistance = MAX_CHEST_DISTANCE
		clickDetector.Parent = model.PrimaryPart

		local function triggerChest(triggeringPlayer)
			if not nearOwnChest(triggeringPlayer, piece) then
				notify(triggeringPlayer, "You need to be in this camp's party to use its chest.")
				return
			end
			openChestRemote:FireClient(triggeringPlayer, {
				chestId = id,
				columns = piece.storage.columns,
				rows = piece.storage.rows,
				items = snapshotChest(piece.storage),
				position = model.PrimaryPart.Position,
			})
		end

		prompt.Triggered:Connect(triggerChest)
		clickDetector.MouseClick:Connect(triggerChest)
		clickDetector.RightMouseClick:Connect(triggerChest)

		attachManagePrompt(piece, model)
	elseif kind == "guild_chest" then
		local model = buildFurnitureModel(kind, "Cofre de Gremio", CHEST_SPECS, origin)
		model.Parent = furnitureFolder
		piece.model = model

		local prompt = Instance.new("ProximityPrompt")
		prompt.ActionText = "Abrir Banco de Gremio"
		prompt.ObjectText = "Cofre de Gremio"
		prompt.HoldDuration = 0.15
		prompt.MaxActivationDistance = MAX_CHEST_DISTANCE
		prompt.RequiresLineOfSight = false
		prompt.Exclusivity = Enum.ProximityPromptExclusivity.OnePerButton
		prompt.UIOffset = Vector2.new(0, 0)
		prompt.Parent = model.PrimaryPart

		local clickDetector = Instance.new("ClickDetector")
		clickDetector.MaxActivationDistance = MAX_CHEST_DISTANCE
		clickDetector.Parent = model.PrimaryPart

		local function triggerGuildChest(triggeringPlayer)
			if not triggeringPlayer:GetAttribute("GuildId") then
				notify(triggeringPlayer, "Necesitás pertenecer a un gremio para acceder a su banco.")
				return
			end
			if openGuildBankRemote then
				openGuildBankRemote:FireClient(triggeringPlayer)
			end
		end

		prompt.Triggered:Connect(triggerGuildChest)
		clickDetector.MouseClick:Connect(triggerGuildChest)
		clickDetector.RightMouseClick:Connect(triggerGuildChest)

		attachManagePrompt(piece, model)
	elseif kind == "market" then
		local model = buildFurnitureModel(kind, "Puesto de Mercado", CHEST_SPECS, origin)
		model.Parent = furnitureFolder
		piece.model = model

		local prompt = Instance.new("ProximityPrompt")
		prompt.ActionText = "Abrir Mercado"
		prompt.ObjectText = "Puesto de Mercado"
		prompt.HoldDuration = 0.15
		prompt.MaxActivationDistance = MAX_CHEST_DISTANCE
		prompt.RequiresLineOfSight = false
		prompt.Exclusivity = Enum.ProximityPromptExclusivity.OnePerButton
		prompt.UIOffset = Vector2.new(0, 0)
		prompt.Parent = model.PrimaryPart

		local clickDetector = Instance.new("ClickDetector")
		clickDetector.MaxActivationDistance = MAX_CHEST_DISTANCE
		clickDetector.Parent = model.PrimaryPart

		local openMarketRemote = Remotes.get("OpenMarket")
		local function triggerMarket(triggeringPlayer)
			if openMarketRemote then
				openMarketRemote:FireClient(triggeringPlayer)
			end
		end

		prompt.Triggered:Connect(triggerMarket)
		clickDetector.MouseClick:Connect(triggerMarket)
		clickDetector.RightMouseClick:Connect(triggerMarket)

		attachManagePrompt(piece, model)
	elseif kind == "tent" then
		local model = buildFurnitureModel(kind, "Carpa", TENT_SPECS, origin)
		model.Parent = furnitureFolder
		piece.model = model

		-- Cozy interior warm light for tents
		local light = Instance.new("PointLight")
		light.Color = Color3.fromRGB(255, 200, 140)
		light.Range = 12
		light.Brightness = 1.0
		light.Parent = model.PrimaryPart

		attachManagePrompt(piece, model)
	elseif kind == "crafting_table" or kind == "forge" or kind == "cauldron" or kind == "guild_architecture" then
		local specs = CRAFTING_TABLE_SPECS
		local artName = "MesaCrafteo"
		if kind == "forge" then
			specs = FORGE_SPECS
			artName = "Forja"
		elseif kind == "cauldron" then
			specs = CAULDRON_SPECS
			artName = "Olla"
		elseif kind == "guild_architecture" then
			specs = CRAFTING_TABLE_SPECS
			artName = "MesaArquitecturaGremio"
		end
		local model = buildFurnitureModel(kind, artName, specs, origin)
		model.Parent = furnitureFolder
		piece.model = model

		if kind == "forge" then
			local light = Instance.new("PointLight")
			light.Color = Color3.fromRGB(255, 120, 30)
			light.Range = 12
			light.Brightness = 1.8
			light.Parent = model.PrimaryPart
		elseif kind == "cauldron" then
			local prompt = Instance.new("ProximityPrompt")
			prompt.ActionText = "Cocinar / Alquimia"
			prompt.ObjectText = "Olla de Campamento"
			prompt.HoldDuration = 0.15
			prompt.MaxActivationDistance = MAX_CHEST_DISTANCE
			prompt.RequiresLineOfSight = false
			prompt.Exclusivity = Enum.ProximityPromptExclusivity.OnePerButton
			prompt.UIOffset = Vector2.new(0, 0)
			prompt.Parent = model.PrimaryPart

			local clickDetector = Instance.new("ClickDetector")
			clickDetector.MaxActivationDistance = MAX_CHEST_DISTANCE
			clickDetector.Parent = model.PrimaryPart

			local openCookingRemote = Remotes.get("OpenCooking")
			local function triggerCooking(triggeringPlayer)
				if openCookingRemote then
					openCookingRemote:FireClient(triggeringPlayer)
				end
			end

			prompt.Triggered:Connect(triggerCooking)
			clickDetector.MouseClick:Connect(triggerCooking)
			clickDetector.RightMouseClick:Connect(triggerCooking)

			local light = Instance.new("PointLight")
			light.Color = Color3.fromRGB(255, 180, 80)
			light.Range = 10
			light.Brightness = 1.4
			light.Parent = model.PrimaryPart

			local steam = Instance.new("ParticleEmitter")
			steam.Name = "Steam"
			steam.Color = ColorSequence.new(Color3.fromRGB(220, 230, 240))
			steam.Size = NumberSequence.new({
				NumberSequenceKeypoint.new(0, 0.4),
				NumberSequenceKeypoint.new(1, 1.2),
			})
			steam.Transparency = NumberSequence.new({
				NumberSequenceKeypoint.new(0, 0.5),
				NumberSequenceKeypoint.new(1, 1.0),
			})
			steam.Lifetime = NumberRange.new(1.0, 2.0)
			steam.Rate = 6
			steam.Speed = NumberRange.new(1.0, 2.0)
			steam.Parent = model.PrimaryPart
		end

		-- The whole point: while this piece stands, it's a real workbench —
		-- recipes that need FURNITURE_DEFS[itemId].station unlock near it,
		-- same as the fixed ones in town (CraftingService.nearStation
		-- doesn't distinguish the two).
		piece.station = FURNITURE_DEFS[itemId].station
		piece.stationHandle = CraftingService.registerStation(piece.station, model.PrimaryPart.Position)

		attachManagePrompt(piece, model)
	elseif kind == "rug" or kind == "lantern" or kind == "trophy" then
		local specs = RUG_SPECS
		local artName = "Alfombra"
		if kind == "lantern" then
			specs = LANTERN_SPECS
			artName = "Farol"
		elseif kind == "trophy" then
			specs = TROPHY_SPECS
			artName = "Trofeo"
		end
		local model = buildFurnitureModel(kind, artName, specs, origin)
		model.Parent = furnitureFolder
		piece.model = model

		if kind == "lantern" then
			-- ArtKit lantern has an "Ember" part; the mesh's glass is just
			-- the first Neon part — light either, in its own color.
			local glow = model:FindFirstChild("Ember")
			if not glow then
				for _, p in ipairs(model:GetDescendants()) do
					if p:IsA("BasePart") and p.Material == Enum.Material.Neon then
						glow = p
						break
					end
				end
			end
			local targetPart = glow or model.PrimaryPart
			local light = Instance.new("PointLight")
			light.Color = glow and glow.Color or Color3.fromRGB(255, 210, 120)
			light.Range = 16
			light.Brightness = 2.0
			light.Parent = targetPart
		end

		attachManagePrompt(piece, model)
	elseif kind == "torch" or kind == "campfire" or kind == "lamp" then
		local specs = LANTERN_SPECS
		local artName = "Antorcha"
		if kind == "campfire" then
			specs = FORGE_SPECS
			artName = "Hoguera"
		elseif kind == "lamp" then
			specs = LANTERN_SPECS
			artName = "Farol"
		end
		local model = buildFurnitureModel(kind, artName, specs, origin)
		model.Parent = furnitureFolder
		piece.model = model

		local light = Instance.new("PointLight")
		if kind == "torch" then
			light.Color = Color3.fromRGB(255, 170, 70)
			light.Range = 28
			light.Brightness = 2.8
		elseif kind == "campfire" then
			light.Color = Color3.fromRGB(255, 150, 50)
			light.Range = 42
			light.Brightness = 3.6

			local openCookingRemote = Remotes.get("OpenCooking")
			local prompt = Instance.new("ProximityPrompt")
			prompt.ActionText = "Cocinar Pescado / Comida"
			prompt.ObjectText = "Hoguera de Campamento"
			prompt.HoldDuration = 0.15
			prompt.MaxActivationDistance = 12
			prompt.RequiresLineOfSight = false
			prompt.Parent = model.PrimaryPart

			prompt.Triggered:Connect(function(plr)
				if openCookingRemote then
					openCookingRemote:FireClient(plr)
				end
			end)
		else
			light.Color = Color3.fromRGB(255, 225, 140)
			light.Range = 32
			light.Brightness = 2.6
		end
		light.Parent = model.PrimaryPart

		local targetBrightness = (kind == "campfire" and 3.6) or (kind == "torch" and 2.8) or 2.6
		registerLightSource(model, light, nil, targetBrightness)

		attachManagePrompt(piece, model)
	elseif kind == "planter" then
		local model = buildFurnitureModel(kind, "Maceta", CAULDRON_SPECS, origin)
		model.Parent = furnitureFolder
		piece.model = model

		local prompt = Instance.new("ProximityPrompt")
		prompt.ActionText = "Plantar Semillas de Hierbas"
		prompt.ObjectText = "Maceta del Gremio"
		prompt.HoldDuration = 0.15
		prompt.MaxActivationDistance = 10
		prompt.RequiresLineOfSight = false
		prompt.Parent = model.PrimaryPart

		local isPlanted = false
		local isGrown = false
		local plantMesh = nil

		prompt.Triggered:Connect(function(plr)
			if not isPlanted then
				if PlayerService.removeItem(plr, "semilla_hierbas", 1) then
					isPlanted = true
					prompt.ActionText = "🌱 Creciendo..."
					prompt.Enabled = false

					plantMesh = Instance.new("Part")
					plantMesh.Name = "Sprout"
					plantMesh.Size = Vector3.new(0.6, 0.6, 0.6)
					plantMesh.CFrame = model.PrimaryPart.CFrame * CFrame.new(0, 0.8, 0)
					plantMesh.Color = Color3.fromRGB(80, 180, 60)
					plantMesh.Material = Enum.Material.Grass
					plantMesh.Anchored = true
					plantMesh.CanCollide = false
					plantMesh.Parent = model

					task.delay(8, function()
						if plantMesh and plantMesh.Parent then
							isGrown = true
							plantMesh.Size = Vector3.new(1.2, 1.4, 1.2)
							plantMesh.Color = Color3.fromRGB(40, 210, 80)
							plantMesh.Material = Enum.Material.Neon

							prompt.ActionText = "🌿 Cosechar Hierbas Medicinales"
							prompt.Enabled = true
						end
					end)
				else
					notify(plr, "Necesitas Semillas de Hierbas para plantar (recolectalas de arbustos con la Hoz).")
				end
			elseif isGrown then
				isPlanted = false
				isGrown = false
				if plantMesh then
					plantMesh:Destroy()
					plantMesh = nil
				end
				PlayerService.addItem(plr, "herb_green", 2, true)
				PlayerService.addItem(plr, "semilla_hierbas", 1, true)
				prompt.ActionText = "Plantar Semillas de Hierbas"
				notify(plr, "¡Cosechaste 2x Hierbas Medicinales y 1x Semilla!")
			end
		end)

		attachManagePrompt(piece, model)
	elseif kind == "welcome_sign" then
		local model = buildFurnitureModel(kind, "LetreroBienvenida", TROPHY_SPECS, origin)
		model.Parent = furnitureFolder
		piece.model = model

		local surfaceGui = Instance.new("SurfaceGui")
		surfaceGui.Size = Vector2.new(400, 250)
		surfaceGui.CanvasSize = Vector2.new(400, 250)
		surfaceGui.AlwaysOnTop = false
		surfaceGui.Parent = model.PrimaryPart

		local boardText = Instance.new("TextLabel")
		boardText.Size = UDim2.new(1, 0, 1, 0)
		boardText.BackgroundColor3 = Color3.fromRGB(30, 20, 10)
		boardText.TextColor3 = Color3.fromRGB(255, 220, 140)
		boardText.TextScaled = true
		boardText.Font = Enum.Font.SourceSansBold
		boardText.Text = "📜 ANUNCIOS DE LA SEDE\n\n¡Bienvenidos a la Sede del Gremio!"
		boardText.Parent = surfaceGui

		local promptRead = Instance.new("ProximityPrompt")
		promptRead.ActionText = "Leer / Editar Anuncio"
		promptRead.ObjectText = "Letrero del Gremio"
		promptRead.HoldDuration = 0.1
		promptRead.MaxActivationDistance = 12
		promptRead.RequiresLineOfSight = false
		promptRead.Parent = model.PrimaryPart

		promptRead.Triggered:Connect(function(plr)
			Remotes.get("OpenWelcomeSign"):FireClient(plr, {
				guildName = plr:GetAttribute("GuildName") or "Gremio",
				text = boardText.Text,
				isLeader = plr:GetAttribute("GuildLeader") == true,
			})
		end)

		attachManagePrompt(piece, model)
	elseif kind == "guild_portal" then
		local model = buildFurnitureModel(kind, "PortalGremio", CRAFTING_TABLE_SPECS, origin)
		model.Parent = furnitureFolder
		piece.model = model

		local vortex = Instance.new("Part")
		vortex.Name = "PortalVortex"
		vortex.Size = Vector3.new(4, 7, 0.4)
		vortex.CFrame = origin * CFrame.new(0, 4.5, 0)
		vortex.Material = Enum.Material.Neon
		vortex.Color = Color3.fromRGB(0, 210, 255)
		vortex.Transparency = 0.35
		vortex.Anchored = true
		vortex.CanCollide = false
		vortex.Parent = model

		local light = Instance.new("PointLight")
		light.Color = Color3.fromRGB(0, 200, 255)
		light.Range = 20
		light.Brightness = 1.8
		light.Parent = vortex

		local prompt = Instance.new("ProximityPrompt")
		prompt.ActionText = "Entrar al Valle de los Gremios"
		prompt.ObjectText = "Portal del Gremio"
		prompt.HoldDuration = 0.15
		prompt.MaxActivationDistance = 12
		prompt.RequiresLineOfSight = false
		prompt.Parent = vortex

		prompt.Triggered:Connect(function(triggeringPlayer)
			GuildPlotService.teleportToGuildSanctuary(triggeringPlayer)
		end)

		attachManagePrompt(piece, model)
	elseif kind == "bed" then
		local specs = RUG_SPECS
		local model = buildFurnitureModel(kind, "Cama", specs, origin)
		model.Parent = furnitureFolder
		piece.model = model

		local prompt = Instance.new("ProximityPrompt")
		prompt.ActionText = "Acostarse / Descansar"
		prompt.ObjectText = itemId == "bolsa_dormir" and "Bolsa de Dormir" or "Cama de Campamento"
		prompt.HoldDuration = 0.15
		prompt.MaxActivationDistance = MAX_CHEST_DISTANCE
		prompt.RequiresLineOfSight = false
		prompt.Exclusivity = Enum.ProximityPromptExclusivity.OnePerButton
		prompt.Parent = model.PrimaryPart

		local clickDetector = Instance.new("ClickDetector")
		clickDetector.MaxActivationDistance = MAX_CHEST_DISTANCE
		clickDetector.Parent = model.PrimaryPart

		local function triggerSleep(p)
			SleepingService.lieDown(p, model.PrimaryPart)
		end
		prompt.Triggered:Connect(triggerSleep)
		clickDetector.MouseClick:Connect(triggerSleep)
		clickDetector.RightMouseClick:Connect(triggerSleep)

		attachManagePrompt(piece, model)
	elseif kind == "guild_research" then
		local specs = CRAFTING_TABLE_SPECS
		local model = buildFurnitureModel(kind, "MesaInvestigacion", specs, origin)
		model.Parent = furnitureFolder
		piece.model = model

		local prompt = Instance.new("ProximityPrompt")
		prompt.ActionText = "Investigaciones del Gremio"
		prompt.ObjectText = "Mesa de Investigación"
		prompt.HoldDuration = 0.15
		prompt.MaxActivationDistance = MAX_CHEST_DISTANCE
		prompt.RequiresLineOfSight = false
		prompt.Exclusivity = Enum.ProximityPromptExclusivity.OnePerButton
		prompt.Parent = model.PrimaryPart

		local clickDetector = Instance.new("ClickDetector")
		clickDetector.MaxActivationDistance = MAX_CHEST_DISTANCE
		clickDetector.Parent = model.PrimaryPart

		local openResearchRemote = Remotes.get("OpenGuildResearch")
		local function triggerResearch(p)
			if openResearchRemote then
				openResearchRemote:FireClient(p)
			end
		end
		prompt.Triggered:Connect(triggerResearch)
		clickDetector.MouseClick:Connect(triggerResearch)
		clickDetector.RightMouseClick:Connect(triggerResearch)

		attachManagePrompt(piece, model)
	elseif kind == "chair" then
		local specs = RUG_SPECS
		local model = buildFurnitureModel(kind, "Asiento", specs, origin, itemId)
		model.Parent = furnitureFolder
		piece.model = model

		local prompt = Instance.new("ProximityPrompt")
		prompt.ActionText = "Sentarse / Descansar"
		prompt.ObjectText = itemId == "banco_campamento" and "Banco de Madera" or "Silla de Madera"
		prompt.HoldDuration = 0.15
		prompt.MaxActivationDistance = MAX_CHEST_DISTANCE
		prompt.RequiresLineOfSight = false
		prompt.Exclusivity = Enum.ProximityPromptExclusivity.OnePerButton
		prompt.Parent = model.PrimaryPart

		local clickDetector = Instance.new("ClickDetector")
		clickDetector.MaxActivationDistance = MAX_CHEST_DISTANCE
		clickDetector.Parent = model.PrimaryPart

		local function triggerSit(p)
			SittingService.sitDown(p, model.PrimaryPart)
		end
		prompt.Triggered:Connect(triggerSit)
		clickDetector.MouseClick:Connect(triggerSit)
		clickDetector.RightMouseClick:Connect(triggerSit)

		attachManagePrompt(piece, model)
	end

	return piece
end

-- ---- saved layout (persistence) ------------------------------------------

-- Snapshot of everything currently planted for `ownerId`, JSON-able and
-- ready for PlayerService.setCampLayout. Positions are stored as offsets
-- from the camp center (not world coordinates) so they replay correctly at
-- a different spot next time.
local function snapshotLayout(ownerId, campCenter)
	local savedPieces = {}
	local pieces = piecesByCamp[ownerId]
	if pieces then
		for _, piece in pairs(pieces) do
			local entry = {
				itemId = piece.itemId,
				dx = piece.center.X - campCenter.X,
				dz = piece.center.Z - campCenter.Z,
			}
			if piece.kind == "chest" then
				entry.chestItems = snapshotChest(piece.storage)
			end
			table.insert(savedPieces, entry)
		end
	end
	return { pieces = savedPieces }
end

-- Rebuilds every saved piece for a freshly-placed camp (CampService.onPlace).
local function restoreLayout(ownerId, camp)
	local layout = PlayerService.getCampLayout(ownerId)
	local savedPieces = typeof(layout) == "table" and layout.pieces
	if typeof(savedPieces) ~= "table" then
		return
	end

	for _, saved in ipairs(savedPieces) do
		local itemId = typeof(saved) == "table" and saved.itemId
		local def = typeof(itemId) == "string" and FURNITURE_DEFS[itemId]
		local dx, dz = tonumber(saved.dx), tonumber(saved.dz)
		if def and dx and dz then
			local x, z = camp.center.X + dx, camp.center.Z + dz
			local center = Vector3.new(x, findGroundY(x, z), z)
			local piece = buildPiece(def.kind, itemId, center, ownerId)

			if piece.kind == "chest" and typeof(saved.chestItems) == "table" then
				local maxLocalId = 0
				for _, item in ipairs(saved.chestItems) do
					local localId = tonumber(item.id)
					local quantity = tonumber(item.quantity)
					local ix, iy = tonumber(item.x), tonumber(item.y)
					if localId and quantity and quantity > 0 and ix and iy and typeof(item.itemId) == "string" then
						piece.storage.items[localId] = { itemId = item.itemId, quantity = quantity, x = ix, y = iy }
						maxLocalId = math.max(maxLocalId, localId)
					end
				end
				piece.storage.nextLocalId = maxLocalId
			end

			piecesByCamp[ownerId] = piecesByCamp[ownerId] or {}
			piecesByCamp[ownerId][piece.id] = piece
		end
	end
end

-- ---- remotes ------------------------------------------------------------

local function handlePlaceFurniture(player, itemId, x, z, rotY)
	if typeof(itemId) ~= "string" or typeof(x) ~= "number" or typeof(z) ~= "number" then
		return { ok = false, error = "bad_request" }
	end
	rotY = tonumber(rotY) or 0
	local def = FURNITURE_DEFS[itemId]
	if not def then
		return { ok = false, error = "bad_request" }
	end

	local camp = CampService.campFor(player)
	local guildId = player:GetAttribute("GuildId")
	local inHQ = guildId and GuildPlotService.isPositionInGuildHQ(Vector3.new(x, 0, z), guildId)

	if not camp and not inHQ then
		notify(player, "Debes tener una Acampada activa o estar en la Sede de tu Gremio para colocar este mueble.")
		return { ok = false, error = "no_camp" }
	end

	if def.minCampTier and camp and (camp.tier or 0) < def.minCampTier then
		notify(player, "Tu acampada necesita un nivel más alto para colocar este objeto.")
		return { ok = false, error = "tier_too_low" }
	end

	local character = player.Character
	local root = character and character:FindFirstChild("HumanoidRootPart")
	if not root then
		return { ok = false, error = "no_character" }
	end

	-- Anti-exploit: distance check
	local flatDistance = (Vector3.new(x, root.Position.Y, z) - root.Position).Magnitude
	if flatDistance > CAMP.maxPlacementDistance then
		notify(player, "Demasiado lejos para colocarlo ahí.")
		return { ok = false, error = "too_far" }
	end

	if camp then
		local half = camp.zoneHalf
		if not inHQ and (math.abs(x - camp.center.X) > half or math.abs(z - camp.center.Z) > half) then
			notify(player, "El mueble debe colocarse dentro del área de tu Acampada o Sede.")
			return { ok = false, error = "outside_zone" }
		end
	end

	if itemId == "mesa_investigacion_gremio" then
		local guildId = player:GetAttribute("GuildId")
		if not guildId or not GuildPlotService.isPositionInGuildHQ(Vector3.new(x, 0, z), guildId) then
			notify(player, "La Mesa de Investigación solo puede colocarse dentro de la Sede Oficial de tu Gremio.")
			return { ok = false, error = "not_guild_hq" }
		end
	end

	-- Camp specific radius and capacity checks (bypassed in Guild HQ)
	if not inHQ and camp then
		local dx, dz = x - camp.center.X, z - camp.center.Z
		if math.sqrt(dx * dx + dz * dz) < CAMP.firePitRadius then
			notify(player, "Demasiado cerca de la hoguera del campamento.")
			return { ok = false, error = "too_close_to_fire" }
		end

		local pieces = piecesByCamp[camp.ownerUserId]
		local maxFurniture = (CAMP.tiers[camp.tier] or CAMP.tiers[0]).maxFurniture
		local currentCount = 0
		if pieces then
			for _ in pairs(pieces) do
				currentCount += 1
			end
		end
		if currentCount >= maxFurniture then
			notify(player, "No entran más muebles en este campamento personal. ¡Usa la Sede del Gremio para amueblar sin límite!")
			return { ok = false, error = "camp_full" }
		end
	end

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
	local piece = buildPiece(def.kind, itemId, center, camp.ownerUserId, rotY)

	piecesByCamp[camp.ownerUserId] = piecesByCamp[camp.ownerUserId] or {}
	piecesByCamp[camp.ownerUserId][piece.id] = piece

	local itemDef = Items.get(itemId)
	notify(player, (itemDef and itemDef.name or itemId) .. " placed.")
	return { ok = true }
end

-- Player must currently have camp access (own/party) matching the piece's
-- camp, regardless of distance — used by move/pickup, which do their own
-- distance checks against the relevant point (the piece itself for pickup,
-- the destination for move).
local function pieceOwnerCamp(player, piece)
	local camp = CampService.campFor(player)
	if not camp or camp.ownerUserId ~= piece.ownerId then
		return nil
	end
	return camp
end

-- Finds a piece by id across all camps, plus which owner it belongs to.
local function findPiece(pieceId)
	pieceId = tonumber(pieceId)
	if not pieceId then
		return nil, nil
	end
	for ownerId, pieces in pairs(piecesByCamp) do
		local piece = pieces[pieceId]
		if piece then
			return piece, ownerId
		end
	end
	return nil, nil
end

local function handleMoveFurniture(player, pieceId, x, z)
	if typeof(x) ~= "number" or typeof(z) ~= "number" then
		return { ok = false, error = "bad_request" }
	end
	local piece, ownerId = findPiece(pieceId)
	if not piece then
		return { ok = false, error = "bad_request" }
	end

	local camp = pieceOwnerCamp(player, piece)
	if not camp then
		notify(player, "You need to be in this camp's party to move that.")
		return { ok = false, error = "no_camp" }
	end

	local character = player.Character
	local root = character and character:FindFirstChild("HumanoidRootPart")
	if not root then
		return { ok = false, error = "no_character" }
	end

	-- Same re-validation posture as PlaceFurniture: never trust the client's
	-- claimed point.
	local flatDistance = (Vector3.new(x, root.Position.Y, z) - root.Position).Magnitude
	if flatDistance > CAMP.maxPlacementDistance then
		notify(player, "Too far away to place it there.")
		return { ok = false, error = "too_far" }
	end

	local half = camp.zoneHalf
	if math.abs(x - camp.center.X) > half or math.abs(z - camp.center.Z) > half then
		notify(player, "Furniture has to go inside the camp's zone.")
		return { ok = false, error = "outside_zone" }
	end

	-- Same reserved fire-pit radius as PlaceFurniture (docs/CAMP_TIERS.md
	-- §6.1) — moving a piece into it is just as invalid as planting it there.
	do
		local dx, dz = x - camp.center.X, z - camp.center.Z
		if math.sqrt(dx * dx + dz * dz) < CAMP.firePitRadius then
			notify(player, "Too close to the campfire.")
			return { ok = false, error = "too_close_to_fire" }
		end
	end

	local pieces = piecesByCamp[ownerId]
	for otherId, other in pairs(pieces) do
		if otherId ~= piece.id then
			local dx, dz = other.center.X - x, other.center.Z - z
			if math.sqrt(dx * dx + dz * dz) < FURNITURE.minSpacing then
				notify(player, "Too close to another piece of furniture.")
				return { ok = false, error = "too_close" }
			end
		end
	end

	local newCenter = Vector3.new(x, findGroundY(x, z), z)
	piece.center = newCenter
	if piece.model then
		piece.model:PivotTo(CFrame.new(newCenter))
	end
	if piece.stationHandle then
		CraftingService.moveStation(piece.stationHandle, newCenter)
	end
	return { ok = true }
end

local function handlePickupFurniture(player, pieceId)
	local piece, ownerId = findPiece(pieceId)
	if not piece then
		return { ok = false, error = "bad_request" }
	end

	if not pieceOwnerCamp(player, piece) then
		notify(player, "You need to be in this camp's party to pick that up.")
		return { ok = false, error = "no_camp" }
	end
	if not nearOwnChest(player, piece) then
		return { ok = false, error = "too_far" }
	end
	if piece.kind == "chest" and next(piece.storage.items) ~= nil then
		notify(player, "Empty the chest before picking it up.")
		return { ok = false, error = "not_empty" }
	end

	local ok = PlayerService.addItem(player, piece.itemId, 1, true)
	if not ok then
		notify(player, "Not enough room in your inventory.")
		return { ok = false, error = "no_space" }
	end

	piecesByCamp[ownerId][piece.id] = nil
	if piece.kind == "chest" then
		chestsById[piece.id] = nil
	end
	if piece.station then
		CraftingService.unregisterStation(piece.station, piece.stationHandle)
	end
	if piece.model then
		piece.model:Destroy()
	end

	local itemDef = Items.get(piece.itemId)
	notify(player, (itemDef and itemDef.name or piece.itemId) .. " returned to your inventory.")
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

-- Public: 0-1 ratio of how "cozy" ownerId's camp currently is right now —
-- currently-planted cosmetic pieces (FURNITURE_DEFS[x].cosmetic, e.g. rug/
-- lantern/trophy) versus the tier's cozinessTarget, capped at 1. Used by
-- RestedService to scale how fast the Rested buff banks while resting in a
-- decorated camp (docs/CAMP_TIERS.md §3) — this module stays the only place
-- that iterates FURNITURE_DEFS/piecesByCamp, RestedService just asks for
-- the number.
function CampFurnitureService.cozinessRatio(ownerId)
	local camp = CampService.getCamp(ownerId)
	local tier = CAMP.tiers[camp and camp.tier or 0] or CAMP.tiers[0]
	if (tier.cozinessTarget or 0) <= 0 then
		return 0
	end

	local cosmeticCount = 0
	for _, piece in pairs(piecesByCamp[ownerId] or {}) do
		local def = FURNITURE_DEFS[piece.itemId]
		if def and def.cosmetic then
			cosmeticCount += 1
		end
	end

	return math.min(cosmeticCount / tier.cozinessTarget, 1)
end

function CampFurnitureService.start()
	notifyRemote = Remotes.get("Notify")
	chestUpdatedRemote = Remotes.get("ChestUpdated")
	openChestRemote = Remotes.get("OpenChest")
	manageRemote = Remotes.get("ManageFurniture")

	furnitureFolder = Instance.new("Folder")
	furnitureFolder.Name = "CampFurniture"
	furnitureFolder.Parent = Workspace

	CampService.onTeardown(function(ownerId, camp)
		-- Snapshot BEFORE destroying anything: this is what reappears next
		-- time this owner plants an Acampada (see restoreLayout / onPlace
		-- below). Nothing is dropped or lost — it just goes dormant.
		PlayerService.setCampLayout(ownerId, snapshotLayout(ownerId, camp.center))

		local pieces = piecesByCamp[ownerId]
		if not pieces then
			return
		end
		piecesByCamp[ownerId] = nil
		for _, piece in pairs(pieces) do
			if piece.kind == "chest" then
				chestsById[piece.id] = nil
			end
			if piece.station then
				CraftingService.unregisterStation(piece.station, piece.stationHandle)
			end
			if piece.model then
				piece.model:Destroy()
			end
		end
	end)

	CampService.onPlace(function(ownerId, camp)
		restoreLayout(ownerId, camp)
	end)

	-- Coziness (docs/CAMP_TIERS.md §3) used to grant extra HP regen directly
	-- here — reworked: HP regen already has too many hands in the pot
	-- (Cleric's Devotion passive, Brawler's synergy bonus, the generic
	-- `regen` trait stat all feed the same HealthService.registerBonusRegen
	-- hook), so a decoration-scaled regen bonus mostly just rewarded
	-- whoever already stacked regen the hardest. Coziness now scales how
	-- fast the "Rested" buff banks instead (see RestedService.lua) — a
	-- different axis (gathering/XP, not combat regen) that doesn't compete
	-- with any existing trait or passive. This module stays the only place
	-- that counts furniture (see CampFurnitureService.cozinessRatio below);
	-- RestedService just asks for the ratio.

	-- Periodic safety net: the layout is always saved on teardown, but that
	-- alone means an unexpected server restart mid-session loses anything
	-- moved/placed since the camp went up. This just re-runs the same
	-- snapshot on a timer for every currently-active camp.
	task.spawn(function()
		while true do
			task.wait(AUTOSAVE_INTERVAL)
			for ownerId in pairs(piecesByCamp) do
				local camp = CampService.getCamp(ownerId)
				if camp then
					PlayerService.setCampLayout(ownerId, snapshotLayout(ownerId, camp.center))
				end
			end
		end
	end)

	notifyRemote = Remotes.get("Notify")
	chestUpdatedRemote = Remotes.get("ChestUpdated")
	openChestRemote = Remotes.get("OpenChest")
	openGuildBankRemote = Remotes.get("OpenGuildBank")
	manageRemote = Remotes.get("ManageFurniture")

	local placeFurniture = Remotes.getFunction("PlaceFurniture")
	placeFurniture.OnServerInvoke = handlePlaceFurniture

	local moveFurniture = Remotes.getFunction("MoveFurniture")
	moveFurniture.OnServerInvoke = handleMoveFurniture

	local pickupFurniture = Remotes.getFunction("PickupFurniture")
	pickupFurniture.OnServerInvoke = handlePickupFurniture

	local chestDeposit = Remotes.getFunction("ChestDeposit")
	chestDeposit.OnServerInvoke = handleChestDeposit

	local chestWithdraw = Remotes.getFunction("ChestWithdraw")
	chestWithdraw.OnServerInvoke = handleChestWithdraw

	DayNightService.onChanged(function(isNight)
		CampFurnitureService.setNightLighting(isNight)
	end)
end

return CampFurnitureService