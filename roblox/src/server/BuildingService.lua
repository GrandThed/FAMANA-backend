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

local DataStoreService = game:GetService("DataStoreService")
local structureDataStore = DataStoreService:GetDataStore("GuildHQ_Structures_V1")

local BuildingService = {}

local structuresFolder

-- [guildId] = { { pieceId = "...", position = Vector3, rotationY = number, model = Model }, ... }
local savedGuildStructures = {}

local function notify(player, text)
	Remotes.get("Notify"):FireClient(player, text)
end

function BuildingService.saveGuildStructures(guildId)
	if not guildId then
		return
	end
	local list = savedGuildStructures[guildId] or {}
	local data = {}
	for _, entry in ipairs(list) do
		table.insert(data, {
			pieceId = entry.pieceId,
			x = math.floor(entry.position.X * 100) / 100,
			y = math.floor(entry.position.Y * 100) / 100,
			z = math.floor(entry.position.Z * 100) / 100,
			rotY = entry.rotationY,
		})
	end
	pcall(function()
		structureDataStore:SetAsync("Guild_" .. tostring(guildId), data)
	end)
end

function BuildingService.buildDirectStructure(guildId, pieceId, position, rotationY)
	local pieceDef = BuildingConfig.getPiece(pieceId)
	if not pieceDef then
		return nil
	end

	local model = Instance.new("Model")
	model.Name = "GuildStructure_" .. pieceId
	model:SetAttribute("GuildId", guildId)
	model:SetAttribute("PieceId", pieceId)

	local cframe = CFrame.new(position) * CFrame.Angles(0, math.rad(rotationY), 0)

	if pieceDef.hasDoor then
		local baseCF = cframe * CFrame.new(pieceDef.offset or Vector3.zero)

		local leftWall = ArtKit.part(pieceDef.colorName or "trunkDark")
		leftWall.Name = "LeftWall"
		leftWall.Size = Vector3.new(4, 10, 0.6)
		leftWall.CFrame = baseCF * CFrame.new(-4, 0, 0)
		leftWall.Anchored = true
		leftWall.Parent = model

		local rightWall = ArtKit.part(pieceDef.colorName or "trunkDark")
		rightWall.Name = "RightWall"
		rightWall.Size = Vector3.new(4, 10, 0.6)
		rightWall.CFrame = baseCF * CFrame.new(4, 0, 0)
		rightWall.Anchored = true
		rightWall.Parent = model

		local lintel = ArtKit.part(pieceDef.colorName or "trunkDark")
		lintel.Name = "Lintel"
		lintel.Size = Vector3.new(4, 2.5, 0.6)
		lintel.CFrame = baseCF * CFrame.new(0, 3.75, 0)
		lintel.Anchored = true
		lintel.Parent = model

		model.PrimaryPart = leftWall

		local doorPanel = ArtKit.part("trunk")
		doorPanel.Name = "DoorPanel"
		doorPanel.Size = Vector3.new(3.9, 7.4, 0.4)

		local closedCF = baseCF * CFrame.new(0, -1.3, 0)
		doorPanel.CFrame = closedCF
		doorPanel.Anchored = true
		doorPanel.Parent = model

		local knob = ArtKit.part("gold")
		knob.Name = "Knob"
		knob.Size = Vector3.new(0.3, 0.3, 0.6)
		knob.CFrame = closedCF * CFrame.new(1.4, 0, 0)
		knob.Anchored = true
		knob.Parent = model

		local prompt = Instance.new("ProximityPrompt")
		prompt.ActionText = "Abrir Puerta"
		prompt.ObjectText = "Puerta del Gremio"
		prompt.HoldDuration = 0.1
		prompt.MaxActivationDistance = 10
		prompt.RequiresLineOfSight = false
		prompt.Parent = doorPanel

		local isOpen = false
		local TweenService = game:GetService("TweenService")
		local tweenInfo = TweenInfo.new(0.35, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)

		prompt.Triggered:Connect(function(triggeringPlayer)
			isOpen = not isOpen
			prompt.ActionText = isOpen and "Cerrar Puerta" or "Abrir Puerta"

			local swingAngle = 90
			if isOpen and triggeringPlayer and triggeringPlayer.Character then
				local root = triggeringPlayer.Character:FindFirstChild("HumanoidRootPart")
				if root then
					local localPos = closedCF:PointToObjectSpace(root.Position)
					if localPos.Z > 0 then
						swingAngle = 90
					else
						swingAngle = -90
					end
				end
			end

			local hingeCF = closedCF * CFrame.new(-1.95, 0, 0)
			local targetCF = isOpen and (hingeCF * CFrame.Angles(0, math.rad(swingAngle), 0) * CFrame.new(1.95, 0, 0)) or closedCF
			local knobTargetCF = isOpen and (targetCF * CFrame.new(1.4, 0, 0)) or (closedCF * CFrame.new(1.4, 0, 0))

			TweenService:Create(doorPanel, tweenInfo, { CFrame = targetCF }):Play()
			TweenService:Create(knob, tweenInfo, { CFrame = knobTargetCF }):Play()
		end)

	elseif pieceDef.hasWindow then
		local baseCF = cframe * CFrame.new(pieceDef.offset or Vector3.zero)

		local leftWall = ArtKit.part(pieceDef.colorName or "trunkDark")
		leftWall.Name = "LeftWall"
		leftWall.Size = Vector3.new(3.5, 10, 0.6)
		leftWall.CFrame = baseCF * CFrame.new(-4.25, 0, 0)
		leftWall.Anchored = true
		leftWall.Parent = model

		local rightWall = ArtKit.part(pieceDef.colorName or "trunkDark")
		rightWall.Name = "RightWall"
		rightWall.Size = Vector3.new(3.5, 10, 0.6)
		rightWall.CFrame = baseCF * CFrame.new(4.25, 0, 0)
		rightWall.Anchored = true
		rightWall.Parent = model

		local sill = ArtKit.part(pieceDef.colorName or "trunkDark")
		sill.Name = "Sill"
		sill.Size = Vector3.new(5, 3, 0.6)
		sill.CFrame = baseCF * CFrame.new(0, -3.5, 0)
		sill.Anchored = true
		sill.Parent = model

		local header = ArtKit.part(pieceDef.colorName or "trunkDark")
		header.Name = "Header"
		header.Size = Vector3.new(5, 3, 0.6)
		header.CFrame = baseCF * CFrame.new(0, 3.5, 0)
		header.Anchored = true
		header.Parent = model

		local glass = Instance.new("Part")
		glass.Name = "WindowGlass"
		glass.Size = Vector3.new(4.9, 3.9, 0.1)
		glass.CFrame = baseCF * CFrame.new(0, 0, 0)
		glass.Material = Enum.Material.Glass
		glass.Color = Color3.fromRGB(180, 220, 255)
		glass.Transparency = 0.5
		glass.Anchored = true
		glass.CanCollide = false
		glass.Parent = model

		model.PrimaryPart = leftWall
	else
		local mainPart = ArtKit.part(pieceDef.colorName or "trunk")
		mainPart.Name = "MainPart"
		mainPart.Size = pieceDef.size
		mainPart.CFrame = cframe * CFrame.new(pieceDef.offset or Vector3.zero)
		mainPart.Anchored = true
		mainPart.Parent = model
		model.PrimaryPart = mainPart

		if pieceId:find("techo") or pieceId:find("roof") then
			mainPart.CastShadow = false
			local indoorLight = Instance.new("PointLight")
			indoorLight.Name = "RoofAmbientLight"
			indoorLight.Color = Color3.fromRGB(255, 215, 160)
			indoorLight.Range = 36
			indoorLight.Brightness = 0.20
			indoorLight.Shadows = false
			indoorLight.Parent = mainPart
		end
	end

	if pieceDef.material then
		for _, part in ipairs(model:GetDescendants()) do
			if part:IsA("BasePart") and part.Name ~= "WindowGlass" and part.Name ~= "Knob" and part.Name ~= "DoorPanel" then
				part.Material = pieceDef.material
			end
		end
	end

	structuresFolder = structuresFolder or Workspace:FindFirstChild("GuildStructures") or Instance.new("Folder", Workspace)
	structuresFolder.Name = "GuildStructures"
	model.Parent = structuresFolder

	savedGuildStructures[guildId] = savedGuildStructures[guildId] or {}
	table.insert(savedGuildStructures[guildId], {
		pieceId = pieceId,
		position = position,
		rotationY = rotationY,
		model = model,
	})

	return model
end

function BuildingService.loadGuildStructures(guildId)
	if not guildId then
		return
	end
	local success, data = pcall(function()
		return structureDataStore:GetAsync("Guild_" .. tostring(guildId))
	end)
	if success and type(data) == "table" then
		local validEntries = {}
		for _, entry in ipairs(data) do
			local pos = Vector3.new(entry.x, entry.y, entry.z)
			if GuildPlotService.isPositionInGuildHQ(pos, guildId) then
				BuildingService.buildDirectStructure(guildId, entry.pieceId, pos, entry.rotY)
				table.insert(validEntries, entry)
			end
		end
		-- Save cleaned data back to DataStore
		pcall(function()
			structureDataStore:SetAsync("Guild_" .. tostring(guildId), validEntries)
		end)
	end
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

	if pieceDef.hasDoor then
		local baseCF = cframe * CFrame.new(pieceDef.offset or Vector3.zero)

		-- Left wall pillar (4 wide, 10 high)
		local leftWall = ArtKit.part(pieceDef.colorName or "trunkDark")
		leftWall.Name = "LeftWall"
		leftWall.Size = Vector3.new(4, 10, 0.6)
		leftWall.CFrame = baseCF * CFrame.new(-4, 0, 0)
		leftWall.Anchored = true
		leftWall.Parent = model

		-- Right wall pillar (4 wide, 10 high)
		local rightWall = ArtKit.part(pieceDef.colorName or "trunkDark")
		rightWall.Name = "RightWall"
		rightWall.Size = Vector3.new(4, 10, 0.6)
		rightWall.CFrame = baseCF * CFrame.new(4, 0, 0)
		rightWall.Anchored = true
		rightWall.Parent = model

		-- Lintel top beam (4 wide, 2.5 high)
		local lintel = ArtKit.part(pieceDef.colorName or "trunkDark")
		lintel.Name = "Lintel"
		lintel.Size = Vector3.new(4, 2.5, 0.6)
		lintel.CFrame = baseCF * CFrame.new(0, 3.75, 0)
		lintel.Anchored = true
		lintel.Parent = model

		model.PrimaryPart = leftWall

		-- Door Panel (3.9 wide, 7.4 high, 0.4 thick) inside the 4x7.5 opening
		local doorPanel = ArtKit.part("trunk")
		doorPanel.Name = "DoorPanel"
		doorPanel.Size = Vector3.new(3.9, 7.4, 0.4)

		local closedCF = baseCF * CFrame.new(0, -1.3, 0)
		doorPanel.CFrame = closedCF
		doorPanel.Anchored = true
		doorPanel.Parent = model

		-- Handle knob
		local knob = ArtKit.part("gold")
		knob.Name = "Knob"
		knob.Size = Vector3.new(0.3, 0.3, 0.6)
		knob.CFrame = closedCF * CFrame.new(1.4, 0, 0)
		knob.Anchored = true
		knob.Parent = model

		local prompt = Instance.new("ProximityPrompt")
		prompt.ActionText = "Abrir Puerta"
		prompt.ObjectText = "Puerta del Gremio"
		prompt.HoldDuration = 0.1
		prompt.MaxActivationDistance = 10
		prompt.RequiresLineOfSight = false
		prompt.Parent = doorPanel

		local isOpen = false
		local TweenService = game:GetService("TweenService")
		local tweenInfo = TweenInfo.new(0.35, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)

		prompt.Triggered:Connect(function()
			isOpen = not isOpen
			prompt.ActionText = isOpen and "Cerrar Puerta" or "Abrir Puerta"

			local hingeCF = closedCF * CFrame.new(-1.95, 0, 0)
			local targetCF = isOpen and (hingeCF * CFrame.Angles(0, math.rad(-90), 0) * CFrame.new(1.95, 0, 0)) or closedCF
			local knobTargetCF = isOpen and (targetCF * CFrame.new(1.4, 0, 0)) or (closedCF * CFrame.new(1.4, 0, 0))

			TweenService:Create(doorPanel, tweenInfo, { CFrame = targetCF }):Play()
			TweenService:Create(knob, tweenInfo, { CFrame = knobTargetCF }):Play()
		end)

	elseif pieceDef.hasWindow then
		local baseCF = cframe * CFrame.new(pieceDef.offset or Vector3.zero)

		-- Left Pillar (3.5 wide, 10 high)
		local leftWall = ArtKit.part(pieceDef.colorName or "trunkDark")
		leftWall.Name = "LeftWall"
		leftWall.Size = Vector3.new(3.5, 10, 0.6)
		leftWall.CFrame = baseCF * CFrame.new(-4.25, 0, 0)
		leftWall.Anchored = true
		leftWall.Parent = model

		-- Right Pillar (3.5 wide, 10 high)
		local rightWall = ArtKit.part(pieceDef.colorName or "trunkDark")
		rightWall.Name = "RightWall"
		rightWall.Size = Vector3.new(3.5, 10, 0.6)
		rightWall.CFrame = baseCF * CFrame.new(4.25, 0, 0)
		rightWall.Anchored = true
		rightWall.Parent = model

		-- Bottom Sill (5 wide, 3 high)
		local sill = ArtKit.part(pieceDef.colorName or "trunkDark")
		sill.Name = "Sill"
		sill.Size = Vector3.new(5, 3, 0.6)
		sill.CFrame = baseCF * CFrame.new(0, -3.5, 0)
		sill.Anchored = true
		sill.Parent = model

		-- Top Header (5 wide, 3 high)
		local header = ArtKit.part(pieceDef.colorName or "trunkDark")
		header.Name = "Header"
		header.Size = Vector3.new(5, 3, 0.6)
		header.CFrame = baseCF * CFrame.new(0, 3.5, 0)
		header.Anchored = true
		header.Parent = model

		-- Glass Panel in center (5 wide, 4 high, 0.1 thick)
		local glass = Instance.new("Part")
		glass.Name = "WindowGlass"
		glass.Size = Vector3.new(4.9, 3.9, 0.1)
		glass.CFrame = baseCF * CFrame.new(0, 0, 0)
		glass.Material = Enum.Material.Glass
		glass.Color = Color3.fromRGB(180, 220, 255)
		glass.Transparency = 0.5
		glass.Anchored = true
		glass.CanCollide = false
		glass.Parent = model

		model.PrimaryPart = leftWall
	else
		-- Standard solid floor / wall / roof
		local mainPart = ArtKit.part(pieceDef.colorName or "trunk")
		mainPart.Name = "MainPart"
		mainPart.Size = pieceDef.size
		mainPart.CFrame = cframe * CFrame.new(pieceDef.offset or Vector3.zero)
		mainPart.Anchored = true
		mainPart.Parent = model
		model.PrimaryPart = mainPart
	end

	if pieceDef.material then
		for _, part in ipairs(model:GetDescendants()) do
			if part:IsA("BasePart") and part.Name ~= "WindowGlass" and part.Name ~= "Knob" then
				part.Material = pieceDef.material
			end
		end
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
	BuildingService.saveGuildStructures(guildId)

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
		local res = BuildingService.placeStructure(player, payload)
		if res and res.ok then
			local gId = player:GetAttribute("GuildId")
			BuildingService.saveGuildStructures(gId)
		end
		return res
	end

	demolishRemote.OnServerInvoke = function(player, targetModel)
		return BuildingService.demolishStructure(player, targetModel)
	end

	local function onPlayerJoined(player)
		task.delay(1.5, function()
			local gId = player:GetAttribute("GuildId")
			if gId then
				BuildingService.loadGuildStructures(gId)
			end
		end)
	end

	Players.PlayerAdded:Connect(onPlayerJoined)
	for _, p in ipairs(Players:GetPlayers()) do
		onPlayerJoined(p)
	end
end

return BuildingService
