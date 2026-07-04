-- Applies per-cell theming so it's obvious which grid cell you're in: tints the
-- baseplate and raises a large floating sign with the cell's name.

local Workspace = game:GetService("Workspace")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local GridConfig = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("GridConfig"))

local WorldService = {}

local function tintGround(theme)
	-- Default Baseplate is named "Baseplate"; tint whatever large ground part exists.
	local ground = Workspace:FindFirstChild("Baseplate")
	if ground and ground:IsA("BasePart") then
		ground.Color = theme.ground
		ground.Material = Enum.Material.Grass
	end
end

local function raiseSign(theme)
	local anchor = Instance.new("Part")
	anchor.Name = "CellSign"
	anchor.Anchored = true
	anchor.CanCollide = false
	anchor.Transparency = 1
	anchor.Size = Vector3.new(1, 1, 1)
	anchor.Position = Vector3.new(0, 40, 0)
	anchor.Parent = Workspace

	local billboard = Instance.new("BillboardGui")
	billboard.Size = UDim2.new(0, 500, 0, 130)
	billboard.AlwaysOnTop = false
	billboard.MaxDistance = 500
	billboard.Parent = anchor

	local label = Instance.new("TextLabel")
	label.Size = UDim2.new(1, 0, 1, 0)
	label.BackgroundTransparency = 1
	label.Font = Enum.Font.GothamBlack
	label.TextScaled = true
	label.TextColor3 = theme.signColor
	label.TextStrokeTransparency = 0.3
	label.Text = theme.name
	label.Parent = billboard
end

function WorldService.start()
	local cellId = GridConfig.currentCell()
	local theme = GridConfig.theme(cellId)
	tintGround(theme)
	raiseSign(theme)
end

return WorldService
