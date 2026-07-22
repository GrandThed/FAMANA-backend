-- Building UI (Rust-Style Building Plan Client Controller).
-- Renders preview hologram, grid snapping (6 studs), rotation (R key), piece selector, and demolition mode (X key).

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local UserInputService = game:GetService("UserInputService")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Remotes = require(Shared:WaitForChild("Remotes"))
local BuildingConfig = require(Shared:WaitForChild("BuildingConfig"))
local Theme = require(script.Parent.Theme)
local UIKit = require(script.Parent.UIKit)
local Sfx = require(script.Parent.Sfx)

local player = Players.LocalPlayer
local camera = Workspace.CurrentCamera

local BuildingUI = {}

local previewPart = nil

local function mouseWorldPoint()
	local mouseLoc = UserInputService:GetMouseLocation()
	local ray = camera:ViewportPointToRay(mouseLoc.X, mouseLoc.Y)
	local params = RaycastParams.new()
	local character = player.Character
	local filter = {}
	if character then
		table.insert(filter, character)
	end
	if previewPart then
		table.insert(filter, previewPart)
	end
	params.FilterType = Enum.RaycastFilterType.Exclude
	params.FilterDescendantsInstances = filter

	local result = Workspace:Raycast(ray.Origin, ray.Direction * 300, params)
	if result then
		return result.Position, result.Instance
	end
	return ray.Origin + ray.Direction * 50, nil
end

local PLOT_POSITIONS = {
	Vector3.new(0, 0, -100),
	Vector3.new(100, 0, 0),
	Vector3.new(0, 0, 100),
	Vector3.new(-100, 0, 0),
}

local function snapPointToGrid(point)
	local nearestPlotPos = PLOT_POSITIONS[1]
	local minDist = (point - nearestPlotPos).Magnitude
	for i = 2, #PLOT_POSITIONS do
		local d = (point - PLOT_POSITIONS[i]).Magnitude
		if d < minDist then
			minDist = d
			nearestPlotPos = PLOT_POSITIONS[i]
		end
	end

	local relX = point.X - nearestPlotPos.X
	local relZ = point.Z - nearestPlotPos.Z

	local colX = math.clamp(math.floor((relX + 24) / 12), 0, 3)
	local colZ = math.clamp(math.floor((relZ + 24) / 12), 0, 3)

	local tileCenterX = -18 + colX * 12
	local tileCenterZ = -18 + colZ * 12

	local finalX = nearestPlotPos.X + tileCenterX
	local finalZ = nearestPlotPos.Z + tileCenterZ
	local finalY = math.floor(point.Y / 5 + 0.5) * 5

	return Vector3.new(finalX, finalY, finalZ)
end

function BuildingUI.start()
	local placeRemote = Remotes.getFunction("PlaceStructure")
	local demolishRemote = Remotes.getFunction("DemolishStructure")

	local gui = Instance.new("ScreenGui")
	gui.Name = "BuildingUI"
	gui.ResetOnSpawn = false
	gui.DisplayOrder = 10
	gui.Parent = player:WaitForChild("PlayerGui")

	local bar = Instance.new("Frame")
	bar.Size = UDim2.new(0, 520, 0, 60)
	bar.Position = UDim2.new(0.5, 0, 0.88, 0)
	bar.AnchorPoint = Vector2.new(0.5, 0.5)
	bar.Visible = false
	bar.Parent = gui
	UIKit.stylePanel(bar)
	UIKit.addShadow(bar)
	UIKit.autoScale(bar)

	local hintLabel = UIKit.label(
		bar,
		"📐 PLANO DE CONSTRUCCIÓN — R: Rotar 90° | Click: Construir | X: Modo Demoler",
		12,
		Theme.Semantic.Currency,
		Theme.Font.BodyBold
	)
	hintLabel.Position = UDim2.new(0, 12, 0, 6)

	local btnContainer = Instance.new("Frame")
	btnContainer.Size = UDim2.new(1, -24, 0, 28)
	btnContainer.Position = UDim2.new(0, 12, 0, 26)
	btnContainer.BackgroundTransparency = 1
	btnContainer.Parent = bar

	local btnLayout = Instance.new("UIListLayout")
	btnLayout.FillDirection = Enum.FillDirection.Horizontal
	btnLayout.SortOrder = Enum.SortOrder.LayoutOrder
	btnLayout.Padding = UDim.new(0, 6)
	btnLayout.Parent = btnContainer

	local activePieceId = "piso_madera"
	local rotationY = 0
	local active = false
	local renderConn = nil

	local piecesOrder = { "piso_madera", "pared_madera", "puerta_madera", "pared_ventana", "techo_madera" }

	for _, pId in ipairs(piecesOrder) do
		local pDef = BuildingConfig.getPiece(pId)
		local btn = UIKit.button(
			btnContainer,
			string.format("%s %s", pDef.icon or "", pDef.name),
			11,
			Theme.Semantic.SurfaceWell,
			Theme.Semantic.TextTitle
		)
		btn.Size = UDim2.new(0, 95, 1, 0)
		btn.Activated:Connect(function()
			activePieceId = pId
			Sfx.play("uiClick")
		end)
	end

	local function cleanupPreview()
		if previewPart then
			previewPart:Destroy()
			previewPart = nil
		end
		if renderConn then
			renderConn:Disconnect()
			renderConn = nil
		end
	end

	local function startBuildingMode()
		active = true
		bar.Visible = true
		cleanupPreview()

		previewPart = Instance.new("Part")
		previewPart.Name = "BuildingHologram"
		previewPart.Color = Color3.fromRGB(0, 200, 255)
		previewPart.Material = Enum.Material.ForceField
		previewPart.Transparency = 0.4
		previewPart.CanCollide = false
		previewPart.CanQuery = false
		previewPart.CanTouch = false
		previewPart.Anchored = true
		previewPart.Parent = Workspace

		renderConn = RunService.RenderStepped:Connect(function()
			if not active or not previewPart then
				return
			end
			local point = mouseWorldPoint()
			local snappedPos = snapPointToGrid(point)
			local pDef = BuildingConfig.getPiece(activePieceId)
			if pDef then
				previewPart.Size = pDef.size
				local pos = snappedPos + (pDef.offset or Vector3.zero)
				previewPart.CFrame = CFrame.new(pos) * CFrame.Angles(0, math.rad(rotationY), 0)
			end
		end)
	end

	local function stopBuildingMode()
		active = false
		bar.Visible = false
		cleanupPreview()
	end

	-- Watch for holding plano_construccion
	RunService.Heartbeat:Connect(function()
		local character = player.Character
		local tool = character and character:FindFirstChildOfClass("Tool")
		local isHoldingPlan = tool and tool:GetAttribute("itemId") == "plano_construccion"

		if isHoldingPlan and not active then
			startBuildingMode()
		elseif not isHoldingPlan and active then
			stopBuildingMode()
		end
	end)

	UserInputService.InputBegan:Connect(function(input, gpe)
		if gpe or not active then
			return
		end

		if input.KeyCode == Enum.KeyCode.R then
			rotationY = (rotationY + 90) % 360
			Sfx.play("uiClick")
		elseif input.KeyCode == Enum.KeyCode.X then
			-- Demolish mode
			local point, targetInst = mouseWorldPoint()
			local targetModel = targetInst and targetInst:FindFirstAncestorWhichIsA("Model")
			if targetModel and targetModel:GetAttribute("PieceId") then
				demolishRemote:InvokeServer(targetModel)
				Sfx.play("spellDenied")
			end
		elseif input.UserInputType == Enum.UserInputType.MouseButton1 then
			if previewPart then
				local point = mouseWorldPoint()
				local snappedPos = snapPointToGrid(point)

				Sfx.play("equip")
				placeRemote:InvokeServer({
					pieceId = activePieceId,
					position = snappedPos,
					rotationY = rotationY,
				})
			end
		end
	end)
end

return BuildingUI
