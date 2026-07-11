-- Floating combat damage numbers. Normal hits show a plain white number with
-- a quick pop; critical hits go bigger and bolder: a gold number with a
-- "!!!" suffix, a punchy overshoot pop, a slight random tilt, a warm glow
-- halo behind the text, and a brief radial flash — all "free" juice, no new
-- server data required.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")
local Workspace = game:GetService("Workspace")

local Remotes = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Remotes"))
local Theme = require(script.Parent.Theme)
local UIKit = require(script.Parent.UIKit)
local Sfx = require(script.Parent.Sfx)

local DamageIndicatorUI = {}

local NORMAL_COLOR = Theme.Semantic.TextStrong
local CRIT_COLOR = Theme.Color.Gold400
local CRIT_GLOW_COLOR = Theme.Color.Ember300

local NORMAL_SIZE = 22
local CRIT_SIZE = 36

local FLOAT_RISE = 3.2
local CRIT_RISE = 3.9
local FLOAT_TIME = 0.85
local POP_TIME = 0.12
local CRIT_TILT_MAX = 9 -- degrees, static tilt for punch (not animated)

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
	billboard.Size = UDim2.new(0, 180, 0, 60)
	billboard.AlwaysOnTop = true
	billboard.Parent = part

	-- Crit-only radial flash behind everything: a quick bright burst that
	-- fades almost as fast as it appears, like a muzzle flash on the hit.
	if isCrit then
		local flash = UIKit.addGlow(billboard, CRIT_GLOW_COLOR, 0.15)
		if flash then
			flash.ZIndex = 0
			flash.Size = UDim2.new(1.6, 0, 1.6, 0)
			flash.Position = UDim2.new(-0.3, 0, -0.3, 0)
			TweenService:Create(flash, TweenInfo.new(0.28, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), { ImageTransparency = 1 }):Play()
		end
	end

	local scale = Instance.new("UIScale")
	scale.Scale = isCrit and 0.35 or 0.8 -- both start slightly small and "pop" up, crits much more so
	scale.Parent = billboard

	-- Glow label (crit only): a soft warm duplicate sitting behind the main
	-- text, slightly larger, fading fast — reads as a halo without needing a
	-- real blur/outline (Roblox TextLabels only support a 1px stroke).
	if isCrit then
		local glowLabel = Instance.new("TextLabel")
		glowLabel.Name = "Glow"
		glowLabel.Size = UDim2.new(1, 0, 1, 0)
		glowLabel.BackgroundTransparency = 1
		glowLabel.FontFace = Theme.Font.DisplayBold
		glowLabel.TextSize = CRIT_SIZE + 8
		glowLabel.TextColor3 = CRIT_GLOW_COLOR
		glowLabel.TextTransparency = 0.35
		glowLabel.Text = string.format("-%d!!!", amount)
		glowLabel.ZIndex = 1
		glowLabel.Rotation = math.random(-CRIT_TILT_MAX, CRIT_TILT_MAX)
		glowLabel.Parent = billboard
		TweenService:Create(glowLabel, TweenInfo.new(FLOAT_TIME, Enum.EasingStyle.Quad), { TextTransparency = 1 }):Play()
	end

	local label = Instance.new("TextLabel")
	label.Size = UDim2.new(1, 0, 1, 0)
	label.BackgroundTransparency = 1
	label.FontFace = isCrit and Theme.Font.DisplayBold or Theme.Font.BodyBold
	label.TextSize = isCrit and CRIT_SIZE or NORMAL_SIZE
	label.TextColor3 = isCrit and CRIT_COLOR or NORMAL_COLOR
	label.TextStrokeTransparency = 0
	label.TextStrokeColor3 = Color3.new(0, 0, 0)
	label.Text = isCrit and string.format("-%d!!!", amount) or string.format("-%d", amount)
	-- Crits get a static random tilt (punchier, less "typed text" than dead
	-- straight); normal hits stay level so the HUD doesn't feel jittery.
	label.Rotation = isCrit and math.random(-CRIT_TILT_MAX, CRIT_TILT_MAX) or 0
	label.ZIndex = 2
	label.Parent = billboard

	-- Overshoot pop for every hit; crits overshoot further and snap back
	-- harder so they read as heavier impacts at a glance.
	local popScale = isCrit and 1.3 or 1.08
	local popUp = TweenService:Create(scale, TweenInfo.new(POP_TIME, Enum.EasingStyle.Back, Enum.EasingDirection.Out), { Scale = popScale })
	popUp:Play()
	popUp.Completed:Once(function()
		TweenService:Create(scale, TweenInfo.new(POP_TIME, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), { Scale = 1 }):Play()
	end)

	-- Rise with a touch of horizontal drift (an arc, not a straight elevator)
	-- so consecutive numbers read as distinct even without much jitter.
	local rise = isCrit and CRIT_RISE or FLOAT_RISE
	local drift = jitter.X > 0 and 0.6 or -0.6
	local goal = CFrame.new(startPos + Vector3.new(drift, rise, 0))
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
		-- playThrottled, no play: dealDamage (server/EnemyService.lua) todavía
		-- no tiene cooldown propio, así que esto es lo único que evita que
		-- clickear rápido sature de sonido hasta que eso se resuelva del
		-- lado del gameplay.
		Sfx.playThrottled(isCrit and "critHit" or "hit", 0.07)
	end)
end

return DamageIndicatorUI