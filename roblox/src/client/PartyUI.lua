-- panel de party, con la lista de miembros y la sección pa invitar a otros
-- el lider de party tiene un [L] de lider al lado de su nombre, y puede kickear a los demás miembros, o invitarlos si la party está cerrada
-- las invitaciones se envían por remotes, y se muestran en un popup pa aceptar o rechazar con un timeout de 10 segundos
-- el panel se puede abrir y cerrar con un botón en la esquina superior izquierda, o con la tecla O

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ContextActionService = game:GetService("ContextActionService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Remotes = require(Shared:WaitForChild("Remotes"))
local Config = require(Shared:WaitForChild("Config"))
local Sfx = require(script.Parent.Sfx)

local player = Players.LocalPlayer

local PartyUI = {}

local COLORS = {
	panel = Color3.fromRGB(25, 25, 28),
	section = Color3.fromRGB(33, 33, 38),
	line = Color3.fromRGB(48, 48, 55),
	good = Color3.fromRGB(80, 180, 90),
	mana = Color3.fromRGB(70, 130, 220),
	bad = Color3.fromRGB(200, 70, 60),
	text = Color3.fromRGB(235, 235, 240),
	textDim = Color3.fromRGB(150, 150, 160),
	gold = Color3.fromRGB(255, 220, 120),
}

local MAX_SIZE = Config.Party.maxSize

local function makeLabel(parent, text, size, color)
	local label = Instance.new("TextLabel")
	label.BackgroundTransparency = 1
	label.Font = Enum.Font.GothamBold
	label.TextSize = size
	label.TextColor3 = color or COLORS.text
	label.Text = text
	label.TextXAlignment = Enum.TextXAlignment.Left
	label.Parent = parent
	return label
end

local function makeButton(parent, text, bg, size)
	local btn = Instance.new("TextButton")
	btn.BackgroundColor3 = bg
	btn.AutoButtonColor = true
	btn.Font = Enum.Font.GothamBold
	btn.TextSize = size or 13
	btn.TextColor3 = Color3.new(1, 1, 1)
	btn.Text = text
	btn.Parent = parent
	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0, 6)
	corner.Parent = btn
	return btn
end

local function makeBar(parent, position, size, fillColor)
	local back = Instance.new("Frame")
	back.BackgroundColor3 = Color3.fromRGB(15, 15, 18)
	back.BorderSizePixel = 0
	back.Position = position
	back.Size = size
	back.Parent = parent
	local backCorner = Instance.new("UICorner")
	backCorner.CornerRadius = UDim.new(0, 4)
	backCorner.Parent = back

	local fill = Instance.new("Frame")
	fill.BackgroundColor3 = fillColor
	fill.BorderSizePixel = 0
	fill.Size = UDim2.new(1, 0, 1, 0)
	fill.Parent = back
	local fillCorner = Instance.new("UICorner")
	fillCorner.CornerRadius = UDim.new(0, 4)
	fillCorner.Parent = fill

	return function(current, max)
		local ratio = max > 0 and math.clamp(current / max, 0, 1) or 0
		fill.Size = UDim2.new(ratio, 0, 1, 0)
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
	gui.DisplayOrder = 200
	gui.Parent = player:WaitForChild("PlayerGui")

	-- ---- botón de la interfaz
	local toggleBtn = makeButton(gui, "Party", Color3.fromRGB(60, 90, 160), 14)
	toggleBtn.Size = UDim2.new(0, 90, 0, 34)
	toggleBtn.Position = UDim2.new(0, 16, 0, 68)

	-- ---- panel principallll
	local panel = Instance.new("Frame")
	panel.BackgroundColor3 = COLORS.panel
	panel.BorderSizePixel = 0
	panel.Size = UDim2.new(0, 320, 0, 420)
	panel.Position = UDim2.new(0.5, -160, 0.5, -210)
	panel.Visible = false
	panel.Parent = gui
	local panelCorner = Instance.new("UICorner")
	panelCorner.CornerRadius = UDim.new(0, 10)
	panelCorner.Parent = panel

	local header = Instance.new("Frame")
	header.BackgroundTransparency = 1
	header.Size = UDim2.new(1, -20, 0, 40)
	header.Position = UDim2.new(0, 10, 0, 6)
	header.Parent = panel

	local title = makeLabel(header, "Party", 20, COLORS.text)
	title.Size = UDim2.new(0, 140, 1, 0)

	local closeBtn = makeButton(header, "X", COLORS.bad, 13)
	closeBtn.Size = UDim2.new(0, 26, 0, 26)
	closeBtn.Position = UDim2.new(1, -26, 0.5, -13)

	local openToggleBtn = makeButton(header, "Open", Color3.fromRGB(70, 130, 90), 12)
	openToggleBtn.Size = UDim2.new(0, 64, 0, 24)
	openToggleBtn.Position = UDim2.new(1, -100, 0.5, -12)
	openToggleBtn.Visible = false -- only shown to the leader

	local leaveBtn = makeButton(panel, "Leave Party", COLORS.bad, 13)
	leaveBtn.Size = UDim2.new(1, -20, 0, 30)
	leaveBtn.Position = UDim2.new(0, 10, 1, -40)
	leaveBtn.Visible = false

	-- ---- esta es la sección de miembros de party
	local membersLabel = makeLabel(panel, "Members", 13, COLORS.textDim)
	membersLabel.Position = UDim2.new(0, 10, 0, 48)
	membersLabel.Size = UDim2.new(1, -20, 0, 16)

	local membersList = Instance.new("Frame")
	membersList.BackgroundColor3 = COLORS.section
	membersList.BorderSizePixel = 0
	membersList.Size = UDim2.new(1, -20, 0, 150)
	membersList.Position = UDim2.new(0, 10, 0, 66)
	membersList.Parent = panel
	local membersCorner = Instance.new("UICorner")
	membersCorner.CornerRadius = UDim.new(0, 8)
	membersCorner.Parent = membersList
	local membersLayout = Instance.new("UIListLayout")
	membersLayout.Padding = UDim.new(0, 4)
	membersLayout.SortOrder = Enum.SortOrder.LayoutOrder
	membersLayout.Parent = membersList
	local membersPad = Instance.new("UIPadding")
	membersPad.PaddingTop = UDim.new(0, 6)
	membersPad.PaddingLeft = UDim.new(0, 6)
	membersPad.PaddingRight = UDim.new(0, 6)
	membersPad.Parent = membersList

	-- ---- sección pa invitar
	local inviteLabel = makeLabel(panel, "Invite a player", 13, COLORS.textDim)
	inviteLabel.Position = UDim2.new(0, 10, 0, 226)
	inviteLabel.Size = UDim2.new(1, -20, 0, 16)

	local inviteScroll = Instance.new("ScrollingFrame")
	inviteScroll.BackgroundColor3 = COLORS.section
	inviteScroll.BorderSizePixel = 0
	inviteScroll.Size = UDim2.new(1, -20, 0, 130)
	inviteScroll.Position = UDim2.new(0, 10, 0, 244)
	inviteScroll.ScrollBarThickness = 4
	inviteScroll.CanvasSize = UDim2.new(0, 0, 0, 0)
	inviteScroll.AutomaticCanvasSize = Enum.AutomaticSize.Y
	inviteScroll.Parent = panel
	local inviteCorner = Instance.new("UICorner")
	inviteCorner.CornerRadius = UDim.new(0, 8)
	inviteCorner.Parent = inviteScroll
	local inviteLayout = Instance.new("UIListLayout")
	inviteLayout.Padding = UDim.new(0, 4)
	inviteLayout.SortOrder = Enum.SortOrder.LayoutOrder
	inviteLayout.Parent = inviteScroll
	local invitePad = Instance.new("UIPadding")
	invitePad.PaddingTop = UDim.new(0, 6)
	invitePad.PaddingLeft = UDim.new(0, 6)
	invitePad.PaddingRight = UDim.new(0, 6)
	invitePad.Parent = inviteScroll

	-- ---- popup de invitación
	local invitePopup = Instance.new("Frame")
	invitePopup.BackgroundColor3 = COLORS.panel
	invitePopup.BorderSizePixel = 0
	invitePopup.Size = UDim2.new(0, 300, 0, 90)
	invitePopup.Position = UDim2.new(0.5, -150, 0, 90)
	invitePopup.Visible = false
	invitePopup.Parent = gui
	local popupCorner = Instance.new("UICorner")
	popupCorner.CornerRadius = UDim.new(0, 10)
	popupCorner.Parent = invitePopup

	local popupText = makeLabel(invitePopup, "", 14, COLORS.text)
	popupText.Size = UDim2.new(1, -20, 0, 36)
	popupText.Position = UDim2.new(0, 10, 0, 8)
	popupText.TextWrapped = true

	local acceptBtn = makeButton(invitePopup, "Accept", COLORS.good, 13)
	acceptBtn.Size = UDim2.new(0.45, -15, 0, 30)
	acceptBtn.Position = UDim2.new(0, 10, 1, -40)

	local declineBtn = makeButton(invitePopup, "Decline", COLORS.bad, 13)
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

	acceptBtn.MouseButton1Click:Connect(function()
		if currentInvite then
			partyRespond:FireServer({ fromUserId = currentInvite.fromUserId, accept = true })
			hideInvitePopup()
		end
	end)
	declineBtn.MouseButton1Click:Connect(function()
		if currentInvite then
			partyRespond:FireServer({ fromUserId = currentInvite.fromUserId, accept = false })
			hideInvitePopup()
		end
	end)

	-- ---- estas son las filas de miembros de party
	local function buildMemberRow(memberPlayer)
		local row = Instance.new("Frame")
		row.BackgroundColor3 = COLORS.line
		row.BorderSizePixel = 0
		row.Size = UDim2.new(1, 0, 0, 42)
		row.Parent = membersList
		local rowCorner = Instance.new("UICorner")
		rowCorner.CornerRadius = UDim.new(0, 6)
		rowCorner.Parent = row

		local nameLabel = makeLabel(row, memberPlayer.Name, 13, COLORS.text)
		nameLabel.Size = UDim2.new(0.5, -6, 0, 16)
		nameLabel.Position = UDim2.new(0, 8, 0, 3)

		local levelLabel = makeLabel(row, "", 11, COLORS.gold)
		levelLabel.Size = UDim2.new(0.4, 0, 0, 14)
		levelLabel.Position = UDim2.new(0.5, 0, 0, 4)
		levelLabel.TextXAlignment = Enum.TextXAlignment.Right

		local setHp = makeBar(row, UDim2.new(0, 8, 0, 22), UDim2.new(0.46, -12, 0, 6), COLORS.good)
		local setMana = makeBar(row, UDim2.new(0.5, 4, 0, 22), UDim2.new(0.46, -12, 0, 6), COLORS.mana)

		local kickBtn = makeButton(row, "Kick", COLORS.bad, 11)
		kickBtn.Size = UDim2.new(0, 42, 0, 20)
		kickBtn.Position = UDim2.new(1, -48, 0, 3)
		kickBtn.Visible = false
		kickBtn.MouseButton1Click:Connect(function()
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
			kickBtn.Visible = canKick and memberPlayer ~= player
		end
	end

	local function buildInviteRow(candidate)
		local row = Instance.new("Frame")
		row.BackgroundColor3 = COLORS.line
		row.BorderSizePixel = 0
		row.Size = UDim2.new(1, 0, 0, 32)
		row.Parent = inviteScroll
		local rowCorner = Instance.new("UICorner")
		rowCorner.CornerRadius = UDim.new(0, 6)
		rowCorner.Parent = row

		local nameLabel = makeLabel(row, candidate.Name, 13, COLORS.text)
		nameLabel.Size = UDim2.new(0.6, 0, 1, 0)
		nameLabel.Position = UDim2.new(0, 8, 0, 0)

		local inviteBtn = makeButton(row, "Invite", Color3.fromRGB(60, 120, 90), 12)
		inviteBtn.Size = UDim2.new(0, 64, 0, 24)
		inviteBtn.Position = UDim2.new(1, -70, 0.5, -12)
		inviteBtn.MouseButton1Click:Connect(function()
			partyInvite:FireServer(candidate.UserId)
		end)

		return row
	end

	-- ---- reconstruye todo el panel con atributos de la party, tipo las clases, niveles, hp etc
	local memberRowConnections = {}

	local function clearChildren(parent)
		for _, child in ipairs(parent:GetChildren()) do
			if not child:IsA("UIListLayout") and not child:IsA("UIPadding") then
				child:Destroy()
			end
		end
	end

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

		toggleBtn.Text = inParty and ("Party (" .. memberCount .. ")") or "Party"
		leaveBtn.Visible = inParty
		openToggleBtn.Visible = inParty and iAmLeader
		if inParty then
			local canInviteMore = memberCount < MAX_SIZE
			inviteLabel.Visible = canInviteMore
			inviteScroll.Visible = canInviteMore
			openToggleBtn.Text = partyOpen and "Open" or "Closed"
			openToggleBtn.BackgroundColor3 = partyOpen and Color3.fromRGB(70, 130, 90) or Color3.fromRGB(150, 90, 60)
		else
			inviteLabel.Visible = true
			inviteScroll.Visible = true
		end
	end

	local function setPanelOpen(open)
		panel.Visible = open
		Sfx.play(open and "panelOpen" or "panelClose")
		if open then
			refresh()
		end
	end

	toggleBtn.MouseButton1Click:Connect(function()
		setPanelOpen(not panel.Visible)
	end)
	closeBtn.MouseButton1Click:Connect(function()
		setPanelOpen(false)
	end)
	leaveBtn.MouseButton1Click:Connect(function()
		partyLeave:FireServer()
	end)
	openToggleBtn.MouseButton1Click:Connect(function()
		local currentlyOpen = player:GetAttribute("PartyOpen")
		partySetOpen:FireServer(not currentlyOpen)
	end)

	ContextActionService:BindAction("TogglePartyPanel", function(_, inputState)
		if inputState == Enum.UserInputState.Begin then
			setPanelOpen(not panel.Visible)
		end
		return Enum.ContextActionResult.Pass
	end, false, Enum.KeyCode.O)

	-- Rebuild whenever anyone's party attributes change, or the roster
	-- changes (join/leave), but only while the panel is actually open (this
	-- also keeps the HUD button's "(n)" count fresh even when closed, since
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
