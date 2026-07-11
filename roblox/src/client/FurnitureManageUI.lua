-- Move/pick-up popup for already-placed camp furniture. Opens on the
-- "Manage" ProximityPrompt (key F) that server/CampFurnitureService.lua
-- attaches to every piece, alongside the chest's own "Open" prompt.
--
-- "Move": same ground-preview-follows-mouse pattern as client/
-- FurniturePlacementUI.lua, but aimed at an EXISTING piece instead of one
-- freshly pulled from a Tool — click confirms via the MoveFurniture
-- RemoteFunction, right-click/Escape cancels.
-- "Store in inventory": calls PickupFurniture directly (server rejects if
-- it's a chest that isn't empty yet).

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared:WaitForChild("Config"))
local Items = require(Shared:WaitForChild("Items"))
local Remotes = require(Shared:WaitForChild("Remotes"))
local UIKit = require(script.Parent.UIKit)

local player = Players.LocalPlayer

local FurnitureManageUI = {}

local MAX_DISTANCE = Config.Camp.maxPlacementDistance
local COLOR_OK = Color3.fromRGB(88, 156, 76)
local COLOR_TOO_FAR = Color3.fromRGB(200, 62, 70)

local moveFurniture -- RemoteFunction, resolved in start()
local pickupFurniture -- RemoteFunction

local popupGui
local movePreview, moveRenderConn, moveInputConn
local activePieceId

local function teardownMovePreview()
	if moveRenderConn then
		moveRenderConn:Disconnect()
		moveRenderConn = nil
	end
	if moveInputConn then
		moveInputConn:Disconnect()
		moveInputConn = nil
	end
	if movePreview then
		movePreview:Destroy()
		movePreview = nil
	end
end

local function closePopup()
	if popupGui then
		popupGui.Enabled = false
	end
end

-- Enters drag mode for the currently-selected piece: a translucent square
-- follows the mouse until the player left-clicks (confirm) or
-- right-clicks/Esc (cancel). Never trusted — the server re-validates
-- everything (camp access, zone bounds, distance, spacing) just like the
-- initial placement.
local function beginMove()
	local pieceId = activePieceId
	if not pieceId then
		return
	end
	closePopup()
	teardownMovePreview()

	local mouse = player:GetMouse()
	movePreview = Instance.new("Part")
	movePreview.Name = "FurnitureMovePreview"
	movePreview.Size = Vector3.new(3, 0.2, 3)
	movePreview.Anchored = true
	movePreview.CanCollide = false
	movePreview.CanQuery = false
	movePreview.Transparency = 0.6
	movePreview.Material = Enum.Material.SmoothPlastic
	movePreview.Color = COLOR_OK
	movePreview.Parent = workspace
	mouse.TargetFilter = movePreview

	moveRenderConn = RunService.RenderStepped:Connect(function()
		if not (movePreview and mouse.Hit) then
			return
		end
		movePreview.CFrame = CFrame.new(mouse.Hit.Position + Vector3.new(0, 0.15, 0))
		local root = player.Character and player.Character:FindFirstChild("HumanoidRootPart")
		local inRange = root and (mouse.Hit.Position - root.Position).Magnitude <= MAX_DISTANCE
		movePreview.Color = inRange and COLOR_OK or COLOR_TOO_FAR
	end)

	moveInputConn = UserInputService.InputBegan:Connect(function(input, gameProcessed)
		if gameProcessed then
			return
		end
		if input.UserInputType == Enum.UserInputType.MouseButton1 then
			if mouse.Hit then
				local hit = mouse.Hit.Position
				teardownMovePreview()
				task.spawn(function()
					pcall(function()
						moveFurniture:InvokeServer(pieceId, hit.X, hit.Z)
					end)
				end)
			end
		elseif input.UserInputType == Enum.UserInputType.MouseButton2 or input.KeyCode == Enum.KeyCode.Escape then
			teardownMovePreview()
		end
	end)
end

local function pickup()
	local pieceId = activePieceId
	if not pieceId then
		return
	end
	closePopup()
	task.spawn(function()
		pcall(function()
			pickupFurniture:InvokeServer(pieceId)
		end)
	end)
end

local function buildPopup()
	local gui = Instance.new("ScreenGui")
	gui.Name = "FurnitureManageUI"
	gui.ResetOnSpawn = false
	gui.Enabled = false
	gui.Parent = player:WaitForChild("PlayerGui")

	local panel = Instance.new("Frame")
	panel.Size = UDim2.new(0, 220, 0, 130)
	panel.Position = UDim2.new(0.5, 0, 0.62, 0)
	panel.AnchorPoint = Vector2.new(0.5, 0)
	panel.Parent = gui
	UIKit.stylePanel(panel)
	UIKit.autoScale(panel)

	local title = UIKit.titleBar(panel, "Furniture", 32)

	local closeBtn = UIKit.closeButton(panel, 22)
	closeBtn.Position = UDim2.new(1, -28, 0, 5)
	closeBtn.Activated:Connect(closePopup)

	local moveBtn = UIKit.primaryButton(panel, "Move")
	moveBtn.Size = UDim2.new(1, -24, 0, 36)
	moveBtn.Position = UDim2.new(0, 12, 0, 44)
	moveBtn.Parent = panel
	moveBtn.Activated:Connect(beginMove)

	local pickupBtn = UIKit.ghostButton(panel, "Store in inventory")
	pickupBtn.Size = UDim2.new(1, -24, 0, 32)
	pickupBtn.Position = UDim2.new(0, 12, 0, 88)
	pickupBtn.Parent = panel
	pickupBtn.Activated:Connect(pickup)

	popupGui = gui
	return title
end

function FurnitureManageUI.start()
	local manageRemote = Remotes.get("ManageFurniture")
	moveFurniture = Remotes.getFunction("MoveFurniture")
	pickupFurniture = Remotes.getFunction("PickupFurniture")

	local title = buildPopup()

	manageRemote.OnClientEvent:Connect(function(info)
		if typeof(info) ~= "table" or typeof(info.pieceId) ~= "number" then
			return
		end
		teardownMovePreview()
		activePieceId = info.pieceId

		local def = typeof(info.itemId) == "string" and Items.get(info.itemId)
		title.Text = def and def.name or "Furniture"

		popupGui.Enabled = true
	end)
end

return FurnitureManageUI