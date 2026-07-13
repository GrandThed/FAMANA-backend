-- remarcador de party y distancia a los miembros de la party wachin

-- se crea un highlight y un billboard gui para cada miembro de la party, y se actualiza la distancia pero no a tiempo real

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")

local player = Players.LocalPlayer

local PartyMarkerUI = {}

local MARKER_COLOR = Color3.fromRGB(255, 221, 51) -- fallback si el attribute todavía no replicó

-- Cada miembro tiene su propio Color3 asignado por PartyService (attribute
-- "PartyColor", mismo que usa MarkerUI para los pings) — así se distinguen
-- de un vistazo en vez de que todos compartan el mismo amarillo.
local function colorFor(memberPlayer)
	return memberPlayer:GetAttribute("PartyColor") or MARKER_COLOR
end
local DISTANCE_REFRESH = 0.25 -- segundos antes de que se actualice la distancia

function PartyMarkerUI.start()
	local rows = {} -- [userId] = { highlight, characterConn, billboard, distanceLabel }

	local function destroyRow(userId)
		local row = rows[userId]
		if not row then
			return
		end
		if row.characterConn then
			row.characterConn:Disconnect()
		end
		if row.highlight then
			row.highlight:Destroy()
		end
		if row.billboard then
			row.billboard:Destroy()
		end
		rows[userId] = nil
	end

	local function attachTo(row, character)
		local head = character:FindFirstChild("Head") or character:WaitForChild("HumanoidRootPart", 5)
		if not head then
			return
		end
		row.highlight.Adornee = character
		row.highlight.Parent = character
		row.billboard.Adornee = head
		row.billboard.Parent = head
	end

	local function buildRow(memberPlayer)
		local color = colorFor(memberPlayer)

		local highlight = Instance.new("Highlight")
		highlight.FillTransparency = 0.85
		highlight.FillColor = color
		highlight.OutlineColor = color
		highlight.OutlineTransparency = 0.1
		highlight.Enabled = true

		local billboard = Instance.new("BillboardGui")
		billboard.Name = "PartyMarker"
		billboard.Size = UDim2.new(0, 140, 0, 34)
		billboard.StudsOffset = Vector3.new(0, 2.6, 0)
		billboard.AlwaysOnTop = true -- con esto se muestra por encima de los objetos
		billboard.MaxDistance = 0 -- 0 = no hay distancia maxima

		local nameLabel = Instance.new("TextLabel")
		nameLabel.BackgroundTransparency = 1
		nameLabel.Size = UDim2.new(1, 0, 0, 18)
		nameLabel.Font = Enum.Font.GothamBold
		nameLabel.TextSize = 15
		nameLabel.TextColor3 = color
		nameLabel.TextStrokeTransparency = 0.2
		nameLabel.Text = memberPlayer.Name
		nameLabel.Parent = billboard

		local distanceLabel = Instance.new("TextLabel")
		distanceLabel.BackgroundTransparency = 1
		distanceLabel.Size = UDim2.new(1, 0, 0, 14)
		distanceLabel.Position = UDim2.new(0, 0, 0, 18)
		distanceLabel.Font = Enum.Font.Gotham
		distanceLabel.TextSize = 12
		distanceLabel.TextColor3 = Color3.new(1, 1, 1)
		distanceLabel.TextStrokeTransparency = 0.3
		distanceLabel.Text = ""
		distanceLabel.Parent = billboard

		local row = { highlight = highlight, billboard = billboard, distanceLabel = distanceLabel }

		if memberPlayer.Character then
			attachTo(row, memberPlayer.Character)
		end
		row.characterConn = memberPlayer.CharacterAdded:Connect(function(character)
			attachTo(row, character)
		end)

		rows[memberPlayer.UserId] = row
	end

	-- actualiza la lista de miembros de la party, agregando o eliminando los que entran o salen
	local function refresh()
		local myPartyId = player:GetAttribute("PartyId")

		if not myPartyId then
			for userId in pairs(rows) do
				destroyRow(userId)
			end
			return
		end

		local seen = {}
		for _, other in ipairs(Players:GetPlayers()) do
			if other ~= player and other:GetAttribute("PartyId") == myPartyId then
				seen[other.UserId] = true
				if not rows[other.UserId] then
					buildRow(other)
				end
			end
		end
		for userId in pairs(rows) do
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

	-- labes de distancia yippeeee
	local accumulator = 0
	RunService.Heartbeat:Connect(function(dt)
		accumulator += dt
		if accumulator < DISTANCE_REFRESH then
			return
		end
		accumulator = 0

		local myRoot = player.Character and player.Character:FindFirstChild("HumanoidRootPart")
		if not myRoot then
			return
		end

		for userId, row in pairs(rows) do
			local memberPlayer = Players:GetPlayerByUserId(userId)
			local character = memberPlayer and memberPlayer.Character
			local theirRoot = character and character:FindFirstChild("HumanoidRootPart")
			if theirRoot then
				local studs = (theirRoot.Position - myRoot.Position).Magnitude
				row.distanceLabel.Text = math.floor(studs + 0.5) .. "m"
			else
				row.distanceLabel.Text = ""
			end
		end
	end)
end

return PartyMarkerUI