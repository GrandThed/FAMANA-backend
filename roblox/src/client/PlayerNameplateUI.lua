-- Nametag propio arriba de la cabeza de CADA jugador (local y remotos):
-- nombre + "Clase — Lv.X", en vez del nameplate default de Roblox. Mismo
-- patrón de BillboardGui que el NameTag de los enemigos (server/EnemyService
-- + client/EnemyLevelUI), pero acá vive todo del lado del cliente porque
-- Class/Level ya son atributos replicados del Player (ver PlayerService /
-- ClassService — los mismos que lee CharacterUI).

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Classes = require(Shared:WaitForChild("Classes"))
local Theme = require(script.Parent.Theme)

local PlayerNameplateUI = {}

local function buildTag(head, player)
	local existing = head:FindFirstChild("Nameplate")
	if existing then
		existing:Destroy()
	end

	local billboard = Instance.new("BillboardGui")
	billboard.Name = "Nameplate"
	billboard.Size = UDim2.new(0, 160, 0, 34)
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
	nameLabel.Text = player.DisplayName
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

	return subLabel
end

local function refreshSub(subLabel, player)
	local classDef = Classes.get(player:GetAttribute("Class"))
	local level = player:GetAttribute("Level") or 1
	subLabel.Text = string.format("%s — Lv.%d", classDef.name, level)
end

local function watchCharacter(player, character)
	local head = character:WaitForChild("Head", 5)
	local humanoid = character:WaitForChild("Humanoid", 5)
	if not (head and humanoid) then
		return
	end

	-- Apaga el nameplate/health bar default de Roblox: el nuestro lo
	-- reemplaza por completo, así no quedan dos nombres pisándose.
	humanoid.NameDisplayDistance = 0
	humanoid.HealthDisplayType = Enum.HumanoidHealthDisplayType.AlwaysOff

	local subLabel = buildTag(head, player)
	refreshSub(subLabel, player)

	local classConn = player:GetAttributeChangedSignal("Class"):Connect(function()
		refreshSub(subLabel, player)
	end)
	local levelConn = player:GetAttributeChangedSignal("Level"):Connect(function()
		refreshSub(subLabel, player)
	end)

	-- Estas conexiones son por-personaje: se cierran solas al morir/
	-- respawnear porque el Head viejo (y por lo tanto el billboard) se
	-- destruye junto con el resto del character.
	head.AncestryChanged:Connect(function(_, parent)
		if not parent then
			classConn:Disconnect()
			levelConn:Disconnect()
		end
	end)
end

local function watchPlayer(player)
	if player.Character then
		task.spawn(watchCharacter, player, player.Character)
	end
	player.CharacterAdded:Connect(function(character)
		watchCharacter(player, character)
	end)
end

function PlayerNameplateUI.start()
	for _, player in ipairs(Players:GetPlayers()) do
		watchPlayer(player)
	end
	Players.PlayerAdded:Connect(watchPlayer)
end

return PlayerNameplateUI
