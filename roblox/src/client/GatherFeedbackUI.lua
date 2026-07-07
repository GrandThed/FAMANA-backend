-- esto es un texto de +1 o la cantidad de recursos que se recolectan y el sonido que tiene pegarle a los arboles o piedras

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")
local Workspace = game:GetService("Workspace")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Items = require(Shared:WaitForChild("Items"))
local Remotes = require(Shared:WaitForChild("Remotes"))
local Theme = require(script.Parent.Theme)

local GatherFeedbackUI = {}

-- los sonidos los sacas de la tienda de roblox studio
local SOUND_IDS = {
	wood = "rbxassetid://1911987235",
	stone = "rbxassetid://9118617342",
}

local FLOAT_RISE = 3 -- studs the text rises before fading out
local FLOAT_TIME = 0.9

-- la funcion de hacer ruido tipo feedback
local function playImpactSound(itemId, position)
	local soundId = SOUND_IDS[itemId]
	if not soundId then
		return
	end

	local anchor = Instance.new("Part")
	anchor.Name = "GatherSoundAnchor"
	anchor.Anchored = true
	anchor.CanCollide = false
	anchor.CanQuery = false
	anchor.Transparency = 1
	anchor.Size = Vector3.new(0.1, 0.1, 0.1)
	anchor.CFrame = CFrame.new(position)
	anchor.Parent = Workspace

	local sound = Instance.new("Sound")
	sound.SoundId = soundId
	sound.Volume = 0.6
	sound.RollOffMaxDistance = 60
	sound.Parent = anchor
	sound:Play()

	sound.Ended:Once(function()
		anchor:Destroy()
	end)
	-- Failsafe: clean up even if Ended never fires (e.g. an invalid asset id).
	task.delay(4, function()
		if anchor.Parent then
			anchor:Destroy()
		end
	end)
end

-- A short-lived world-space "+1 Wood" label that rises and fades over the
-- node, like a damage number.
local function floatingText(text, position)
	local part = Instance.new("Part")
	part.Name = "GatherText"
	part.Anchored = true
	part.CanCollide = false
	part.CanQuery = false
	part.Transparency = 1
	part.Size = Vector3.new(0.1, 0.1, 0.1)
	part.CFrame = CFrame.new(position + Vector3.new(0, 3, 0))
	part.Parent = Workspace

	local billboard = Instance.new("BillboardGui")
	billboard.Size = UDim2.new(0, 120, 0, 30)
	billboard.AlwaysOnTop = true
	billboard.Parent = part

	local label = Instance.new("TextLabel")
	label.Size = UDim2.new(1, 0, 1, 0)
	label.BackgroundTransparency = 1
	label.FontFace = Theme.Font.BodyBold
	label.TextSize = 20
	label.TextColor3 = Theme.Color.Gold300
	label.TextStrokeTransparency = 0.2
	label.Text = text
	label.Parent = billboard

	local goal = CFrame.new(position + Vector3.new(0, 3 + FLOAT_RISE, 0))
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

function GatherFeedbackUI.start()
	Remotes.get("GatherFeedback").OnClientEvent:Connect(function(itemId, amount, position)
		if typeof(position) ~= "Vector3" then
			return
		end
		local def = Items.get(itemId)
		floatingText(string.format("+%d %s", amount, def and def.name or itemId), position)
		playImpactSound(itemId, position)
	end)
end

return GatherFeedbackUI
