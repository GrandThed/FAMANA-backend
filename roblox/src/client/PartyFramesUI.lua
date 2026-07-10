-- frames de party que muestran la salud y mana de los miembros del party
-- además de los nombres de cada uno y la clase 
-- el botón de "open" o "closed" significa que todos pueden invitar a otros miembros o solo el líder puede hacerlo
-- son rectangulos simples como placeholder para cuando tengamos un diseño de interfaz fijo
-- en teoría los colores, las fuentes y qsio deberían poder modificarse desde acá cuando la interfaz nueva se arme
-- *importante* la lista de jugadores para invitar solo muestran jugadores disponibles, si ya hay uno en una party no va a aparecer ahí

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Classes = require(Shared:WaitForChild("Classes"))

local player = Players.LocalPlayer

local PartyFramesUI = {}

local COLORS = {
	frame = Color3.fromRGB(25, 25, 28),
	good = Color3.fromRGB(80, 180, 90),
	mana = Color3.fromRGB(70, 130, 220),
	barBack = Color3.fromRGB(15, 15, 18),
	text = Color3.fromRGB(235, 235, 240),
	textDim = Color3.fromRGB(165, 165, 175),
}

local FRAME_WIDTH = 230
local FRAME_HEIGHT = 60
local FRAME_GAP = 6
local LEFT_MARGIN = 16

local function makeBar(parent, position, size, fillColor)
	local back = Instance.new("Frame")
	back.BackgroundColor3 = COLORS.barBack
	back.BorderSizePixel = 0
	back.Position = position
	back.Size = size
	back.Parent = parent

	local fill = Instance.new("Frame")
	fill.BackgroundColor3 = fillColor
	fill.BorderSizePixel = 0
	fill.Size = UDim2.new(1, 0, 1, 0)
	fill.Parent = back

	return function(current, max)
		local ratio = max > 0 and math.clamp(current / max, 0, 1) or 0
		fill.Size = UDim2.new(ratio, 0, 1, 0)
	end
end

function PartyFramesUI.start()
	local gui = Instance.new("ScreenGui")
	gui.Name = "PartyFramesUI"
	gui.ResetOnSpawn = false
	gui.DisplayOrder = 190 
	gui.Parent = player:WaitForChild("PlayerGui")

	-- más o menos centrado a la izquierda, pero no pegado al borde de la pantalla
	local container = Instance.new("Frame")
	container.BackgroundTransparency = 1
	container.AnchorPoint = Vector2.new(0, 0.5)
	container.Position = UDim2.new(0, LEFT_MARGIN, 0.5, 0)
	container.Size = UDim2.new(0, FRAME_WIDTH, 0, 0)
	container.AutomaticSize = Enum.AutomaticSize.Y
	container.Parent = gui

	local layout = Instance.new("UIListLayout")
	layout.SortOrder = Enum.SortOrder.LayoutOrder
	layout.Padding = UDim.new(0, FRAME_GAP)
	layout.Parent = container

	local rowConnections = {} -- [userId] = { connections... }
	local rowFrames = {} -- [userId] = Frame

	local function destroyRow(userId)
		local conns = rowConnections[userId]
		if conns then
			for _, c in ipairs(conns) do
				c:Disconnect()
			end
			rowConnections[userId] = nil
		end
		local frame = rowFrames[userId]
		if frame then
			frame:Destroy()
			rowFrames[userId] = nil
		end
	end

	local function buildRow(memberPlayer, layoutOrder)
		local frame = Instance.new("Frame")
		frame.BackgroundColor3 = COLORS.frame
		frame.BackgroundTransparency = 0.15
		frame.BorderSizePixel = 0
		frame.Size = UDim2.new(1, 0, 0, FRAME_HEIGHT)
		frame.LayoutOrder = layoutOrder
		frame.Parent = container

		local nameLabel = Instance.new("TextLabel")
		nameLabel.BackgroundTransparency = 1
		nameLabel.Font = Enum.Font.GothamBold
		nameLabel.TextSize = 14
		nameLabel.TextColor3 = COLORS.text
		nameLabel.TextXAlignment = Enum.TextXAlignment.Left
		nameLabel.TextTruncate = Enum.TextTruncate.AtEnd
		nameLabel.Size = UDim2.new(0.6, -8, 0, 18)
		nameLabel.Position = UDim2.new(0, 8, 0, 4)
		nameLabel.Text = memberPlayer.Name
		nameLabel.Parent = frame

		local classLabel = Instance.new("TextLabel")
		classLabel.BackgroundTransparency = 1
		classLabel.Font = Enum.Font.Gotham
		classLabel.TextSize = 12
		classLabel.TextColor3 = COLORS.textDim
		classLabel.TextXAlignment = Enum.TextXAlignment.Right
		classLabel.Size = UDim2.new(0.4, -8, 0, 18)
		classLabel.Position = UDim2.new(0.6, 0, 0, 4)
		classLabel.Parent = frame

		local setHp = makeBar(frame, UDim2.new(0, 8, 0, 26), UDim2.new(1, -16, 0, 10), COLORS.good)
		local setMana = makeBar(frame, UDim2.new(0, 8, 0, 40), UDim2.new(1, -16, 0, 10), COLORS.mana)

		local connections = {}

		local function refreshClass()
			if memberPlayer:GetAttribute("Downed") then
				classLabel.Text = "Caído"
				classLabel.TextColor3 = Color3.fromRGB(255, 110, 110)
				return
			end
			local def = Classes.get(memberPlayer:GetAttribute("Class"))
			classLabel.TextColor3 = COLORS.textDim
			classLabel.Text = def and def.name or ""
		end
		table.insert(connections, memberPlayer:GetAttributeChangedSignal("Class"):Connect(refreshClass))
		table.insert(connections, memberPlayer:GetAttributeChangedSignal("Downed"):Connect(refreshClass))
		refreshClass()

		local function refreshMana()
			setMana(memberPlayer:GetAttribute("Mana") or 0, memberPlayer:GetAttribute("MaxMana") or 100)
		end
		table.insert(connections, memberPlayer:GetAttributeChangedSignal("Mana"):Connect(refreshMana))
		table.insert(connections, memberPlayer:GetAttributeChangedSignal("MaxMana"):Connect(refreshMana))
		refreshMana()

		local function bindHealth(character)
			local humanoid = character:WaitForChild("Humanoid", 5)
			if not humanoid then
				return
			end
			local function refreshHp()
				setHp(humanoid.Health, humanoid.MaxHealth)
			end
			table.insert(connections, humanoid.HealthChanged:Connect(refreshHp))
			table.insert(connections, humanoid:GetPropertyChangedSignal("MaxHealth"):Connect(refreshHp))
			refreshHp()
		end
		if memberPlayer.Character then
			task.spawn(bindHealth, memberPlayer.Character)
		end
		table.insert(connections, memberPlayer.CharacterAdded:Connect(bindHealth))

		rowConnections[memberPlayer.UserId] = connections
		rowFrames[memberPlayer.UserId] = frame
	end

	-- esto es un refresh para cuando alguien entra o sale de la party
	local function refresh()
		local myPartyId = player:GetAttribute("PartyId")

		if not myPartyId then
			for userId in pairs(rowFrames) do
				destroyRow(userId)
			end
			return
		end

		-- esto guarda los miembros de la party en un array y los ordena por nombre para que siempre aparezcan en el mismo orden
		local members = {}
		for _, other in ipairs(Players:GetPlayers()) do
			if other ~= player and other:GetAttribute("PartyId") == myPartyId then
				table.insert(members, other)
			end
		end
		table.sort(members, function(a, b)
			return a.Name < b.Name
		end)

		local seen = {}
		for i, memberPlayer in ipairs(members) do
			seen[memberPlayer.UserId] = true
			if not rowFrames[memberPlayer.UserId] then
				buildRow(memberPlayer, i)
			else
				rowFrames[memberPlayer.UserId].LayoutOrder = i
			end
		end
		for userId in pairs(rowFrames) do
			if not seen[userId] then
				destroyRow(userId)
			end
		end
	end

	local function watchPlayer(p)
		p:GetAttributeChangedSignal("PartyId"):Connect(refresh)
	end
	for _, p in ipairs(Players:GetPlayers()) do
		watchPlayer(p)
	end
	Players.PlayerAdded:Connect(function(p)
		watchPlayer(p)
		refresh()
	end)
	Players.PlayerRemoving:Connect(function(p)
		destroyRow(p.UserId)
		refresh()
	end)

	refresh()
end

return PartyFramesUI