-- Panel de party (botón "Party (O)" del stack de arriba a la derecha, o la
-- tecla O), con la lista de miembros y la sección pa invitar a otros. El
-- lider de party tiene un [L] al lado de su nombre, y puede kickear a los
-- demás miembros, o invitarlos si la party está cerrada. Las invitaciones
-- se envían por remotes, y se muestran en un popup pa aceptar o rechazar
-- con un timeout de 10 segundos.
--
-- Mismo look que GuildUI (Theme/UIKit — panel Aethelgard, tipografía serif,
-- cantos rectos salvo el botón de cerrar): antes tenía su propia paleta
-- gris plana y esquinas redondeadas, y quedaba visualmente desconectado
-- del resto de las ventanas del juego.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ContextActionService = game:GetService("ContextActionService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Remotes = require(Shared:WaitForChild("Remotes"))
local Config = require(Shared:WaitForChild("Config"))
local Theme = require(script.Parent.Theme)
local TopRightMenu = require(script.Parent.TopRightMenu)
local UIKit = require(script.Parent.UIKit)
local Sfx = require(script.Parent.Sfx)

local player = Players.LocalPlayer

local PartyUI = {}

local COLORS = {
	section = Theme.Semantic.SurfaceWell,
	line = Theme.Semantic.BorderHair,
	tile = Theme.Color.Ink900,
	accent = Theme.Color.Ember300,
	good = Theme.Semantic.Good,
	bad = Theme.Semantic.Bad,
	mana = Theme.Color.Mana400,
	text = Theme.Semantic.TextBody,
	textDim = Theme.Semantic.TextMuted,
	gold = Theme.Color.Gold400,
}

local MAX_SIZE = Config.Party.maxSize
local PANEL_W = 340
local PANEL_H = 420

local function makeLabel(parent, text, size, color, font)
	local label = Instance.new("TextLabel")
	label.BackgroundTransparency = 1
	label.FontFace = font or Theme.Font.Body
	label.TextSize = size
	label.TextColor3 = color or COLORS.text
	label.TextWrapped = true
	label.TextXAlignment = Enum.TextXAlignment.Left
	label.Text = text
	label.Parent = parent
	return label
end

local function makeScrollList(parent, size, position)
	local scroll = Instance.new("ScrollingFrame")
	scroll.Size = size
	scroll.Position = position
	scroll.BackgroundColor3 = COLORS.section
	scroll.BorderSizePixel = 0
	scroll.ScrollBarThickness = 6
	scroll.AutomaticCanvasSize = Enum.AutomaticSize.Y
	scroll.CanvasSize = UDim2.new(0, 0, 0, 0)
	scroll.Parent = parent

	local stroke = Instance.new("UIStroke")
	stroke.Thickness = 1
	stroke.Color = COLORS.line
	stroke.Parent = scroll

	local layout = Instance.new("UIListLayout")
	layout.SortOrder = Enum.SortOrder.LayoutOrder
	layout.Padding = UDim.new(0, 4)
	layout.Parent = scroll

	local pad = Instance.new("UIPadding")
	pad.PaddingTop = UDim.new(0, 6)
	pad.PaddingLeft = UDim.new(0, 6)
	pad.PaddingRight = UDim.new(0, 6)
	pad.PaddingBottom = UDim.new(0, 6)
	pad.Parent = scroll

	return scroll
end

-- Tira una barra rellena (HP/Mana) al estilo de los tiles del roster.
-- Devuelve un setter(current, max) para actualizarla.
local function makeBar(parent, position, size, fillColor)
	local back = Instance.new("Frame")
	back.BackgroundColor3 = Theme.Color.Ink900
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

-- Recolorea un ghostButton para acciones "buenas" (Invitar) o "malas"
-- (Kickear, Salir) sin perder su forma/tipografía — mismo truco que usa
-- InventoryUI para el "Soltar" del menú contextual.
local function tintButton(button, color, strokeColor)
	button.TextColor3 = color
	local stroke = button:FindFirstChildOfClass("UIStroke")
	if stroke then
		stroke.Color = strokeColor or color
	end
end

local function clearChildren(parent)
	for _, child in ipairs(parent:GetChildren()) do
		if not child:IsA("UIListLayout") and not child:IsA("UIPadding") then
			child:Destroy()
		end
	end
end

function PartyUI.start()
	local partyInvite = Remotes.get("PartyInvite")
	local partyInviteReceived = Remotes.get("PartyInviteReceived")
	local partyRespond = Remotes.get("PartyRespond")
	local partyLeave = Remotes.get("PartyLeave")
	local partyKick = Remotes.get("PartyKick")
	local partySetOpen = Remotes.get("PartySetOpen")

	local gui = Instance.new("ScreenGui")
	gui.Name = "PartyUI"
	gui.ResetOnSpawn = false
	gui.DisplayOrder = 5
	gui.Parent = player:WaitForChild("PlayerGui")

	-- ---- panel principal ----------------------------------------------------
	local panel = Instance.new("Frame")
	panel.Size = UDim2.new(0, PANEL_W, 0, PANEL_H)
	panel.Position = UDim2.new(0.5, 0, 0.5, 0)
	panel.AnchorPoint = Vector2.new(0.5, 0.5)
	panel.Visible = false
	panel.Parent = gui
	UIKit.stylePanel(panel)
	UIKit.addShadow(panel)
	UIKit.autoScale(panel)

	local title = makeLabel(panel, "Party", Theme.Text.Title, Theme.Semantic.TextTitle, Theme.Font.DisplayBold)
	title.Size = UDim2.new(1, -126, 0, 30)
	title.Position = UDim2.new(0, 12, 0, 4)

	local closeBtn = UIKit.closeButton(panel)
	closeBtn.Position = UDim2.new(1, -6, 0, 6)
	closeBtn.AnchorPoint = Vector2.new(1, 0)

	local openToggleBtn = UIKit.ghostButton(panel, "Open")
	openToggleBtn.Size = UDim2.new(0, 66, 0, 24)
	openToggleBtn.Position = UDim2.new(1, -108, 0, 8)
	openToggleBtn.Visible = false -- only shown to the leader

	local leaveBtn = UIKit.ghostButton(panel, "Leave Party")
	leaveBtn.Size = UDim2.new(1, -24, 0, 30)
	leaveBtn.Position = UDim2.new(0, 12, 1, -42)
	leaveBtn.Visible = false
	tintButton(leaveBtn, COLORS.bad, Theme.Color.Blood500)

	-- ---- esta es la sección de miembros de party
	local membersLabel = makeLabel(panel, "Members", Theme.Text.Sm, COLORS.textDim)
	membersLabel.Size = UDim2.new(1, -24, 0, 16)
	membersLabel.Position = UDim2.new(0, 12, 0, 44)

	local membersList = makeScrollList(panel, UDim2.new(1, -24, 0, 150), UDim2.new(0, 12, 0, 62))

	-- ---- sección pa invitar
	local inviteLabel = makeLabel(panel, "Invite a player", Theme.Text.Sm, COLORS.textDim)
	inviteLabel.Size = UDim2.new(1, -24, 0, 16)
	inviteLabel.Position = UDim2.new(0, 12, 0, 222)

	local inviteScroll = makeScrollList(panel, UDim2.new(1, -24, 0, 110), UDim2.new(0, 12, 0, 240))

	-- ---- popup de invitación (mismo patrón que GuildUI)
	local invitePopup = Instance.new("Frame")
	invitePopup.Size = UDim2.new(0, 320, 0, 96)
	invitePopup.Position = UDim2.new(0.5, -160, 0, 90)
	invitePopup.Visible = false
	invitePopup.Parent = gui
	UIKit.stylePanel(invitePopup)
	UIKit.addShadow(invitePopup)

	local popupText = makeLabel(invitePopup, "", Theme.Text.Lg, COLORS.text)
	popupText.Size = UDim2.new(1, -20, 0, 40)
	popupText.Position = UDim2.new(0, 10, 0, 8)

	local acceptBtn = UIKit.primaryButton(invitePopup, "Accept")
	acceptBtn.Size = UDim2.new(0.45, -15, 0, 30)
	acceptBtn.Position = UDim2.new(0, 10, 1, -40)

	local declineBtn = UIKit.ghostButton(invitePopup, "Decline")
	declineBtn.Size = UDim2.new(0.45, -15, 0, 30)
	declineBtn.Position = UDim2.new(0.55, 5, 1, -40)

	local currentInvite -- { fromUserId } or nil
	local currentInviteToken = 0

	local function hideInvitePopup()
		invitePopup.Visible = false
		currentInvite = nil
	end

	partyInviteReceived.OnClientEvent:Connect(function(payload)
		if typeof(payload) ~= "table" or typeof(payload.fromUserId) ~= "number" then
			return
		end
		currentInvite = { fromUserId = payload.fromUserId }
		currentInviteToken += 1
		local token = currentInviteToken
		popupText.Text = tostring(payload.fromName or "Someone") .. " invited you to their party."
		invitePopup.Visible = true
		local timeout = tonumber(payload.timeout) or Config.Party.inviteTimeout
		task.delay(timeout, function()
			if currentInviteToken == token then
				hideInvitePopup()
			end
		end)
	end)

	acceptBtn.Activated:Connect(function()
		if currentInvite then
			partyRespond:FireServer({ fromUserId = currentInvite.fromUserId, accept = true })
			hideInvitePopup()
		end
	end)
	declineBtn.Activated:Connect(function()
		if currentInvite then
			partyRespond:FireServer({ fromUserId = currentInvite.fromUserId, accept = false })
			hideInvitePopup()
		end
	end)

	-- ---- estas son las filas de miembros de party
	local function buildMemberRow(memberPlayer)
		local row = Instance.new("Frame")
		row.BackgroundColor3 = COLORS.tile
		row.BackgroundTransparency = 0.35
		row.BorderSizePixel = 0
		row.Size = UDim2.new(1, 0, 0, 42)
		row.Parent = membersList

		local nameLabel = makeLabel(row, memberPlayer.Name, Theme.Text.Body, COLORS.text, Theme.Font.BodyBold)
		nameLabel.Size = UDim2.new(0.5, -6, 0, 16)
		nameLabel.Position = UDim2.new(0, 8, 0, 4)

		local levelLabel = makeLabel(row, "", Theme.Text.Sm, COLORS.gold)
		levelLabel.Size = UDim2.new(0.4, 0, 0, 14)
		levelLabel.Position = UDim2.new(0.5, 0, 0, 5)
		levelLabel.TextXAlignment = Enum.TextXAlignment.Right

		local setHp = makeBar(row, UDim2.new(0, 8, 0, 23), UDim2.new(0.46, -12, 0, 6), COLORS.good)
		local setMana = makeBar(row, UDim2.new(0.5, 4, 0, 23), UDim2.new(0.46, -12, 0, 6), COLORS.mana)

		local kickBtn = UIKit.ghostButton(row, "Kick")
		kickBtn.Size = UDim2.new(0, 46, 0, 20)
		kickBtn.Position = UDim2.new(1, -52, 0, 4)
		kickBtn.Visible = false
		tintButton(kickBtn, COLORS.bad, Theme.Color.Blood500)
		kickBtn.Activated:Connect(function()
			partyKick:FireServer(memberPlayer.UserId)
		end)

		local connections = {}

		local function refreshLevel()
			levelLabel.Text = "Lv " .. tostring(memberPlayer:GetAttribute("Level") or 1)
		end
		table.insert(connections, memberPlayer:GetAttributeChangedSignal("Level"):Connect(refreshLevel))
		refreshLevel()

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

		return row, connections, function(isLeaderRow, canKick)
			nameLabel.Text = (isLeaderRow and "[L] " or "") .. memberPlayer.Name
			nameLabel.TextColor3 = isLeaderRow and COLORS.accent or COLORS.text
			kickBtn.Visible = canKick and memberPlayer ~= player
		end
	end

	local function buildInviteRow(candidate)
		local row = Instance.new("Frame")
		row.BackgroundColor3 = COLORS.tile
		row.BackgroundTransparency = 0.35
		row.BorderSizePixel = 0
		row.Size = UDim2.new(1, 0, 0, 32)
		row.Parent = inviteScroll

		local nameLabel = makeLabel(row, candidate.Name, Theme.Text.Body, COLORS.text)
		nameLabel.Size = UDim2.new(0.6, 0, 1, 0)
		nameLabel.Position = UDim2.new(0, 8, 0, 0)

		local inviteBtn = UIKit.ghostButton(row, "Invite")
		inviteBtn.Size = UDim2.new(0, 62, 0, 22)
		inviteBtn.Position = UDim2.new(1, -68, 0.5, -11)
		tintButton(inviteBtn, COLORS.good)
		inviteBtn.Activated:Connect(function()
			partyInvite:FireServer(candidate.UserId)
		end)

		return row
	end

	-- ---- reconstruye todo el panel con atributos de la party, tipo las clases, niveles, hp etc
	local memberRowConnections = {}
	local openBtn -- TopRightMenu button; resolved below, referenced by refresh()

	local function refresh()
		for _, conns in ipairs(memberRowConnections) do
			for _, c in ipairs(conns) do
				c:Disconnect()
			end
		end
		memberRowConnections = {}
		clearChildren(membersList)
		clearChildren(inviteScroll)

		local myPartyId = player:GetAttribute("PartyId")
		local iAmLeader = player:GetAttribute("PartyLeader") == true
		local partyOpen = player:GetAttribute("PartyOpen")
		local inParty = myPartyId ~= nil

		local memberCount = 0
		for _, other in ipairs(Players:GetPlayers()) do
			local otherPartyId = other:GetAttribute("PartyId")
			if inParty and otherPartyId == myPartyId then
				-- A fellow party member (or ourselves): show in the roster.
				memberCount += 1
				local isLeaderRow = other:GetAttribute("PartyLeader") == true
				local row, conns, applyState = buildMemberRow(other)
				table.insert(memberRowConnections, conns)
				applyState(isLeaderRow, iAmLeader)
			elseif other ~= player and otherPartyId == nil then
				-- solo gente sin party aparece en lista de invitación
				buildInviteRow(other)
			end
		end

		openBtn.Text = inParty and string.format("Party (O) · %d", memberCount) or "Party (O)"
		leaveBtn.Visible = inParty
		openToggleBtn.Visible = inParty and iAmLeader
		if inParty then
			local canInviteMore = memberCount < MAX_SIZE
			inviteLabel.Visible = canInviteMore
			inviteScroll.Visible = canInviteMore
			openToggleBtn.Text = partyOpen and "Open" or "Closed"
			tintButton(openToggleBtn, partyOpen and COLORS.good or COLORS.bad, partyOpen and COLORS.good or Theme.Color.Blood500)
		else
			inviteLabel.Visible = true
			inviteScroll.Visible = true
		end
	end

	local isOpen = false
	local function setPanelOpen(open)
		isOpen = open
		panel.Visible = open
		Sfx.play(open and "panelOpen" or "panelClose")
		if open then
			refresh()
		end
	end
	local function toggle()
		setPanelOpen(not isOpen)
	end

	openBtn = TopRightMenu.addButton("Party (O)", 6)
	openBtn.Name = "PartyButton"
	openBtn.Activated:Connect(toggle)

	closeBtn.Activated:Connect(function()
		setPanelOpen(false)
	end)
	leaveBtn.Activated:Connect(function()
		partyLeave:FireServer()
	end)
	openToggleBtn.Activated:Connect(function()
		local currentlyOpen = player:GetAttribute("PartyOpen")
		partySetOpen:FireServer(not currentlyOpen)
	end)

	ContextActionService:BindAction("TogglePartyPanel", function(_, inputState)
		if inputState == Enum.UserInputState.Begin then
			toggle()
		end
		return Enum.ContextActionResult.Pass
	end, false, Enum.KeyCode.O)

	-- Rebuild whenever anyone's party attributes change, or the roster
	-- changes (join/leave), but only while the panel is actually open (this
	-- also keeps the HUD button's "· n" count fresh even when closed, since
	-- refresh() is cheap and parties are tiny).
	local function watchPlayer(p)
		p:GetAttributeChangedSignal("PartyId"):Connect(refresh)
		p:GetAttributeChangedSignal("PartyLeader"):Connect(refresh)
		p:GetAttributeChangedSignal("PartyOpen"):Connect(refresh)
	end
	for _, p in ipairs(Players:GetPlayers()) do
		watchPlayer(p)
	end
	Players.PlayerAdded:Connect(function(p)
		watchPlayer(p)
		refresh()
	end)
	Players.PlayerRemoving:Connect(refresh)

	refresh()
end

return PartyUI