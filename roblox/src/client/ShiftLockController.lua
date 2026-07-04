-- Hold-right-click to aim. While RMB is held (and the inventory is closed) the
-- character faces the camera's look direction (action-RPG aiming), a crosshair
-- shows, and ClientState.aiming is set so the targeting system focuses a
-- target. The mouse is NOT locked — Roblox's default RMB-drag already rotates
-- the camera; releasing RMB restores normal movement facing.

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")
local Workspace = game:GetService("Workspace")

local ClientState = require(script.Parent.ClientState)

local player = Players.LocalPlayer

-- How quickly the character turns to face the camera while aiming (exponential
-- smoothing rate; higher = snappier, lower = lazier). Framerate-independent.
local AIM_TURN_SPEED = 8

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

	RunService.RenderStepped:Connect(function(dt)
		-- Aim (face camera + crosshair + targeting) only while holding RMB and
		-- not in the inventory. The mouse is never locked.
		local aiming = ClientState.aiming and not ClientState.inventoryOpen
		dot.Visible = aiming

		if aiming and character and character.Parent and root and humanoid and humanoid.Health > 0 then
			if humanoid.AutoRotate then
				humanoid.AutoRotate = false
			end
			local camera = Workspace.CurrentCamera
			if camera then
				local look = camera.CFrame.LookVector
				local flat = Vector3.new(look.X, 0, look.Z)
				if flat.Magnitude > 1e-3 then
					local pos = root.Position
					local target = CFrame.lookAt(pos, pos + flat.Unit)
					-- Ease toward the camera direction instead of snapping.
					local alpha = 1 - math.exp(-AIM_TURN_SPEED * dt)
					root.CFrame = root.CFrame:Lerp(target, alpha)
				end
			end
		elseif humanoid and not humanoid.AutoRotate then
			humanoid.AutoRotate = true
		end
	end)
end

return ShiftLockController
