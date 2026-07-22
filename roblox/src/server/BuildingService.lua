-- Building Service (Rust-Style Modular Building System).
-- Handles server-validated placement of floors, walls, doors, windows, and roofs
-- inside claimed Guild Headquarters plots. Supports door interactions and structure demolition.

local Players = game:GetService("Players")
local Workspace = game:GetService("Workspace")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Remotes = require(Shared:WaitForChild("Remotes"))
local ArtKit = require(Shared:WaitForChild("ArtKit"))
local BuildingConfig = require(Shared:WaitForChild("BuildingConfig"))
local PlayerService = require(script.Parent.PlayerService)
local GuildPlotService = require(script.Parent.GuildPlotService)

local BuildingService = {}

local structuresFolder

-- [guildId] = { { pieceId = "...", x = 0, y = 0, z = 0, rotY = 0, model = Model }, ... }
local savedGuildStructures = {}

local function notify(player, text)
	Remotes.get("Notify"):FireClient(player, text)
end

function BuildingService.placeStructure(player, payload)
	if typeof(payload) ~= "table" then
		return { ok = false }
	end

	local pieceId = payload.pieceId
	local position = payload.position
	local rotationY = payload.rotationY or 0

	local guildId = player:GetAttribute("GuildId")
	if not guildId then
		notify(player, "Debes pertenecer a un gremio para construir estructuras.")
		return { ok = false, error = "no_guild" }
	end

	if typeof(position) ~= "Vector3" then
		return { ok = false, error = "invalid_position" }
	end

	if not GuildPlotService.isPositionInGuildHQ(position, guildId) then
		notify(player, "Las estructuras solo se pueden edificar dentro de la Sede Oficial de tu Gremio.")
		return { ok = false, error = "outside_hq" }
	end

	local pieceDef = BuildingConfig.getPiece(pieceId)
	if not pieceDef then
		return { ok = false, error = "invalid_piece" }
	end

	-- Check and deduct materials
	for matItem, matQty in pairs(pieceDef.cost) do
		if not PlayerService.removeItem(player, matItem, matQty) then
			notify(player, string.format("Necesitas %dx %s para construir %s.", matQty, matItem, pieceDef.name))
			return { ok = false, error = "no_materials" }
		end
	end

	-- Build Model
	local model = Instance.new("Model")
	model.Name = "GuildStructure_" .. pieceId
	model:SetAttribute("GuildId", guildId)
	model:SetAttribute("PieceId", pieceId)
	model:SetAttribute("OwnerId", player.UserId)

	local cframe = CFrame.new(position) * CFrame.Angles(0, math.rad(rotationY), 0)

	local mainPart = ArtKit.part(pieceDef.colorName or "trunk")
	mainPart.Name = "MainPart"
	mainPart.Size = pieceDef.size
	mainPart.CFrame = cframe * CFrame.new(pieceDef.offset or Vector3.zero)
	mainPart.Anchored = true
	mainPart.Parent = model
	model.PrimaryPart = mainPart

	-- Handle Doorway interaction if door piece
	if pieceDef.hasDoor then
		local door = ArtKit.part("trunkDark")
		door.Name = "DoorPanel"
		door.Size = Vector3.new(4, 8, 0.4)
		door.CFrame = mainPart.CFrame * CFrame.new(0, -0.5, 0)
		door.Anchored = true
		door.Parent = model

		local prompt = Instance.new("ProximityPrompt")
		prompt.ActionText = "Abrir / Cerrar Puerta"
		prompt.ObjectText = "Puerta del Gremio"
		prompt.HoldDuration = 0.1
		prompt.MaxActivationDistance = 10
		prompt.RequiresLineOfSight = false
		prompt.Parent = door

		local isOpen = false
		prompt.Triggered:Connect(function()
			isOpen = not isOpen
			door.CanCollide = not isOpen
			door.Transparency = isOpen and 0.5 or 0
		end)
	end

	model.Parent = structuresFolder
	savedGuildStructures[guildId] = savedGuildStructures[guildId] or {}
	table.insert(savedGuildStructures[guildId], {
		pieceId = pieceId,
		position = position,
		rotationY = rotationY,
		model = model,
	})

	notify(player, string.format("¡Construiste: %s!", pieceDef.name))
	return { ok = true }
end

function BuildingService.demolishStructure(player, targetModel)
	if not (targetModel and targetModel:IsA("Model") and targetModel:GetAttribute("PieceId")) then
		return { ok = false }
	end

	local guildId = player:GetAttribute("GuildId")
	if not guildId or targetModel:GetAttribute("GuildId") ~= guildId then
		notify(player, "Solo puedes demoler estructuras pertenecientes a tu gremio.")
		return { ok = false, error = "not_owner" }
	end

	local pieceId = targetModel:GetAttribute("PieceId")
	local pieceDef = BuildingConfig.getPiece(pieceId)

	-- Remove from saved structures list
	if savedGuildStructures[guildId] then
		for i, entry in ipairs(savedGuildStructures[guildId]) do
			if entry.model == targetModel then
				table.remove(savedGuildStructures[guildId], i)
				break
			end
		end
	end

	targetModel:Destroy()

	-- Refund 50% materials
	if pieceDef then
		for matItem, matQty in pairs(pieceDef.cost) do
			local refundQty = math.max(1, math.floor(matQty * 0.5))
			PlayerService.addItem(player, matItem, refundQty, true)
		end
	end

	notify(player, "Estructura demolida. Se reembolsaron materiales.")
	return { ok = true }
end

function BuildingService.start()
	structuresFolder = Workspace:FindFirstChild("GuildStructures") or Instance.new("Folder", Workspace)
	structuresFolder.Name = "GuildStructures"

	local placeRemote = Remotes.getFunction("PlaceStructure")
	local demolishRemote = Remotes.getFunction("DemolishStructure")

	placeRemote.OnServerInvoke = function(player, payload)
		return BuildingService.placeStructure(player, payload)
	end

	demolishRemote.OnServerInvoke = function(player, targetModel)
		return BuildingService.demolishStructure(player, targetModel)
	end
end

return BuildingService
