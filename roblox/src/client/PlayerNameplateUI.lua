-- Nametag propio arriba de la cabeza de CADA jugador (local y remotos):
-- nombre + "Clase — Lv.X", en vez del nameplate default de Roblox. Mismo
-- patrón de BillboardGui que el NameTag de los enemigos (server/EnemyService
-- + client/EnemyLevelUI), pero acá vive todo del lado del cliente porque
-- Class/Level ya son atributos replicados del Player (ver PlayerService /
-- ClassService — los mismos que lee CharacterUI).

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Classes = require(Shared:WaitForChild("Classes"))
local Theme = require(script.Parent.Theme)

local localPlayer = Players.LocalPlayer

local PlayerNameplateUI = {}

-- Fuera de party, el nametag solo se ve de cerca (evita el ruido visual de
-- nombres flotando por todo el mapa). A un aliado de party se lo ve sin
-- límite de distancia, con la distancia en studs debajo del nombre.
local NON_PARTY_VIEW_DISTANCE = 40
local REFRESH_INTERVAL = 0.2 -- segundos entre updates de distancia/estado de party

local function isPartyAlly(player)
	if player == localPlayer then
		return false
	end
	local myPartyId = localPlayer:GetAttribute("PartyId")
	return myPartyId ~= nil and player:GetAttribute("PartyId") == myPartyId
end

-- Escapa los caracteres especiales de RichText para que un DisplayName o tag
-- con < > & " no rompa el markup del TextLabel.
local function escapeRichText(text)
	return (text:gsub("&", "&amp;"):gsub("<", "&lt;"):gsub(">", "&gt;"):gsub("\"", "&quot;"))
end

local function buildNameText(player)
	local guildTag = player:GetAttribute("GuildTag")
	local name = escapeRichText(player.DisplayName)
	if guildTag and guildTag ~= "" then
		-- Tag del gremio a la izquierda del nombre, en un color distinto
		-- (Ember300, el acento del theme) para diferenciarlo del nombre.
		return string.format(
			'<font color="#%s">[%s]</font> %s',
			Theme.Color.Ember300:ToHex(),
			escapeRichText(guildTag),
			name
		)
	end
	return name
end

local function buildTag(head, player)
	local existing = head:FindFirstChild("Nameplate")
	if existing then
		existing:Destroy()
	end

	local billboard = Instance.new("BillboardGui")
	billboard.Name = "Nameplate"
	billboard.Size = UDim2.new(0, 160, 0, 48)
	billboard.StudsOffsetWorldSpace = Vector3.new(0, 1.1, 0)
	billboard.AlwaysOnTop = true
	billboard.Parent = head

	local nameLabel = Instance.new("TextLabel")
	nameLabel.Name = "NameLabel"
	nameLabel.Size = UDim2.new(1, 0, 0, 18)
	nameLabel.BackgroundTransparency = 1
	nameLabel.FontFace = Theme.Font.BodyBold
	nameLabel.TextSize = 15
	nameLabel.TextColor3 = Theme.Color.NameGold
	nameLabel.TextStrokeTransparency = 0.4
	nameLabel.RichText = true
	nameLabel.Text = buildNameText(player)
	nameLabel.Parent = billboard

	local subLabel = Instance.new("TextLabel")
	subLabel.Name = "SubLabel"
	subLabel.Size = UDim2.new(1, 0, 0, 14)
	subLabel.Position = UDim2.new(0, 0, 0, 18)
	subLabel.BackgroundTransparency = 1
	subLabel.FontFace = Theme.Font.Body
	subLabel.TextSize = 13
	subLabel.TextColor3 = Theme.Semantic.TextSecondary
	subLabel.TextStrokeTransparency = 0.5
	subLabel.Text = ""
	subLabel.Parent = billboard

	-- Solo se muestra cuando es un aliado de party (ver refreshPartyState);
	-- ahí reemplaza al segundo BillboardGui que antes creaba PartyMarkerUI.
	local distanceLabel = Instance.new("TextLabel")
	distanceLabel.Name = "DistanceLabel"
	distanceLabel.Size = UDim2.new(1, 0, 0, 14)
	distanceLabel.Position = UDim2.new(0, 0, 0, 32)
	distanceLabel.BackgroundTransparency = 1
	distanceLabel.FontFace = Theme.Font.Body
	distanceLabel.TextSize = 12
	distanceLabel.TextColor3 = Theme.Color.Gold400
	distanceLabel.TextStrokeTransparency = 0.5
	distanceLabel.Text = ""
	distanceLabel.Visible = false
	distanceLabel.Parent = billboard

	return nameLabel, subLabel, distanceLabel, billboard
end

local function refreshSub(subLabel, player)
	local classDef = Classes.get(player:GetAttribute("Class"))
	local level = player:GetAttribute("Level") or 1
	subLabel.Text = string.format("%s — Lv.%d", classDef.name, level)
end

local function watchCharacter(player, character, entries)
	local head = character:WaitForChild("Head", 5)
	local humanoid = character:WaitForChild("Humanoid", 5)
	if not (head and humanoid) then
		return
	end

	-- Apaga el nameplate/health bar default de Roblox: el nuestro lo
	-- reemplaza por completo, así no quedan dos nombres pisándose.
	humanoid.NameDisplayDistance = 0
	humanoid.HealthDisplayType = Enum.HumanoidHealthDisplayType.AlwaysOff

	local nameLabel, subLabel, distanceLabel, billboard = buildTag(head, player)
	refreshSub(subLabel, player)

	local classConn = player:GetAttributeChangedSignal("Class"):Connect(function()
		refreshSub(subLabel, player)
	end)
	local levelConn = player:GetAttributeChangedSignal("Level"):Connect(function()
		refreshSub(subLabel, player)
	end)
	-- Si el jugador entra/sale de un gremio (o le cambian el tag), el
	-- nameplate se actualiza al toque sin esperar a que respawnee.
	local guildTagConn = player:GetAttributeChangedSignal("GuildTag"):Connect(function()
		nameLabel.Text = buildNameText(player)
	end)

	entries[player.UserId] = {
		player = player,
		billboard = billboard,
		distanceLabel = distanceLabel,
	}

	-- Estas conexiones son por-personaje: se cierran solas al morir/
	-- respawnear porque el Head viejo (y por lo tanto el billboard) se
	-- destruye junto con el resto del character.
	head.AncestryChanged:Connect(function(_, parent)
		if not parent then
			classConn:Disconnect()
			levelConn:Disconnect()
			guildTagConn:Disconnect()
			if entries[player.UserId] and entries[player.UserId].billboard == billboard then
				entries[player.UserId] = nil
			end
		end
	end)
end

local function watchPlayer(player, entries)
	if player.Character then
		task.spawn(watchCharacter, player, player.Character, entries)
	end
	player.CharacterAdded:Connect(function(character)
		watchCharacter(player, character, entries)
	end)
end

function PlayerNameplateUI.start()
	local entries = {} -- [userId] = { player, billboard, distanceLabel }

	for _, player in ipairs(Players:GetPlayers()) do
		watchPlayer(player, entries)
	end
	Players.PlayerAdded:Connect(function(player)
		watchPlayer(player, entries)
	end)
	Players.PlayerRemoving:Connect(function(player)
		entries[player.UserId] = nil
	end)

	-- Un solo loop central que decide, para cada nameplate activo, si el
	-- dueño es aliado de party (distancia ilimitada + label de distancia)
	-- o no (rango corto, sin distancia) — reemplaza el segundo billboard
	-- que antes ponía PartyMarkerUI encima del nameplate.
	local accumulator = 0
	RunService.Heartbeat:Connect(function(dt)
		accumulator += dt
		if accumulator < REFRESH_INTERVAL then
			return
		end
		accumulator = 0

		local myRoot = localPlayer.Character and localPlayer.Character:FindFirstChild("HumanoidRootPart")

		for userId, entry in pairs(entries) do
			local ally = isPartyAlly(entry.player)

			if ally then
				entry.billboard.MaxDistance = 0 -- 0 = sin límite
				local theirRoot = entry.player.Character and entry.player.Character:FindFirstChild("HumanoidRootPart")
				if myRoot and theirRoot then
					local studs = (theirRoot.Position - myRoot.Position).Magnitude
					entry.distanceLabel.Text = math.floor(studs + 0.5) .. "m"
					entry.distanceLabel.Visible = true
				else
					entry.distanceLabel.Visible = false
				end
			else
				entry.billboard.MaxDistance = NON_PARTY_VIEW_DISTANCE
				entry.distanceLabel.Visible = false
			end
		end
	end)
end

return PlayerNameplateUI