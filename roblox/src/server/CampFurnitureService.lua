-- Camp furniture: crafting "cofre_campamento", "carpa_campamento",
-- "crafting_table", or "simple_forge" (shared/Recipes.lua) lets a player
-- plant them, but ONLY inside the zone of an Acampada they can currently
-- access (their own, or their party's — see CampService.campFor). No count
-- limit per camp, the zone's own footprint (30x30 studs) is the only
-- budget, same spirit as the request.
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

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared:WaitForChild("Config"))
local ArtKit = require(Shared:WaitForChild("ArtKit"))
local Items = require(Shared:WaitForChild("Items"))
local Remotes = require(Shared:WaitForChild("Remotes"))

local PlayerService = require(script.Parent.PlayerService)
local CampService = require(script.Parent.CampService)
local CraftingService = require(script.Parent.CraftingService)

local CampFurnitureService = {}

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
	carpa_campamento = { kind = "tent" },
	crafting_table = { kind = "crafting_table", station = "crafting_table" },
	simple_forge = { kind = "forge", station = "simple_forge" },
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

local furnitureFolder
local notifyRemote
local chestUpdatedRemote
local openChestRemote
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
	prompt.ActionText = "Manage"
	local itemDef = Items.get(piece.itemId)
	prompt.ObjectText = itemDef and itemDef.name or "Furniture"
	prompt.KeyboardKeyCode = Enum.KeyCode.F
	prompt.GamepadKeyCode = Enum.KeyCode.ButtonX
	prompt.HoldDuration = 0.15
	prompt.MaxActivationDistance = MAX_CHEST_DISTANCE
	prompt.RequiresLineOfSight = false
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

		prompt.Triggered:Connect(function(triggeringPlayer)
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
		end)

		attachManagePrompt(piece, model)
	elseif kind == "tent" then
		local model = ArtKit.build("Carpa", origin, TENT_SPECS)
		model.Parent = furnitureFolder
		piece.model = model

		attachManagePrompt(piece, model)
	elseif kind == "crafting_table" or kind == "forge" then
		local specs = kind == "crafting_table" and CRAFTING_TABLE_SPECS or FORGE_SPECS
		local artName = kind == "crafting_table" and "MesaCrafteo" or "Forja"
		local model = ArtKit.build(artName, origin, specs)
		model.Parent = furnitureFolder
		piece.model = model

		-- The whole point: while this piece stands, it's a real workbench —
		-- recipes that need FURNITURE_DEFS[itemId].station unlock near it,
		-- same as the fixed ones in town (CraftingService.nearStation
		-- doesn't distinguish the two).
		piece.station = FURNITURE_DEFS[itemId].station
		piece.stationHandle = CraftingService.registerStation(piece.station, model.PrimaryPart.Position)

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

	local half = CampService.ZONE_HALF
	if math.abs(x - camp.center.X) > half or math.abs(z - camp.center.Z) > half then
		notify(player, "Furniture has to go inside the camp's zone.")
		return { ok = false, error = "outside_zone" }
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
end

return CampFurnitureService