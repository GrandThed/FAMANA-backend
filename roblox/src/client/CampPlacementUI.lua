-- Ground preview + placement for the "acampada" deployable. The item is
-- `type = "placeable"` (see shared/Items.lua), which ToolService turns into
-- a held Tool like any weapon/tool — no custom equip flow needed. While it's
-- equipped this shows a translucent square following the mouse (green/red
-- depending on whether you're in range); clicking fires PlaceAcampada with
-- that ground point. The server re-validates everything (distance, item
-- ownership, cooldown) and never trusts this preview — see
-- server/CampService.lua. Success/error feedback comes back as a toast via
-- the existing "Notify" remote, so this module doesn't need to handle it.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared:WaitForChild("Config"))
local Remotes = require(Shared:WaitForChild("Remotes"))

local player = Players.LocalPlayer

local CampPlacementUI = {}

local ZONE_SIZE = Config.Camp.zoneSize
local MAX_DISTANCE = Config.Camp.maxPlacementDistance

local COLOR_OK = Color3.fromRGB(88, 156, 76)
local COLOR_TOO_FAR = Color3.fromRGB(200, 62, 70)

local placeAcampada -- RemoteFunction, resolved in start()
local placing = false -- debounce: one in-flight request at a time

local function createPreview()
	local part = Instance.new("Part")
	part.Name = "AcampadaPreview"
	part.Size = Vector3.new(ZONE_SIZE, 0.2, ZONE_SIZE)
	part.Anchored = true
	part.CanCollide = false
	part.CanQuery = false -- don't let the mouse raycast hit its own preview
	part.Transparency = 0.6
	part.Material = Enum.Material.SmoothPlastic
	part.Color = COLOR_OK
	part.Parent = workspace
	return part
end

local function attachTool(tool)
	local mouse = player:GetMouse()
	local preview, renderConn

	local function teardown()
		if renderConn then
			renderConn:Disconnect()
			renderConn = nil
		end
		if preview then
			preview:Destroy()
			preview = nil
		end
		mouse.TargetFilter = nil
	end

	local equippedConn = tool.Equipped:Connect(function()
		preview = createPreview()
		mouse.TargetFilter = preview -- otherwise the mouse ends up targeting the preview itself

		renderConn = RunService.RenderStepped:Connect(function()
			if not (preview and mouse.Hit) then
				return
			end
			preview.CFrame = CFrame.new(mouse.Hit.Position + Vector3.new(0, 0.15, 0))

			local root = player.Character and player.Character:FindFirstChild("HumanoidRootPart")
			local inRange = root and (mouse.Hit.Position - root.Position).Magnitude <= MAX_DISTANCE
			preview.Color = inRange and COLOR_OK or COLOR_TOO_FAR
		end)
	end)

	local unequippedConn = tool.Unequipped:Connect(teardown)

	local activatedConn = tool.Activated:Connect(function()
		if placing or not mouse.Hit then
			return
		end
		placing = true
		local hit = mouse.Hit.Position
		pcall(function()
			placeAcampada:InvokeServer(hit.X, hit.Z)
		end)
		placing = false
	end)

	tool.Destroying:Connect(function()
		teardown()
		equippedConn:Disconnect()
		unequippedConn:Disconnect()
		activatedConn:Disconnect()
	end)
end

local function watchContainer(container)
	for _, child in ipairs(container:GetChildren()) do
		if child:IsA("Tool") and child:GetAttribute("itemId") == "acampada" then
			attachTool(child)
		end
	end
	container.ChildAdded:Connect(function(child)
		if child:IsA("Tool") and child:GetAttribute("itemId") == "acampada" then
			attachTool(child)
		end
	end)
end

function CampPlacementUI.start()
	placeAcampada = Remotes.getFunction("PlaceAcampada")

	watchContainer(player:WaitForChild("Backpack"))

	if player.Character then
		watchContainer(player.Character)
	end
	player.CharacterAdded:Connect(watchContainer)
end

return CampPlacementUI
