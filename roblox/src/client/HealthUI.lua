-- Simple health bar. Reads the local character's Humanoid directly (HP
-- replicates automatically, so no remote needed).

local Players = game:GetService("Players")
local player = Players.LocalPlayer

local HealthUI = {}

function HealthUI.start()
	local gui = Instance.new("ScreenGui")
	gui.Name = "HealthUI"
	gui.ResetOnSpawn = false
	gui.IgnoreGuiInset = true
	gui.Parent = player:WaitForChild("PlayerGui")

	local container = Instance.new("Frame")
	container.Size = UDim2.new(0, 240, 0, 26)
	container.Position = UDim2.new(0, 16, 1, -16)
	container.AnchorPoint = Vector2.new(0, 1)
	container.BackgroundColor3 = Color3.fromRGB(20, 20, 20)
	container.BorderSizePixel = 0
	container.Parent = gui

	local bar = Instance.new("Frame")
	bar.Size = UDim2.new(1, 0, 1, 0)
	bar.BackgroundColor3 = Color3.fromRGB(200, 60, 60)
	bar.BorderSizePixel = 0
	bar.Parent = container

	local label = Instance.new("TextLabel")
	label.Size = UDim2.new(1, 0, 1, 0)
	label.BackgroundTransparency = 1
	label.TextColor3 = Color3.new(1, 1, 1)
	label.Font = Enum.Font.GothamBold
	label.TextScaled = true
	label.Text = "100 / 100"
	label.Parent = container

	local function bind(character)
		local humanoid = character:WaitForChild("Humanoid")
		local function update()
			local pct = humanoid.MaxHealth > 0 and (humanoid.Health / humanoid.MaxHealth) or 0
			bar.Size = UDim2.new(math.clamp(pct, 0, 1), 0, 1, 0)
			label.Text = string.format("%d / %d", math.floor(humanoid.Health + 0.5), math.floor(humanoid.MaxHealth + 0.5))
		end
		humanoid.HealthChanged:Connect(update)
		humanoid:GetPropertyChangedSignal("MaxHealth"):Connect(update)
		update()
	end

	if player.Character then
		bind(player.Character)
	end
	player.CharacterAdded:Connect(bind)
end

return HealthUI
