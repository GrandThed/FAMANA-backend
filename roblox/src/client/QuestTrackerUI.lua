-- HUD tracker de la quest "trackeada" (top-left, siempre visible, sin
-- botón para abrir — es solo lectura). Vive oculto por completo cuando no
-- hay nada trackeado (ninguna quest activa, o el jugador nunca aceptó
-- ninguna). Cuál quest está trackeada lo decide el servidor (QuestService)
-- vía el panel QuestLogUI ("Track") o el fallback automático del servidor;
-- este módulo no elige nada, solo refleja lo que le llega.
--
-- Dos fuentes de datos, mismo payload en las dos (buildTrackedPayload del
-- server: { questId, name, objectives = {label, current, amount} }):
--   1. RequestTrackedQuest (RemoteFunction) — pedido único al arrancar.
--   2. TrackedQuestChanged (RemoteEvent) — cada vez que cambia la quest
--      trackeada O progresa un objetivo de la trackeada (ver pushTracked
--      del lado server, se dispara desde start/complete/bump).

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Remotes = require(Shared:WaitForChild("Remotes"))
local Theme = require(script.Parent.Theme)
local UIKit = require(script.Parent.UIKit)

local player = Players.LocalPlayer

local QuestTrackerUI = {}

local INSET = 16
local WIDTH = 240
-- Más largo que Theme.Tween.UI (0.2s, pensado para hovers/paneles) — un
-- flash de borde necesita quedarse a la vista un toque más para notarse.
local FLASH_TWEEN = TweenInfo.new(0.5, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)

local function makeLabel(parent, text, size, color, font)
	local label = Instance.new("TextLabel")
	label.BackgroundTransparency = 1
	label.FontFace = font or Theme.Font.Body
	label.TextSize = size
	label.TextColor3 = color or Theme.Semantic.TextBody
	label.TextWrapped = true
	label.TextXAlignment = Enum.TextXAlignment.Left
	label.Text = text
	label.Parent = parent
	return label
end

function QuestTrackerUI.start()
	local gui = Instance.new("ScreenGui")
	gui.Name = "QuestTrackerUI"
	gui.ResetOnSpawn = false
	gui.Enabled = true
	gui.Parent = player:WaitForChild("PlayerGui")

	local card = Instance.new("Frame")
	card.Size = UDim2.new(0, WIDTH, 0, 0)
	card.AutomaticSize = Enum.AutomaticSize.Y
	card.Position = UDim2.new(0, INSET, 0, INSET)
	card.Visible = false -- nada trackeado hasta que llegue el primer payload
	card.Parent = gui
	local cardStroke = UIKit.stylePanel(card)
	UIKit.addShadow(card)
	UIKit.autoScale(card)

	-- Color/grosor "en reposo" del borde, para volver a ellos después del
	-- flash (leídos de lo que stylePanel ya dejó puesto, no hardcodeados).
	local restColor = cardStroke.Color
	local restThickness = cardStroke.Thickness

	-- Flash del borde: SOLO cuando la quest trackeada cambia de verdad
	-- (una nueva pasa a estar trackeada, o se completó y se reemplazó por
	-- otra) — nunca en cada tick de progreso, eso sería machacón durante
	-- un grind de "matá 10 de esto".
	local function flash()
		cardStroke.Color = Theme.Semantic.Accent
		cardStroke.Thickness = 2
		TweenService:Create(cardStroke, FLASH_TWEEN, {
			Color = restColor,
			Thickness = restThickness,
		}):Play()
	end

	local padding = Instance.new("UIPadding")
	padding.PaddingTop = UDim.new(0, 8)
	padding.PaddingLeft = UDim.new(0, 10)
	padding.PaddingRight = UDim.new(0, 10)
	padding.PaddingBottom = UDim.new(0, 8)
	padding.Parent = card

	local layout = Instance.new("UIListLayout")
	layout.SortOrder = Enum.SortOrder.LayoutOrder
	layout.Padding = UDim.new(0, 2)
	layout.Parent = card

	local nameLabel = makeLabel(card, "", 14, Theme.Semantic.TextTitle, Theme.Font.DisplayBold)
	nameLabel.Size = UDim2.new(1, 0, 0, 18)
	nameLabel.LayoutOrder = 1

	local objectiveLabels = {} -- reutilizadas entre renders, se crean/destruyen según haga falta
	local lastQuestId -- nil = nada trackeado todavía / se acaba de limpiar

	local function render(payload)
		if not payload or typeof(payload) ~= "table" or typeof(payload.objectives) ~= "table" then
			card.Visible = false
			lastQuestId = nil
			return
		end

		card.Visible = true
		-- TrackedQuestChanged también se dispara en cada bump de la
		-- trackeada (para refrescar los números en vivo) — el flash es
		-- solo para cuando `questId` en sí cambió, no para cada tick.
		if payload.questId ~= lastQuestId then
			flash()
		end
		lastQuestId = payload.questId

		nameLabel.Text = payload.name or ""

		for i, objective in ipairs(payload.objectives) do
			local lbl = objectiveLabels[i]
			if not lbl then
				lbl = makeLabel(card, "", 12, Theme.Semantic.TextBody)
				lbl.Size = UDim2.new(1, 0, 0, 16)
				lbl.LayoutOrder = 1 + i
				objectiveLabels[i] = lbl
			end
			local met = objective.current >= objective.amount
			lbl.Text = string.format("%s  %d/%d", objective.label, objective.current, objective.amount)
			lbl.TextColor3 = met and Theme.Semantic.Good or Theme.Semantic.TextBody
			lbl.Visible = true
		end

		-- Sobran labels de un render anterior con más objetivos: ocultarlas
		-- en vez de destruirlas (se pueden reusar si vuelve a crecer).
		for i = #payload.objectives + 1, #objectiveLabels do
			objectiveLabels[i].Visible = false
		end
	end

	Remotes.get("TrackedQuestChanged").OnClientEvent:Connect(render)

	task.spawn(function()
		local ok, payload = pcall(function()
			return Remotes.getFunction("RequestTrackedQuest"):InvokeServer()
		end)
		if ok then
			render(payload)
		end
	end)
end

return QuestTrackerUI
