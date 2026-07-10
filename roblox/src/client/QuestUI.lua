-- Panel del NPC de quests. Se abre con el ProximityPrompt (OpenQuestGiver,
-- mismo patrón que StoreUI/OpenStore); las acciones (aceptar/entregar) van
-- por el RemoteFunction QuestAction, que devuelve la lista de quests de ese
-- NPC ya refrescada — no hace falta un segundo viaje al server para
-- re-renderizar. UI a propósito simple: una lista vertical de tarjetas, sin
-- pestañas ni detalle aparte (eso lo dejamos para cuando haya más contenido).

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Remotes = require(Shared:WaitForChild("Remotes"))
local Theme = require(script.Parent.Theme)
local UIKit = require(script.Parent.UIKit)
local ClientState = require(script.Parent.ClientState)
local Sfx = require(script.Parent.Sfx)

local player = Players.LocalPlayer

local QuestUI = {}

local COLORS = {
	section = Theme.Semantic.SurfaceWell,
	line = Theme.Semantic.BorderHair,
	tile = Theme.Color.Ink900,
	good = Theme.Semantic.Good,
	bad = Theme.Semantic.Bad,
	text = Theme.Semantic.TextBody,
	textDim = Theme.Semantic.TextMuted,
}

local ERROR_TEXT = {
	too_far = "Not near the quest giver anymore",
	already_active = "Quest already in progress",
	already_completed = "Already completed",
	level_too_low = "You need a higher level for this",
	not_ready = "Objectives not finished yet",
	unknown_quest = "That quest doesn't exist",
	bad_request = "Something went wrong",
}

local PANEL_W = 480
local PANEL_H = 460
local CLOSE_DISTANCE = 20 -- studs; walk away → the panel closes itself

local function makeLabel(parent, text, size, color, font)
	local label = Instance.new("TextLabel")
	label.BackgroundTransparency = 1
	label.FontFace = font or Theme.Font.Body
	label.TextSize = size
	label.TextColor3 = color or COLORS.text
	label.Text = text
	label.TextXAlignment = Enum.TextXAlignment.Left
	label.TextWrapped = true
	label.Parent = parent
	return label
end

local function rewardText(rewards)
	local parts = {}
	if rewards.xp then
		table.insert(parts, rewards.xp .. " XP")
	end
	if rewards.gold then
		table.insert(parts, rewards.gold .. "g")
	end
	for _, item in ipairs(rewards.items or {}) do
		table.insert(parts, (item.quantity > 1 and (item.quantity .. "x ") or "") .. item.name)
	end
	return #parts > 0 and table.concat(parts, "  •  ") or nil
end

function QuestUI.start()
	local gui = Instance.new("ScreenGui")
	gui.Name = "QuestUI"
	gui.ResetOnSpawn = false
	gui.DisplayOrder = 5
	gui.Parent = player:WaitForChild("PlayerGui")

	local panel = Instance.new("Frame")
	panel.Size = UDim2.new(0, PANEL_W, 0, PANEL_H)
	panel.Position = UDim2.new(0.5, 0, 0.5, 0)
	panel.AnchorPoint = Vector2.new(0.5, 0.5)
	panel.Visible = false
	panel.Parent = gui
	UIKit.stylePanel(panel)
	UIKit.addShadow(panel)
	UIKit.autoScale(panel)

	local title = UIKit.titleBar(panel, "", 36)
	local closeBtn = UIKit.closeButton(panel)
	closeBtn.Position = UDim2.new(1, -6, 0, 6)
	closeBtn.AnchorPoint = Vector2.new(1, 0)

	local statusLabel = makeLabel(panel, "", 12, COLORS.bad)
	statusLabel.Size = UDim2.new(1, -24, 0, 18)
	statusLabel.Position = UDim2.new(0, 12, 1, -26)

	local list = Instance.new("ScrollingFrame")
	list.Size = UDim2.new(1, -24, 1, -(44 + 34))
	list.Position = UDim2.new(0, 12, 0, 44)
	list.BackgroundColor3 = COLORS.section
	list.BorderSizePixel = 0
	list.ScrollBarThickness = 6
	list.AutomaticCanvasSize = Enum.AutomaticSize.Y
	list.CanvasSize = UDim2.new(0, 0, 0, 0)
	list.Parent = panel

	local listStroke = Instance.new("UIStroke")
	listStroke.Thickness = 1
	listStroke.Color = COLORS.line
	listStroke.Parent = list

	local layout = Instance.new("UIListLayout")
	layout.SortOrder = Enum.SortOrder.LayoutOrder
	layout.Padding = UDim.new(0, 8)
	layout.Parent = list

	local listPadding = Instance.new("UIPadding")
	listPadding.PaddingTop = UDim.new(0, 8)
	listPadding.PaddingLeft = UDim.new(0, 8)
	listPadding.PaddingRight = UDim.new(0, 8)
	listPadding.PaddingBottom = UDim.new(0, 8)
	listPadding.Parent = list

	-- ---- state --------------------------------------------------------------
	local isOpen = false
	local busy = false
	local current = nil -- { giverId, giverName, position, quests }

	local questAction = Remotes.getFunction("QuestAction")

	local render -- forward declaration

	local function doAction(questId, verb)
		if busy then
			return
		end
		busy = true
		statusLabel.Text = ""
		local result = questAction:InvokeServer({ giverId = current.giverId, questId = questId, verb = verb })
		busy = false
		if typeof(result) ~= "table" then
			statusLabel.Text = ERROR_TEXT.bad_request
			return
		end
		if not result.ok then
			statusLabel.Text = ERROR_TEXT[result.error] or ERROR_TEXT.bad_request
		else
			Sfx.play(verb == "complete" and "levelUp" or "uiClick")
		end
		if result.quests then
			current.quests = result.quests
			render()
		end
	end

	local function makeCard(order, quest)
		local card = Instance.new("Frame")
		card.Size = UDim2.new(1, 0, 0, 0)
		card.AutomaticSize = Enum.AutomaticSize.Y
		card.BackgroundColor3 = COLORS.tile
		card.BackgroundTransparency = 0.35
		card.BorderSizePixel = 0
		card.LayoutOrder = order
		card.Parent = list

		local cardStroke = Instance.new("UIStroke")
		cardStroke.Thickness = 1
		cardStroke.Color = quest.status == "completed" and COLORS.good or COLORS.line
		cardStroke.Parent = card

		local cardPadding = Instance.new("UIPadding")
		cardPadding.PaddingTop = UDim.new(0, 8)
		cardPadding.PaddingLeft = UDim.new(0, 10)
		cardPadding.PaddingRight = UDim.new(0, 10)
		cardPadding.PaddingBottom = UDim.new(0, 8)
		cardPadding.Parent = card

		local cardLayout = Instance.new("UIListLayout")
		cardLayout.SortOrder = Enum.SortOrder.LayoutOrder
		cardLayout.Padding = UDim.new(0, 3)
		cardLayout.Parent = card

		local nameRow = Instance.new("Frame")
		nameRow.Size = UDim2.new(1, 0, 0, 20)
		nameRow.BackgroundTransparency = 1
		nameRow.LayoutOrder = 1
		nameRow.Parent = card

		local nameLabel = makeLabel(nameRow, quest.name, 15, COLORS.text, Theme.Font.DisplayBold)
		nameLabel.Size = UDim2.new(1, -70, 1, 0)

		local statusTag = makeLabel(
			nameRow,
			quest.status == "completed" and "DONE" or quest.status == "active" and "ACTIVE" or "NEW",
			11,
			quest.status == "completed" and COLORS.good or COLORS.textDim,
			Theme.Font.BodyBold
		)
		statusTag.Size = UDim2.new(0, 60, 1, 0)
		statusTag.Position = UDim2.new(1, -60, 0, 0)
		statusTag.TextXAlignment = Enum.TextXAlignment.Right

		local desc = makeLabel(card, quest.description, 12, COLORS.textDim)
		desc.Size = UDim2.new(1, 0, 0, 0)
		desc.AutomaticSize = Enum.AutomaticSize.Y
		desc.LayoutOrder = 2

		for i, objective in ipairs(quest.objectives) do
			local met = objective.current >= objective.amount
			local objLabel = makeLabel(
				card,
				string.format("%s  %d/%d", objective.label, objective.current, objective.amount),
				12,
				met and COLORS.good or COLORS.text
			)
			objLabel.Size = UDim2.new(1, 0, 0, 16)
			objLabel.LayoutOrder = 2 + i
		end

		local rewards = rewardText(quest.rewards)
		if rewards then
			local rewardLabel = makeLabel(card, "Reward: " .. rewards, 11, Theme.Color.Ember500)
			rewardLabel.Size = UDim2.new(1, 0, 0, 16)
			rewardLabel.LayoutOrder = 10
		end

		if quest.status == "available" then
			local btn = UIKit.primaryButton(card, "Accept")
			btn.Size = UDim2.new(0, 120, 0, 26)
			btn.LayoutOrder = 11
			btn.Activated:Connect(function()
				doAction(quest.id, "start")
			end)
		elseif quest.status == "active" then
			if quest.canComplete then
				local btn = UIKit.primaryButton(card, "Turn in")
				btn.Size = UDim2.new(0, 120, 0, 26)
				btn.LayoutOrder = 11
				btn.Activated:Connect(function()
					doAction(quest.id, "complete")
				end)
			else
				local btn = UIKit.ghostButton(card, "In progress")
				btn.Size = UDim2.new(0, 120, 0, 26)
				btn.LayoutOrder = 11
			end
		end
	end

	render = function()
		for _, child in ipairs(list:GetChildren()) do
			if child:IsA("GuiObject") then
				child:Destroy()
			end
		end
		if not current then
			return
		end
		title.Text = current.giverName or "Quests"
		if #current.quests == 0 then
			local hint = makeLabel(list, "Nothing to do here right now.", 13, COLORS.textDim)
			hint.Size = UDim2.new(1, -16, 0, 24)
			hint.LayoutOrder = 1
			return
		end
		for i, quest in ipairs(current.quests) do
			makeCard(i, quest)
		end
	end

	-- ---- open / close ---------------------------------------------------------
	local function close()
		current = nil
		isOpen = false
		panel.Visible = false
		ClientState.questOpen = false
		Sfx.play("panelClose")
	end
	ClientState.closeQuest = close
	closeBtn.Activated:Connect(close)

	Remotes.get("OpenQuestGiver").OnClientEvent:Connect(function(info)
		if typeof(info) ~= "table" then
			return
		end
		if ClientState.inventoryOpen and ClientState.closeInventory then
			ClientState.closeInventory()
		end
		if ClientState.storeOpen and ClientState.closeStore then
			ClientState.closeStore()
		end
		current = info
		statusLabel.Text = ""
		panel.Visible = true
		isOpen = true
		ClientState.questOpen = true
		Sfx.play("panelOpen")
		render()
	end)

	-- Walk away → close (the server enforces its own distance on actions too).
	task.spawn(function()
		while true do
			task.wait(0.5)
			if current and typeof(current.position) == "Vector3" then
				local character = player.Character
				local root = character and character:FindFirstChild("HumanoidRootPart")
				if root and (root.Position - current.position).Magnitude > CLOSE_DISTANCE then
					close()
				end
			end
		end
	end)
end

return QuestUI
