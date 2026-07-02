-- Enemy focus/targeting. The enemy nearest the camera's aim (screen center) is
-- focused: it gets a highlight outline and a large target health bar at the top
-- of the screen. Enemy HP is read from the health-bar that the server places on
-- each enemy (its Fill scale replicates), so no extra networking is needed.

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

local player = Players.LocalPlayer

local TargetingController = {}

local MAX_DIST = 90 -- studs
local MAX_SCREEN_FRACTION = 0.35 -- how close to screen-center (as a fraction of height) an enemy must be

local function enemies()
	local folder = Workspace:FindFirstChild("Enemies")
	return folder and folder:GetChildren() or {}
end

local function hpFraction(enemyPart)
	local billboard = enemyPart:FindFirstChild("HealthBar")
	local fill = billboard and billboard:FindFirstChild("Fill", true)
	if fill then
		return math.clamp(fill.Size.X.Scale, 0, 1)
	end
	return nil
end

function TargetingController.start()
	-- ---- target bar UI (top-center) ----
	local gui = Instance.new("ScreenGui")
	gui.Name = "TargetUI"
	gui.ResetOnSpawn = false
	gui.IgnoreGuiInset = true
	gui.Enabled = false
	gui.Parent = player:WaitForChild("PlayerGui")

	local panel = Instance.new("Frame")
	panel.Size = UDim2.new(0, 320, 0, 44)
	panel.Position = UDim2.new(0.5, 0, 0, 14)
	panel.AnchorPoint = Vector2.new(0.5, 0)
	panel.BackgroundColor3 = Color3.fromRGB(20, 20, 26)
	panel.BackgroundTransparency = 0.2
	panel.BorderSizePixel = 0
	panel.Parent = gui

	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0, 8)
	corner.Parent = panel

	local nameLabel = Instance.new("TextLabel")
	nameLabel.Size = UDim2.new(1, -16, 0, 18)
	nameLabel.Position = UDim2.new(0, 8, 0, 4)
	nameLabel.BackgroundTransparency = 1
	nameLabel.Font = Enum.Font.GothamBold
	nameLabel.TextSize = 14
	nameLabel.TextColor3 = Color3.new(1, 1, 1)
	nameLabel.TextXAlignment = Enum.TextXAlignment.Left
	nameLabel.Text = ""
	nameLabel.Parent = panel

	local barBg = Instance.new("Frame")
	barBg.Size = UDim2.new(1, -16, 0, 12)
	barBg.Position = UDim2.new(0, 8, 0, 26)
	barBg.BackgroundColor3 = Color3.fromRGB(45, 45, 45)
	barBg.BorderSizePixel = 0
	barBg.Parent = panel

	local barFill = Instance.new("Frame")
	barFill.Size = UDim2.new(1, 0, 1, 0)
	barFill.BackgroundColor3 = Color3.fromRGB(220, 70, 70)
	barFill.BorderSizePixel = 0
	barFill.Parent = barBg

	-- ---- highlight ----
	local highlight = Instance.new("Highlight")
	highlight.FillTransparency = 0.7
	highlight.FillColor = Color3.fromRGB(255, 230, 120)
	highlight.OutlineColor = Color3.fromRGB(255, 230, 120)
	highlight.OutlineTransparency = 0

	local current

	local function setTarget(part)
		if current == part then
			return
		end
		current = part
		if part then
			highlight.Adornee = part
			highlight.Parent = part
			nameLabel.Text = part.Name
			gui.Enabled = true
		else
			highlight.Adornee = nil
			highlight.Parent = nil
			gui.Enabled = false
		end
	end

	RunService.RenderStepped:Connect(function()
		local camera = Workspace.CurrentCamera
		if not camera then
			return
		end
		local vp = camera.ViewportSize
		local center = Vector2.new(vp.X / 2, vp.Y / 2)

		local best, bestScore
		for _, enemy in ipairs(enemies()) do
			if enemy:IsA("BasePart") then
				local screenPos, onScreen = camera:WorldToViewportPoint(enemy.Position)
				if onScreen and screenPos.Z > 0 then
					local dist = (camera.CFrame.Position - enemy.Position).Magnitude
					if dist <= MAX_DIST then
						local frac = (Vector2.new(screenPos.X, screenPos.Y) - center).Magnitude / vp.Y
						if frac <= MAX_SCREEN_FRACTION and (not bestScore or frac < bestScore) then
							best, bestScore = enemy, frac
						end
					end
				end
			end
		end

		setTarget(best)

		if current then
			if not current.Parent then
				setTarget(nil) -- died / despawned
			else
				local frac = hpFraction(current)
				if frac then
					barFill.Size = UDim2.new(frac, 0, 1, 0)
				end
			end
		end
	end)
end

return TargetingController
