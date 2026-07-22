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
	Vector3.new(2000, 0, 1900),
	Vector3.new(2100, 0, 2000),
	Vector3.new(2000, 0, 2100),
	Vector3.new(1900, 0, 2000),
}

local function snapPointToGrid(point, pieceId, manualRotationY)
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
	local autoRotY = manualRotationY or 0

	local pDef = BuildingConfig.getPiece(pieceId)
	local isWall = pDef and (pieceId:find("pared") or pieceId:find("puerta") or pieceId:find("valla"))

	if isWall then
		local dx = point.X - finalX
		local dz = point.Z - finalZ

		if math.abs(dx) > math.abs(dz) then
			-- Closer to East or West edge of tile
			if dx > 0 then
				finalX += 6
			else
				finalX -= 6
			end
			autoRotY = (manualRotationY == 90 or manualRotationY == 270) and 0 or 90
		else
			-- Closer to North or South edge of tile
			if dz > 0 then
				finalZ += 6
			else
				finalZ -= 6
			end
			autoRotY = (manualRotationY == 90 or manualRotationY == 270) and 90 or 0
		end
	end

	return Vector3.new(finalX, finalY, finalZ), autoRotY
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
	bar.Size = UDim2.new(0, 740, 0, 84)
	bar.Position = UDim2.new(0.5, 0, 0.88, 0)
	bar.AnchorPoint = Vector2.new(0.5, 0.5)
	bar.Visible = false
	bar.Parent = gui
	UIKit.stylePanel(bar)
	UIKit.addShadow(bar)
	UIKit.autoScale(bar)

	local hintLabel = UIKit.label(
		bar,
		"📐 PLANO DE CONSTRUCCIÓN — [R] Rotar 90° | [Click] Construir | [X] Demoler",
		12,
		Theme.Semantic.Currency,
		Theme.Font.BodyBold
	)
	hintLabel.Size = UDim2.new(1, -28, 0, 18)
	hintLabel.Position = UDim2.new(0, 14, 0, 5)
	hintLabel.TextXAlignment = Enum.TextXAlignment.Left

	local btnContainer = Instance.new("Frame")
	btnContainer.Size = UDim2.new(1, -28, 0, 52)
	btnContainer.Position = UDim2.new(0, 14, 0, 24)
	btnContainer.BackgroundTransparency = 1
	btnContainer.Parent = bar

	local btnLayout = Instance.new("UIListLayout")
	btnLayout.FillDirection = Enum.FillDirection.Horizontal
	btnLayout.SortOrder = Enum.SortOrder.LayoutOrder
	btnLayout.Padding = UDim.new(0, 6)
	btnLayout.Parent = btnContainer

	local activePieceId = "piso_madera"
	local selectedMaterial = "wood"
	local isDemolishMode = false
	local rotationY = 0
	local active = false
	local renderConn = nil

	local piecesByMaterial = {
		wood = { "piso_madera", "pared_madera", "puerta_madera", "pared_ventana", "valla_madera", "techo_madera" },
		stone = { "piso_piedra", "pared_piedra", "puerta_piedra", "pared_ventana_piedra", "valla_piedra", "techo_piedra" },
	}

	local cardButtons = {}

	-- Material Tab Switchers
	local tabWood = Instance.new("TextButton")
	tabWood.Size = UDim2.new(0, 85, 0, 18)
	tabWood.Position = UDim2.new(1, -180, 0, 4)
	tabWood.BackgroundColor3 = Theme.Semantic.PanelTop
	tabWood.TextColor3 = Theme.Semantic.Currency
	tabWood.Text = "🪵 Madera"
	tabWood.Font = Enum.Font.SourceSansBold
	tabWood.TextSize = 11
	tabWood.BorderSizePixel = 0
	tabWood.Parent = bar

	local tabStone = Instance.new("TextButton")
	tabStone.Size = UDim2.new(0, 85, 0, 18)
	tabStone.Position = UDim2.new(1, -90, 0, 4)
	tabStone.BackgroundColor3 = Theme.Semantic.SurfaceWell
	tabStone.TextColor3 = Theme.Semantic.TextSecondary
	tabStone.Text = "🪨 Piedra"
	tabStone.Font = Enum.Font.SourceSansBold
	tabStone.TextSize = 11
	tabStone.BorderSizePixel = 0
	tabStone.Parent = bar

	local function updateCardSelections()
		for pId, cardData in pairs(cardButtons) do
			local isSelected = (not isDemolishMode and activePieceId == pId)
			cardData.stroke.Color = isSelected and Theme.Semantic.Currency or Theme.Semantic.BorderPanel
			cardData.stroke.Thickness = isSelected and 2 or 1
			cardData.frame.BackgroundColor3 = isSelected and Theme.Semantic.PanelTop or Theme.Semantic.SurfaceWell
		end
	end

	local function renderPieceCards()
		for _, child in ipairs(btnContainer:GetChildren()) do
			if child:IsA("TextButton") then
				child:Destroy()
			end
		end
		cardButtons = {}

		tabWood.BackgroundColor3 = selectedMaterial == "wood" and Theme.Semantic.PanelTop or Theme.Semantic.SurfaceWell
		tabWood.TextColor3 = selectedMaterial == "wood" and Theme.Semantic.Currency or Theme.Semantic.TextSecondary
		tabStone.BackgroundColor3 = selectedMaterial == "stone" and Theme.Semantic.PanelTop or Theme.Semantic.SurfaceWell
		tabStone.TextColor3 = selectedMaterial == "stone" and Theme.Semantic.Currency or Theme.Semantic.TextSecondary

		local piecesOrder = piecesByMaterial[selectedMaterial]
		for i, pId in ipairs(piecesOrder) do
			local pDef = BuildingConfig.getPiece(pId)
			local costText = "🪵 4 Madera"
			if pDef and pDef.cost then
				if pDef.cost.wood then
					costText = string.format("🪵 %d Madera", pDef.cost.wood)
				elseif pDef.cost.stone then
					costText = string.format("🪨 %d Piedra", pDef.cost.stone)
				end
			end

			local card = Instance.new("TextButton")
			card.Size = UDim2.new(0, 102, 1, 0)
			card.BackgroundColor3 = Theme.Semantic.SurfaceWell
			card.BorderSizePixel = 0
			card.AutoButtonColor = false
			card.Text = ""
			card.LayoutOrder = i
			card.Parent = btnContainer

			local stroke = Instance.new("UIStroke")
			stroke.Thickness = 1
			stroke.Color = Theme.Semantic.BorderPanel
			stroke.Parent = card

			local cleanName = pDef.name:gsub(" de Madera", ""):gsub(" de Piedra", ""):gsub(" con ", " ")
			local titleLabel = UIKit.label(
				card,
				string.format("%s %s", pDef.icon or "", cleanName),
				11,
				Theme.Semantic.TextTitle,
				Theme.Font.BodyBold
			)
			titleLabel.Size = UDim2.new(1, 0, 0, 24)
			titleLabel.Position = UDim2.new(0, 0, 0, 4)
			titleLabel.TextXAlignment = Enum.TextXAlignment.Center

			local costLabel = UIKit.label(card, costText, 10, Theme.Semantic.TextSecondary)
			costLabel.Size = UDim2.new(1, 0, 0, 18)
			costLabel.Position = UDim2.new(0, 0, 0, 28)
			costLabel.TextXAlignment = Enum.TextXAlignment.Center

			cardButtons[pId] = { frame = card, stroke = stroke }

			card.Activated:Connect(function()
				isDemolishMode = false
				activePieceId = pId
				updateCardSelections()
				Sfx.play("uiClick")
			end)
		end

		-- Demolish Mode Card
		local demoCard = Instance.new("TextButton")
		demoCard.Size = UDim2.new(0, 102, 1, 0)
		demoCard.BackgroundColor3 = isDemolishMode and Color3.fromRGB(140, 30, 30) or Color3.fromRGB(80, 20, 20)
		demoCard.BorderSizePixel = 0
		demoCard.AutoButtonColor = false
		demoCard.Text = ""
		demoCard.LayoutOrder = 6
		demoCard.Parent = btnContainer

		local demoStroke = Instance.new("UIStroke")
		demoStroke.Thickness = 1
		demoStroke.Color = Color3.fromRGB(220, 60, 60)
		demoStroke.Parent = demoCard

		local demoLabel = UIKit.label(demoCard, "🔴 Demoler", 11, Color3.fromRGB(255, 200, 200), Theme.Font.BodyBold)
		demoLabel.Size = UDim2.new(1, 0, 0, 24)
		demoLabel.Position = UDim2.new(0, 0, 0, 4)
		demoLabel.TextXAlignment = Enum.TextXAlignment.Center

		local demoSub = UIKit.label(demoCard, "Reembolso 50%", 10, Color3.fromRGB(255, 160, 160))
		demoSub.Size = UDim2.new(1, 0, 0, 18)
		demoSub.Position = UDim2.new(0, 0, 0, 28)
		demoSub.TextXAlignment = Enum.TextXAlignment.Center

		demoCard.Activated:Connect(function()
			isDemolishMode = not isDemolishMode
			demoCard.BackgroundColor3 = isDemolishMode and Color3.fromRGB(140, 30, 30) or Color3.fromRGB(80, 20, 20)
			updateCardSelections()
			Sfx.play("uiClick")
		end)

		updateCardSelections()
	end

	tabWood.Activated:Connect(function()
		selectedMaterial = "wood"
		activePieceId = piecesByMaterial.wood[1]
		renderPieceCards()
		Sfx.play("uiClick")
	end)

	tabStone.Activated:Connect(function()
		selectedMaterial = "stone"
		activePieceId = piecesByMaterial.stone[1]
		renderPieceCards()
		Sfx.play("uiClick")
	end)

	renderPieceCards()

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
			local snappedPos, calcRotY = snapPointToGrid(point, activePieceId, rotationY)
			local pDef = BuildingConfig.getPiece(activePieceId)
			if pDef then
				previewPart.Size = pDef.size
				local pos = snappedPos + (pDef.offset or Vector3.zero)
				previewPart.CFrame = CFrame.new(pos) * CFrame.Angles(0, math.rad(calcRotY), 0)
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
				local snappedPos, calcRotY = snapPointToGrid(point, activePieceId, rotationY)

				Sfx.play("equip")
				placeRemote:InvokeServer({
					pieceId = activePieceId,
					position = snappedPos,
					rotationY = calcRotY,
				})
			end
		end
	end)
end

return BuildingUI
