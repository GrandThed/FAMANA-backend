-- frames de party que muestran la salud y mana de los miembros del party
-- además de los nombres de cada uno y la clase
-- el botón de "open" o "closed" significa que todos pueden invitar a otros miembros o solo el líder puede hacerlo
-- sigue el sistema de diseño Aethelgard (Theme/UIKit) — mismo tratamiento que
-- la barra de vida de los enemigos y el panel de target: shell de panel,
-- barras con degradé + borde + ghost bar en HP y maná.
-- *importante* la lista de jugadores para invitar solo muestran jugadores disponibles, si ya hay uno en una party no va a aparecer ahí

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Classes = require(Shared:WaitForChild("Classes"))
local Theme = require(script.Parent.Theme)
local UIKit = require(script.Parent.UIKit)

local player = Players.LocalPlayer

local PartyFramesUI = {}

local FRAME_WIDTH = 230
local FRAME_HEIGHT = 64
local FRAME_GAP = 6
local LEFT_MARGIN = 16

local FILL_TWEEN = TweenInfo.new(0.15, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
local GHOST_TWEEN = TweenInfo.new(0.35, Enum.EasingStyle.Quad, Enum.EasingDirection.In)
local GHOST_DELAY = 0.25

-- Themed bar: Ink background, Stone border, a top→bottom gradient fill, and a
-- trailing "ghost" afterimage that lags behind on a drop and eases down a
-- beat later (same trick as the enemy overhead bar / target panel).
-- `zIndex` lets the caller lift the whole bar above the panel's forge-light
-- strip (see UIKit.stylePanel). Returns an updater: update(current, max).
local function makeBar(parent, position, size, topColor, bottomColor, ghostColor, zIndex)
	local back = Instance.new("Frame")
	back.BackgroundColor3 = Theme.Color.Ink900
	back.BorderSizePixel = 0
	back.ClipsDescendants = true
	back.Position = position
	back.Size = size
	back.ZIndex = zIndex
	back.Parent = parent

	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0, 2)
	corner.Parent = back

	local border = Instance.new("UIStroke")
	border.Thickness = 1
	border.Color = Theme.Semantic.BorderPanel
	border.Parent = back

	local ghost = Instance.new("Frame")
	ghost.Name = "Ghost"
	ghost.BackgroundColor3 = ghostColor
	ghost.BorderSizePixel = 0
	ghost.Size = UDim2.new(1, 0, 1, 0)
	ghost.ZIndex = back.ZIndex + 1
	ghost.Parent = back

	local fill = Instance.new("Frame")
	fill.Name = "Fill"
	fill.BackgroundColor3 = topColor
	fill.BorderSizePixel = 0
	fill.Size = UDim2.new(1, 0, 1, 0)
	fill.ZIndex = ghost.ZIndex + 1
	fill.Parent = back

	local gradient = Instance.new("UIGradient")
	gradient.Rotation = 90
	gradient.Color = ColorSequence.new(topColor, bottomColor)
	gradient.Parent = fill

	local lastFrac = 1
	local ghostToken = 0

	return function(current, max)
		local ratio = max > 0 and math.clamp(current / max, 0, 1) or 0
		if math.abs(ratio - lastFrac) < 0.001 then
			return
		end
		lastFrac = ratio
		TweenService:Create(fill, FILL_TWEEN, { Size = UDim2.new(ratio, 0, 1, 0) }):Play()
		ghostToken += 1
		local token = ghostToken
		task.delay(GHOST_DELAY, function()
			if ghostToken ~= token then
				return -- a newer update landed before this catch-down fired
			end
			TweenService:Create(ghost, GHOST_TWEEN, { Size = UDim2.new(ratio, 0, 1, 0) }):Play()
		end)
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
		frame.Size = UDim2.new(1, 0, 0, FRAME_HEIGHT)
		frame.LayoutOrder = layoutOrder
		frame.Parent = container
		UIKit.stylePanel(frame) -- Aethelgard shell: Ink gradient, Stone border, ember forge-light
		local contentZ = frame.ZIndex + 1 -- above the forge-light strip stylePanel adds

		local nameLabel = UIKit.label(frame, memberPlayer.Name, Theme.Text.Sm, Theme.Semantic.TextStrong, Theme.Font.BodyBold)
		nameLabel.TextXAlignment = Enum.TextXAlignment.Left
		nameLabel.TextTruncate = Enum.TextTruncate.AtEnd
		nameLabel.Size = UDim2.new(0.6, -8, 0, 18)
		nameLabel.Position = UDim2.new(0, 8, 0, 6)
		nameLabel.ZIndex = contentZ

		local classLabel = UIKit.label(frame, "", Theme.Text.Xs, Theme.Semantic.TextSecondary, Theme.Font.Body)
		classLabel.TextXAlignment = Enum.TextXAlignment.Right
		classLabel.Size = UDim2.new(0.4, -8, 0, 18)
		classLabel.Position = UDim2.new(0.6, 0, 0, 6)
		classLabel.ZIndex = contentZ

		local setHp = makeBar(frame, UDim2.new(0, 8, 0, 28), UDim2.new(1, -16, 0, 11), Theme.Orb.HpTop, Theme.Orb.HpBottom, Theme.Color.Gold300, contentZ)
		local setMana = makeBar(frame, UDim2.new(0, 8, 0, 45), UDim2.new(1, -16, 0, 11), Theme.Orb.ManaTop, Theme.Orb.ManaBottom, Theme.Color.Steel400, contentZ)

		local connections = {}

		local function refreshClass()
			if memberPlayer:GetAttribute("Downed") then
				classLabel.Text = "Caído"
				classLabel.TextColor3 = Theme.Semantic.Danger
				return
			end
			local def = Classes.get(memberPlayer:GetAttribute("Class"))
			classLabel.TextColor3 = Theme.Semantic.TextSecondary
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