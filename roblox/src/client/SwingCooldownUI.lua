-- Minecraft-style attack/gather cooldown bar: a thin pill under the crosshair
-- that goes dim and drains right after a swing, then fills back to solid
-- white as you become ready again. Reads the same SwingCdExpiry/
-- SwingCdDuration Player attributes ToolService.playSwing already sets for
-- HudUI's hotbar veil (see ToolService.lua, GatheringService.registerCooldownFor
-- for why tools use their own longer real cooldown) — this is just a second,
-- always-in-view read of the same numbers, not a new cooldown system.
--
-- Visible only while a weapon/tool/placeable is actually held (an equipped
-- Tool exists), same as when the hotbar veil would apply.

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

local player = Players.LocalPlayer

local BAR_WIDTH = 64
local BAR_HEIGHT = 5
-- Vertical offset from dead-center, in px — clears ShiftLockController's
-- center dot (which only shows while aiming) so the two never overlap.
local BELOW_CROSSHAIR = 28

local SwingCooldownUI = {}

function SwingCooldownUI.start()
	local gui = Instance.new("ScreenGui")
	gui.Name = "SwingCooldownUI"
	gui.ResetOnSpawn = false
	gui.IgnoreGuiInset = true
	gui.Parent = player:WaitForChild("PlayerGui")

	local frame = Instance.new("Frame")
	frame.Name = "Bar"
	frame.Size = UDim2.new(0, BAR_WIDTH, 0, BAR_HEIGHT)
	frame.AnchorPoint = Vector2.new(0.5, 0.5)
	frame.Position = UDim2.new(0.5, 0, 0.5, BELOW_CROSSHAIR)
	frame.BackgroundColor3 = Color3.new(0, 0, 0)
	frame.BackgroundTransparency = 0.55
	frame.BorderSizePixel = 0
	frame.Visible = false
	frame.Parent = gui

	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(1, 0)
	corner.Parent = frame

	local stroke = Instance.new("UIStroke")
	stroke.Color = Color3.new(0, 0, 0)
	stroke.Transparency = 0.45
	stroke.Thickness = 1
	stroke.Parent = frame

	-- Fills left→right as the cooldown recovers (Size.X.Scale 0 → 1), same
	-- read as the hotbar veil's fraction but drawn as growth instead of drain
	-- so it reads correctly as a *pill*, not a curtain.
	local fill = Instance.new("Frame")
	fill.Name = "Fill"
	fill.AnchorPoint = Vector2.new(0, 0)
	fill.Position = UDim2.new(0, 0, 0, 0)
	fill.Size = UDim2.new(1, 0, 1, 0)
	fill.BackgroundColor3 = Color3.new(1, 1, 1)
	fill.BackgroundTransparency = 0.1
	fill.BorderSizePixel = 0
	fill.ZIndex = 2
	fill.Parent = frame

	local fillCorner = Instance.new("UICorner")
	fillCorner.CornerRadius = UDim.new(1, 0)
	fillCorner.Parent = fill

	local function equippedTool()
		local character = player.Character
		return character and character:FindFirstChildOfClass("Tool")
	end

	RunService.RenderStepped:Connect(function()
		local tool = equippedTool()
		if not tool then
			frame.Visible = false
			return
		end
		frame.Visible = true

		local expiry = player:GetAttribute("SwingCdExpiry")
		local duration = player:GetAttribute("SwingCdDuration")
		local remaining = 0
		if typeof(expiry) == "number" then
			remaining = expiry - Workspace:GetServerTimeNow()
		end

		if remaining > 0 and typeof(duration) == "number" and duration > 0 then
			local ready = 1 - math.clamp(remaining / duration, 0, 1)
			fill.Size = UDim2.new(ready, 0, 1, 0)
			fill.BackgroundTransparency = 0.4 -- dimmer while recovering
		else
			fill.Size = UDim2.new(1, 0, 1, 0)
			fill.BackgroundTransparency = 0.1 -- solid white when ready
		end
	end)
end

return SwingCooldownUI