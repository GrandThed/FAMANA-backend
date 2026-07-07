-- Stylized "LEVEL UP" banner, center screen. Fired by the server's "LevelUp"
-- RemoteEvent whenever PlayerService.addXp rolls the player into a new level.
-- Purely a celebratory moment for now — no stat changes ride on this.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")

local Remotes = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Remotes"))
local Theme = require(script.Parent.Theme)

local player = Players.LocalPlayer

local LevelUpUI = {}

local HOLD_TIME = 1.4
local POP_TIME = 0.25
local FADE_TIME = 0.5

function LevelUpUI.start()
	local gui = Instance.new("ScreenGui")
	gui.Name = "LevelUpUI"
	gui.ResetOnSpawn = false
	gui.IgnoreGuiInset = true
	gui.DisplayOrder = 600
	gui.Parent = player:WaitForChild("PlayerGui")

	local container = Instance.new("Frame")
	container.Size = UDim2.new(0, 420, 0, 90)
	container.Position = UDim2.new(0.5, 0, 0.28, 0)
	container.AnchorPoint = Vector2.new(0.5, 0.5)
	container.BackgroundTransparency = 1
	container.Parent = gui

	local scale = Instance.new("UIScale")
	scale.Scale = 0.3
	scale.Parent = container

	local title = Instance.new("TextLabel")
	title.Size = UDim2.new(1, 0, 0, 34)
	title.BackgroundTransparency = 1
	title.FontFace = Theme.Font.DisplayBold
	title.TextSize = 30
	title.TextColor3 = Theme.Color.Gold400
	title.TextTransparency = 1
	title.TextStrokeTransparency = 1
	title.TextStrokeColor3 = Color3.new(0, 0, 0)
	title.Text = "¡SUBISTE DE NIVEL!"
	title.Parent = container

	local levelText = Instance.new("TextLabel")
	levelText.Size = UDim2.new(1, 0, 0, 46)
	levelText.Position = UDim2.new(0, 0, 0, 36)
	levelText.BackgroundTransparency = 1
	levelText.FontFace = Theme.Font.DisplayBold
	levelText.TextSize = 42
	levelText.TextColor3 = Theme.Semantic.TextStrong
	levelText.TextTransparency = 1
	levelText.TextStrokeTransparency = 1
	levelText.TextStrokeColor3 = Color3.new(0, 0, 0)
	levelText.Parent = container

	local function play(level)
		levelText.Text = string.format("Nivel %d", level)

		scale.Scale = 0.3
		title.TextTransparency = 1
		title.TextStrokeTransparency = 1
		levelText.TextTransparency = 1
		levelText.TextStrokeTransparency = 1

		local popIn = TweenService:Create(
			scale,
			TweenInfo.new(POP_TIME, Enum.EasingStyle.Back, Enum.EasingDirection.Out),
			{ Scale = 1 }
		)
		local fadeIn = TweenInfo.new(POP_TIME)
		TweenService:Create(title, fadeIn, { TextTransparency = 0, TextStrokeTransparency = 0.2 }):Play()
		TweenService:Create(levelText, fadeIn, { TextTransparency = 0, TextStrokeTransparency = 0.2 }):Play()
		popIn:Play()

		task.delay(POP_TIME + HOLD_TIME, function()
			local fadeOut = TweenInfo.new(FADE_TIME)
			TweenService:Create(title, fadeOut, { TextTransparency = 1, TextStrokeTransparency = 1 }):Play()
			TweenService:Create(levelText, fadeOut, { TextTransparency = 1, TextStrokeTransparency = 1 }):Play()
		end)
	end

	Remotes.get("LevelUp").OnClientEvent:Connect(function(level)
		if typeof(level) == "number" then
			play(level)
		end
	end)
end

return LevelUpUI
