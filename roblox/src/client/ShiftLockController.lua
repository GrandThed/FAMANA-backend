-- Shift-lock: the cursor stays locked to screen center and the character faces
-- the camera's look direction (action-RPG aiming). Holding right mouse button
-- sets ClientState.aiming, which the targeting system uses to focus a target.
-- The cursor frees automatically while the inventory panel is open.

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")
local Workspace = game:GetService("Workspace")

local ClientState = require(script.Parent.ClientState)

local player = Players.LocalPlayer

local ShiftLockController = {}

function ShiftLockController.start()
	local character, root, humanoid

	local function bind(char)
		character = char
		humanoid = char:WaitForChild("Humanoid")
		root = char:WaitForChild("HumanoidRootPart")
	end
	if player.Character then
		bind(player.Character)
	end
	player.CharacterAdded:Connect(bind)

	-- Center crosshair dot.
	local gui = Instance.new("ScreenGui")
	gui.Name = "Crosshair"
	gui.ResetOnSpawn = false
	gui.IgnoreGuiInset = true
	gui.Parent = player:WaitForChild("PlayerGui")

	local dot = Instance.new("Frame")
	dot.Size = UDim2.new(0, 6, 0, 6)
	dot.AnchorPoint = Vector2.new(0.5, 0.5)
	dot.Position = UDim2.new(0.5, 0, 0.5, 0)
	dot.BackgroundColor3 = Color3.new(1, 1, 1)
	dot.BackgroundTransparency = 0.3
	dot.BorderSizePixel = 0
	local dotCorner = Instance.new("UICorner")
	dotCorner.CornerRadius = UDim.new(1, 0)
	dotCorner.Parent = dot
	dot.Parent = gui

	-- Right mouse button → aiming (targeting active).
	UserInputService.InputBegan:Connect(function(input)
		if input.UserInputType == Enum.UserInputType.MouseButton2 then
			ClientState.aiming = true
		end
	end)
	UserInputService.InputEnded:Connect(function(input)
		if input.UserInputType == Enum.UserInputType.MouseButton2 then
			ClientState.aiming = false
		end
	end)

	RunService.RenderStepped:Connect(function()
		local locked = not ClientState.inventoryOpen
		UserInputService.MouseBehavior = locked and Enum.MouseBehavior.LockCenter or Enum.MouseBehavior.Default
		dot.Visible = locked

		if locked and character and character.Parent and root and humanoid and humanoid.Health > 0 then
			if humanoid.AutoRotate then
				humanoid.AutoRotate = false
			end
			local camera = Workspace.CurrentCamera
			if camera then
				local look = camera.CFrame.LookVector
				local flat = Vector3.new(look.X, 0, look.Z)
				if flat.Magnitude > 1e-3 then
					local pos = root.Position
					root.CFrame = CFrame.lookAt(pos, pos + flat.Unit)
				end
			end
		elseif humanoid and not humanoid.AutoRotate then
			humanoid.AutoRotate = true
		end
	end)
end

return ShiftLockController
