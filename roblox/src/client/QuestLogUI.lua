-- Quest log panel (J key / top-right button, stacked under Craft). Muestra
-- TODAS las quests que el jugador tiene (activas + completadas), a
-- diferencia de QuestUI.lua (el panel del NPC dador, que solo muestra las
-- quests DE ESE giver). Acá vive el botón "Track" que decide cuál aparece
-- en el HUD (QuestTrackerUI) — el servidor es la única autoridad sobre cuál
-- es la trackeada; este panel solo pide/muestra `RequestQuestLog` y llama
-- `SetTrackedQuest`, mismo patrón request/response que QuestAction en
-- QuestUI.lua (la respuesta ya trae el log refrescado, sin segundo viaje).

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ContextActionService = game:GetService("ContextActionService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Remotes = require(Shared:WaitForChild("Remotes"))
local Theme = require(script.Parent.Theme)
local TopRightMenu = require(script.Parent.TopRightMenu)
local UIKit = require(script.Parent.UIKit)
local Sfx = require(script.Parent.Sfx)

local player = Players.LocalPlayer

local QuestLogUI = {}

-- Aethelgard palette (client/Theme.lua) — mismos alias que QuestUI/CraftUI.
local COLORS = {
	section = Theme.Semantic.SurfaceWell,
	line = Theme.Semantic.BorderHair,
	tile = Theme.Color.Ink900,
	accent = Theme.Color.Ember300,
	good = Theme.Semantic.Good,
	text = Theme.Semantic.TextBody,
	textDim = Theme.Semantic.TextMuted,
}

local PANEL_W = 460
local PANEL_H = 520

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

function QuestLogUI.start()
	local gui = Instance.new("ScreenGui")
	gui.Name = "QuestLogUI"
	gui.ResetOnSpawn = false
	gui.Enabled = true
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

	local title = makeLabel(panel, "Quests", Theme.Text.Title, Theme.Semantic.TextTitle, Theme.Font.DisplayBold)
	title.Size = UDim2.new(1, -80, 0, 30)
	title.Position = UDim2.new(0, 12, 0, 4)

	local closeBtn = UIKit.closeButton(panel)
	closeBtn.Position = UDim2.new(1, -6, 0, 6)
	closeBtn.AnchorPoint = Vector2.new(1, 0)

	local emptyLabel = makeLabel(
		panel,
		"No has aceptado ninguna misión todavía. Hablá con un NPC con un ícono de misión sobre la cabeza.",
		13,
		COLORS.textDim,
		Theme.Font.BodyItalic
	)
	emptyLabel.Size = UDim2.new(1, -24, 0, 60)
	emptyLabel.Position = UDim2.new(0, 12, 0, 44)
	emptyLabel.Visible = false

	local list = Instance.new("ScrollingFrame")
	list.Size = UDim2.new(1, -24, 1, -52)
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
	layout.Padding = UDim.new(0, 6)
	layout.Parent = list

	local listPadding = Instance.new("UIPadding")
	listPadding.PaddingTop = UDim.new(0, 8)
	listPadding.PaddingLeft = UDim.new(0, 8)
	listPadding.PaddingRight = UDim.new(0, 8)
	listPadding.PaddingBottom = UDim.new(0, 8)
	listPadding.Parent = list

	local isOpen = false
	local log = {} -- último RequestQuestLog/SetTrackedQuest.log
	local pending = {} -- [questId] = true mientras esperamos la respuesta de un click en Track
	local render, refresh

	local requestQuestLog = Remotes.getFunction("RequestQuestLog")
	local setTrackedQuest = Remotes.getFunction("SetTrackedQuest")

	local function trackQuest(questId)
		if pending[questId] then
			return
		end
		pending[questId] = true
		task.spawn(function()
			local ok, result = pcall(function()
				return setTrackedQuest:InvokeServer(questId)
			end)
			pending[questId] = false
			if ok and typeof(result) == "table" and typeof(result.log) == "table" then
				log = result.log
				Sfx.play("uiClick")
				render()
			end
		end)
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
		cardStroke.Thickness = quest.tracked and 2 or 1
		cardStroke.Color = quest.status == "completed" and COLORS.good
			or quest.tracked and COLORS.accent
			or COLORS.line
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

		local statusText = quest.status == "completed" and "DONE" or quest.tracked and "TRACKING" or "ACTIVE"
		local statusColor = quest.status == "completed" and COLORS.good or quest.tracked and COLORS.accent or COLORS.textDim
		local statusTag = makeLabel(nameRow, statusText, 11, statusColor, Theme.Font.BodyBold)
		statusTag.Size = UDim2.new(0, 90, 1, 0)
		statusTag.Position = UDim2.new(1, -90, 0, 0)
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

		if quest.status == "active" then
			local btn
			if quest.tracked then
				btn = UIKit.ghostButton(card, "Tracking")
			else
				btn = UIKit.primaryButton(card, "Track")
				btn.Activated:Connect(function()
					trackQuest(quest.id)
				end)
			end
			btn.Size = UDim2.new(0, 120, 0, 26)
			btn.LayoutOrder = 20
		end
	end

	render = function()
		for _, child in ipairs(list:GetChildren()) do
			if child:IsA("GuiObject") then
				child:Destroy()
			end
		end
		emptyLabel.Visible = #log == 0
		list.Visible = #log > 0
		for i, quest in ipairs(log) do
			makeCard(i, quest)
		end
	end

	refresh = function()
		task.spawn(function()
			local ok, result = pcall(function()
				return requestQuestLog:InvokeServer()
			end)
			if ok and typeof(result) == "table" then
				log = result
				render()
			end
		end)
	end

	local function setOpen(open)
		isOpen = open
		Sfx.play(isOpen and "panelOpen" or "panelClose")
		panel.Visible = isOpen
		if isOpen then
			refresh()
		end
	end

	local function toggle()
		setOpen(not isOpen)
	end

	local openBtn = TopRightMenu.addButton("Quests (J)", 4)
	openBtn.Name = "QuestLogButton"

	openBtn.Activated:Connect(toggle)
	closeBtn.Activated:Connect(function()
		setOpen(false)
	end)

	ContextActionService:BindAction("ToggleQuestLog", function(_, inputState)
		if inputState == Enum.UserInputState.Begin then
			toggle()
		end
		return Enum.ContextActionResult.Pass
	end, false, Enum.KeyCode.J)

	-- Refrescar en vivo si el panel está abierto y algo cambia (arrancar/
	-- completar otra quest, bumpear un objetivo) — mismo criterio que
	-- CraftUI con InventoryUpdated.
	Remotes.get("QuestUpdated").OnClientEvent:Connect(function()
		if isOpen then
			refresh()
		end
	end)
end

return QuestLogUI
