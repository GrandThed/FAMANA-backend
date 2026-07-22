-- Ground preview + placement for camp furniture ("cofre_campamento",
-- "carpa_campamento", "crafting_table", "simple_forge", ... — see server/
-- CampFurnitureService.lua). Same pattern as client/CampPlacementUI.lua for
-- the acampada itself: the item is `type = "placeable"`, ToolService turns
-- it into a held Tool, this shows a translucent square following the mouse
-- while it's equipped and fires PlaceFurniture with the ground point on
-- click. The server re-validates everything (camp access, zone bounds,
-- distance, spacing, ownership) and never trusts this preview.
-- Success/error feedback comes back as a toast via the existing "Notify"
-- remote.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared:WaitForChild("Config"))
local Remotes = require(Shared:WaitForChild("Remotes"))

local player = Players.LocalPlayer

local FurniturePlacementUI = {}

local UserInputService = game:GetService("UserInputService")

-- itemId -> preview footprint (studs). Keep in sync with server/
-- CampFurnitureService.lua's FURNITURE_DEFS.
local FURNITURE_ITEMS = {
	cofre_campamento = { size = 3 },
	cofre_gremio = { size = 3 },
	puesto_mercado = { size = 4 },
	carpa_campamento = { size = 4 },
	crafting_table = { size = 4 },
	simple_forge = { size = 3 },
	olla_campamento = { size = 3 },
	alfombra_campamento = { size = 3 },
	farol_campamento = { size = 2 },
	trofeo_campamento = { size = 2 },
	bolsa_dormir = { size = 3 },
	cama_campamento = { size = 4 },
	silla_campamento = { size = 2 },
	banco_campamento = { size = 3 },
	mesa_investigacion_gremio = { size = 4 },
	antorcha_campamento = { size = 2 },
	hoguera_gremio = { size = 3 },
	lampara_gremio = { size = 2 },
	mesa_arquitectura_gremio = { size = 4 },
	maceta_hierbas = { size = 2 },
	letrero_bienvenida = { size = 3 },
	portal_gremio = { size = 4 },
}

local MAX_DISTANCE = Config.Camp.maxPlacementDistance

local COLOR_OK = Color3.fromRGB(88, 156, 76)
local COLOR_TOO_FAR = Color3.fromRGB(200, 62, 70)

local placeFurniture -- RemoteFunction, resolved in start()
local placing = false -- debounce: one in-flight request at a time

local function createPreview(size)
	local part = Instance.new("Part")
	part.Name = "FurniturePreview"
	part.Size = Vector3.new(size, 0.2, size)
	part.Anchored = true
	part.CanCollide = false
	part.CanQuery = false -- don't let the mouse raycast hit its own preview
	part.Transparency = 0.6
	part.Material = Enum.Material.SmoothPlastic
	part.Color = COLOR_OK
	part.Parent = workspace
	return part
end

local function attachTool(tool, itemId, previewSize)
	local mouse = player:GetMouse()
	local preview, renderConn, inputConn
	local rotationY = 0

	local function teardown()
		if renderConn then
			renderConn:Disconnect()
			renderConn = nil
		end
		if inputConn then
			inputConn:Disconnect()
			inputConn = nil
		end
		if preview then
			preview:Destroy()
			preview = nil
		end
		mouse.TargetFilter = nil
	end

	local equippedConn = tool.Equipped:Connect(function()
		preview = createPreview(previewSize)
		mouse.TargetFilter = preview -- otherwise the mouse ends up targeting the preview itself

		inputConn = UserInputService.InputBegan:Connect(function(input, gpe)
			if gpe then
				return
			end
			if input.KeyCode == Enum.KeyCode.R then
				rotationY = (rotationY + 90) % 360
			end
		end)

		renderConn = RunService.RenderStepped:Connect(function()
			if not (preview and mouse.Hit) then
				return
			end
			preview.CFrame = CFrame.new(mouse.Hit.Position + Vector3.new(0, 0.15, 0)) * CFrame.Angles(0, math.rad(rotationY), 0)

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
			placeFurniture:InvokeServer(itemId, hit.X, hit.Z, rotationY)
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
	local function maybeAttach(child)
		if not child:IsA("Tool") then
			return
		end
		local itemId = child:GetAttribute("itemId")
		local def = itemId and FURNITURE_ITEMS[itemId]
		if def then
			attachTool(child, itemId, def.size)
		end
	end

	for _, child in ipairs(container:GetChildren()) do
		maybeAttach(child)
	end
	container.ChildAdded:Connect(maybeAttach)
end

function FurniturePlacementUI.start()
	placeFurniture = Remotes.getFunction("PlaceFurniture")

	watchContainer(player:WaitForChild("Backpack"))

	if player.Character then
		watchContainer(player.Character)
	end
	player.CharacterAdded:Connect(watchContainer)
end

return FurniturePlacementUI