-- Makes the character face where the camera is looking (action-RPG / shift-lock
-- style). Disables Humanoid.AutoRotate and orients the root to the camera's
-- horizontal look direction each frame.

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

local player = Players.LocalPlayer

local CameraFaceController = {}

function CameraFaceController.start()
	local character, root, humanoid

	local function bind(char)
		character = char
		humanoid = char:WaitForChild("Humanoid")
		root = char:WaitForChild("HumanoidRootPart")
		humanoid.AutoRotate = false -- we control facing ourselves
	end

	if player.Character then
		bind(player.Character)
	end
	player.CharacterAdded:Connect(bind)

	RunService.RenderStepped:Connect(function()
		if not (character and character.Parent and root and humanoid and humanoid.Health > 0) then
			return
		end
		local camera = Workspace.CurrentCamera
		if not camera then
			return
		end

		-- Flatten the camera look to the horizontal plane so the character stays
		-- upright but yaws to face the aim direction.
		local look = camera.CFrame.LookVector
		local flat = Vector3.new(look.X, 0, look.Z)
		if flat.Magnitude < 1e-3 then
			return
		end

		local pos = root.Position
		root.CFrame = CFrame.lookAt(pos, pos + flat.Unit)
	end)
end

return CameraFaceController
