-- Marcadores de ping: apuntá con el mouse a un enemigo, un drop en el suelo,
-- o cualquier punto del terreno, y hacé click con la RUEDA del mouse
-- (MouseButton3) para dejar una baliza ahí.
--
--   click medio solo          -> marcador PERSONAL (solo lo ves vos)
--   Shift + click medio       -> marcador de PARTY (lo ven todos tus
--                                 compañeros de grupo, y ellos a vos)
--
-- El cliente solo manda intención (qué apunta el mouse + con qué modificador)
-- — MarkerService del server valida el anchor, decide a quién replicarlo, y
-- es quien realmente crea/destruye el marcador lógico. Esto acá solo dibuja
-- lo que el server confirma, mismo patrón que TargetingController con el
-- highlight de foco.

local Players = game:GetService("Players")
local UserInputService = game:GetService("UserInputService")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Remotes = require(Shared:WaitForChild("Remotes"))
local ClientState = require(script.Parent.ClientState)
local Theme = require(script.Parent.Theme)

local player = Players.LocalPlayer
local mouse = player:GetMouse()

local MarkerUI = {}

local MARK_COLOR = Theme.Semantic.Good -- fallback: sin party, o mientras el attribute todavía no replicó
local ICONS = { enemy = "⚔️", loot = "💰", ground = "📍" }
local LABELS = { enemy = "Enemigo", loot = "Loot", ground = "Aquí" }

-- Cada miembro de party tiene su propio Color3 asignado por PartyService,
-- expuesto como el attribute "PartyColor" (mismo mecanismo que PartyId —
-- replica solo, sin remote nuevo). Sin party, cae al verde de siempre.
local function colorFor(ownerUserId)
	local owner = Players:GetPlayerByUserId(ownerUserId)
	local partyColor = owner and owner:GetAttribute("PartyColor")
	return partyColor or MARK_COLOR
end

-- Construye el visual (highlight + billboard, y para "ground" también un
-- part-baliza invisible que sirve de anchor) para un marcador confirmado
-- por el server. Devuelve la entry a guardar en `markers[ownerUserId]`.
local function buildVisual(payload)
	local entry = {}
	local color = colorFor(payload.ownerUserId)
	local adornee

	if payload.anchor then
		local highlight = Instance.new("Highlight")
		highlight.FillTransparency = 0.75
		highlight.OutlineTransparency = 0
		highlight.FillColor = color
		highlight.OutlineColor = color
		highlight.DepthMode = Enum.HighlightDepthMode.AlwaysOnTop
		highlight.Adornee = payload.anchor
		highlight.Parent = payload.anchor
		entry.highlight = highlight
		adornee = payload.anchor
	else
		-- Sin instancia real que adornar (es un punto del piso): un part
		-- invisible, no sólido, que no bloquea el mouse (CanQuery = false),
		-- solo para colgar el billboard y el haz — mismo truco que el preview
		-- de CampPlacementUI.
		local anchorPart = Instance.new("Part")
		anchorPart.Name = "MarkerAnchor"
		anchorPart.Anchored = true
		anchorPart.CanCollide = false
		anchorPart.CanQuery = false
		anchorPart.Transparency = 1
		anchorPart.Size = Vector3.new(0.2, 0.2, 0.2)
		anchorPart.CFrame = CFrame.new(payload.position)
		anchorPart.Parent = Workspace
		entry.anchorPart = anchorPart
		adornee = anchorPart

		-- Haz vertical tipo baliza, para verlo de lejos por encima del pasto/rocas.
		local beam = Instance.new("Part")
		beam.Name = "MarkerBeam"
		beam.Anchored = true
		beam.CanCollide = false
		beam.CanQuery = false
		beam.Material = Enum.Material.Neon
		beam.Color = color
		beam.Size = Vector3.new(0.3, 8, 0.3)
		beam.CFrame = CFrame.new(payload.position + Vector3.new(0, 4, 0))
		beam.Parent = Workspace
		entry.beam = beam

		-- Pulso simple (transparencia oscilando) para que se note que está "vivo".
		entry.pulseConn = RunService.Heartbeat:Connect(function()
			beam.Transparency = 0.3 + 0.35 * (0.5 + 0.5 * math.sin(os.clock() * 4))
		end)
	end

	local billboard = Instance.new("BillboardGui")
	billboard.Name = "Marker"
	billboard.Size = UDim2.new(0, 160, 0, 36)
	billboard.StudsOffset = Vector3.new(0, payload.anchor and 3.5 or 8.6, 0)
	billboard.AlwaysOnTop = true
	billboard.MaxDistance = 400
	billboard.Adornee = adornee
	billboard.Parent = adornee

	local nameLabel = Instance.new("TextLabel")
	nameLabel.BackgroundTransparency = 1
	nameLabel.Size = UDim2.new(1, 0, 0, 18)
	nameLabel.Font = Enum.Font.GothamBold
	nameLabel.TextSize = 15
	nameLabel.TextColor3 = color
	nameLabel.TextStrokeTransparency = 0.2
	nameLabel.Text = (ICONS[payload.kind] or "📍") .. " " .. payload.ownerName
	nameLabel.Parent = billboard

	local kindLabel = Instance.new("TextLabel")
	kindLabel.BackgroundTransparency = 1
	kindLabel.Size = UDim2.new(1, 0, 0, 14)
	kindLabel.Position = UDim2.new(0, 0, 0, 18)
	kindLabel.Font = Enum.Font.Gotham
	kindLabel.TextSize = 12
	kindLabel.TextColor3 = Color3.new(1, 1, 1)
	kindLabel.TextStrokeTransparency = 0.3
	kindLabel.Text = LABELS[payload.kind] or ""
	kindLabel.Parent = billboard

	entry.billboard = billboard
	return entry
end

local function destroyEntry(entry)
	if entry.pulseConn then
		entry.pulseConn:Disconnect()
	end
	if entry.highlight then
		entry.highlight:Destroy()
	end
	if entry.billboard then
		entry.billboard:Destroy()
	end
	if entry.beam then
		entry.beam:Destroy()
	end
	if entry.anchorPart then
		entry.anchorPart:Destroy()
	end
end

function MarkerUI.start()
	local requestMarkRemote = Remotes.get("RequestMark")
	local markerUpdatedRemote = Remotes.get("MarkerUpdated")
	local markerClearedRemote = Remotes.get("MarkerCleared")

	local markers = {} -- [ownerUserId] = entry (ver buildVisual)

	local function clear(ownerUserId)
		local entry = markers[ownerUserId]
		if entry then
			markers[ownerUserId] = nil
			destroyEntry(entry)
		end
	end

	markerUpdatedRemote.OnClientEvent:Connect(function(payload)
		clear(payload.ownerUserId) -- por si ya había uno viejo de este dueño
		markers[payload.ownerUserId] = buildVisual(payload)
	end)

	markerClearedRemote.OnClientEvent:Connect(function(ownerUserId)
		clear(ownerUserId)
	end)

	UserInputService.InputBegan:Connect(function(input, gameProcessed)
		if gameProcessed or input.UserInputType ~= Enum.UserInputType.MouseButton3 then
			return
		end
		-- Mismos paneles full-screen que EnemyInspectUI respeta — no competir
		-- por el click mientras el jugador está en un menú.
		if ClientState.inventoryOpen or ClientState.storeOpen or ClientState.questOpen or ClientState.chestOpen then
			return
		end

		local target = mouse.Target
		if not target then
			return
		end

		local kind, instance, position
		local enemiesFolder = Workspace:FindFirstChild("Enemies")
		local dropsFolder = Workspace:FindFirstChild("Drops")
		if enemiesFolder and target.Parent == enemiesFolder and target:FindFirstChild("HealthBar") then
			kind, instance = "enemy", target
		elseif dropsFolder and target.Parent == dropsFolder and target.Name == "Drop" then
			kind, instance = "loot", target
		else
			kind, position = "ground", mouse.Hit.Position
		end

		local partyScope = UserInputService:IsKeyDown(Enum.KeyCode.LeftShift)
			or UserInputService:IsKeyDown(Enum.KeyCode.RightShift)
		requestMarkRemote:FireServer(kind, instance, position, partyScope and "party" or "self")
	end)
end

return MarkerUI
