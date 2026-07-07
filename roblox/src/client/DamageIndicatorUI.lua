-- Floating combat damage numbers. Normal hits show a plain white number;
-- critical hits show a bigger, yellow number with a "!!!" suffix and a quick
-- "pop" scale animation for extra impact.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")
local Workspace = game:GetService("Workspace")

local Remotes = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Remotes"))
local Theme = require(script.Parent.Theme)

local DamageIndicatorUI = {}

local NORMAL_COLOR = Theme.Semantic.TextStrong
local CRIT_COLOR = Theme.Color.Gold400

local NORMAL_SIZE = 22
local CRIT_SIZE = 34

local FLOAT_RISE = 3.2
local FLOAT_TIME = 0.85
local POP_TIME = 0.12

local function damageText(amount, isCrit, position)
	-- Small random horizontal jitter so consecutive hits don't stack exactly
	-- on top of each other.
	local jitter = Vector3.new((math.random() - 0.5) * 1.6, 0, (math.random() - 0.5) * 1.6)
	local startPos = position + Vector3.new(0, 3.5, 0) + jitter

	local part = Instance.new("Part")
	part.Name = "DamageText"
	part.Anchored = true
	part.CanCollide = false
	part.CanQuery = false
	part.Transparency = 1
	part.Size = Vector3.new(0.1, 0.1, 0.1)
	part.CFrame = CFrame.new(startPos)
	part.Parent = Workspace

	local billboard = Instance.new("BillboardGui")
	billboard.Size = UDim2.new(0, 160, 0, 50)
	billboard.AlwaysOnTop = true
	billboard.Parent = part

	local scale = Instance.new("UIScale")
	scale.Scale = isCrit and 0.4 or 1 -- crits start small and "pop" up
	scale.Parent = billboard

	local label = Instance.new("TextLabel")
	label.Size = UDim2.new(1, 0, 1, 0)
	label.BackgroundTransparency = 1
	label.FontFace = isCrit and Theme.Font.DisplayBold or Theme.Font.BodyBold
	label.TextSize = isCrit and CRIT_SIZE or NORMAL_SIZE
	label.TextColor3 = isCrit and CRIT_COLOR or NORMAL_COLOR
	label.TextStrokeTransparency = 0
	label.TextStrokeColor3 = Color3.new(0, 0, 0)
	label.Text = isCrit and string.format("-%d!!!", amount) or string.format("-%d", amount)
	label.Parent = billboard

	if isCrit then
		-- Quick overshoot pop: 0.4 -> 1.25 -> 1.0 scale.
		local popUp = TweenService:Create(scale, TweenInfo.new(POP_TIME, Enum.EasingStyle.Back, Enum.EasingDirection.Out), { Scale = 1.25 })
		popUp:Play()
		popUp.Completed:Once(function()
			TweenService:Create(scale, TweenInfo.new(POP_TIME, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), { Scale = 1 }):Play()
		end)
	end

	local goal = CFrame.new(startPos + Vector3.new(0, FLOAT_RISE, 0))
	local riseTween = TweenService:Create(
		part,
		TweenInfo.new(FLOAT_TIME, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
		{ CFrame = goal }
	)
	local fadeTween = TweenService:Create(
		label,
		TweenInfo.new(FLOAT_TIME),
		{ TextTransparency = 1, TextStrokeTransparency = 1 }
	)
	riseTween:Play()
	fadeTween:Play()
	fadeTween.Completed:Once(function()
		part:Destroy()
	end)
end

function DamageIndicatorUI.start()
	Remotes.get("DamageIndicator").OnClientEvent:Connect(function(amount, isCrit, position)
		if typeof(position) ~= "Vector3" or typeof(amount) ~= "number" then
			return
		end
		damageText(amount, isCrit == true, position)
	end)
end

return DamageIndicatorUI
