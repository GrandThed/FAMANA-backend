-- 20-slot inventory panel. Toggled with the I key. Pulls the initial contents
-- via RequestInventory and listens to InventoryUpdated for live changes.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local UserInputService = game:GetService("UserInputService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Items = require(Shared:WaitForChild("Items"))
local Remotes = require(Shared:WaitForChild("Remotes"))
local Config = require(Shared:WaitForChild("Config"))

local player = Players.LocalPlayer

local InventoryUI = {}

local COLUMNS = 5
local SLOT = 60
local PAD = 8

function InventoryUI.start()
	local gui = Instance.new("ScreenGui")
	gui.Name = "InventoryUI"
	gui.ResetOnSpawn = false
	gui.Enabled = false
	gui.Parent = player:WaitForChild("PlayerGui")

	local rows = math.ceil(Config.inventoryCapacity / COLUMNS)
	local width = COLUMNS * (SLOT + PAD) + PAD
	local height = rows * (SLOT + PAD) + PAD + 34

	local panel = Instance.new("Frame")
	panel.Size = UDim2.new(0, width, 0, height)
	panel.Position = UDim2.new(0.5, 0, 0.5, 0)
	panel.AnchorPoint = Vector2.new(0.5, 0.5)
	panel.BackgroundColor3 = Color3.fromRGB(25, 25, 25)
	panel.BorderSizePixel = 0
	panel.Parent = gui

	local title = Instance.new("TextLabel")
	title.Size = UDim2.new(1, 0, 0, 30)
	title.BackgroundTransparency = 1
	title.TextColor3 = Color3.new(1, 1, 1)
	title.Font = Enum.Font.GothamBold
	title.TextSize = 16
	title.Text = "Inventory  —  press I to close"
	title.Parent = panel

	local grid = Instance.new("Frame")
	grid.Size = UDim2.new(1, 0, 1, -34)
	grid.Position = UDim2.new(0, 0, 0, 34)
	grid.BackgroundTransparency = 1
	grid.Parent = panel

	local slots = {}
	for i = 0, Config.inventoryCapacity - 1 do
		local col = i % COLUMNS
		local row = math.floor(i / COLUMNS)

		local slot = Instance.new("Frame")
		slot.Size = UDim2.new(0, SLOT, 0, SLOT)
		slot.Position = UDim2.new(0, PAD + col * (SLOT + PAD), 0, PAD + row * (SLOT + PAD))
		slot.BackgroundColor3 = Color3.fromRGB(45, 45, 45)
		slot.BorderSizePixel = 0
		slot.Parent = grid

		local name = Instance.new("TextLabel")
		name.Size = UDim2.new(1, -6, 1, -16)
		name.Position = UDim2.new(0, 3, 0, 2)
		name.BackgroundTransparency = 1
		name.TextColor3 = Color3.new(1, 1, 1)
		name.Font = Enum.Font.Gotham
		name.TextSize = 11
		name.TextWrapped = true
		name.TextYAlignment = Enum.TextYAlignment.Top
		name.Text = ""
		name.Parent = slot

		local qty = Instance.new("TextLabel")
		qty.Size = UDim2.new(1, -6, 0, 14)
		qty.Position = UDim2.new(0, 3, 1, -15)
		qty.BackgroundTransparency = 1
		qty.TextColor3 = Color3.fromRGB(255, 220, 120)
		qty.Font = Enum.Font.GothamBold
		qty.TextXAlignment = Enum.TextXAlignment.Right
		qty.TextSize = 13
		qty.Text = ""
		qty.Parent = slot

		slots[i] = { name = name, qty = qty }
	end

	local function render(inventory)
		for i = 0, Config.inventoryCapacity - 1 do
			slots[i].name.Text = ""
			slots[i].qty.Text = ""
		end
		if typeof(inventory) ~= "table" then
			return
		end
		for _, entry in ipairs(inventory) do
			local slot = slots[entry.slotIndex]
			if slot then
				local def = Items.get(entry.itemId)
				slot.name.Text = def and def.name or entry.itemId
				slot.qty.Text = entry.quantity > 1 and tostring(entry.quantity) or ""
			end
		end
	end

	local inventoryUpdated = Remotes.get("InventoryUpdated")
	local requestInventory = Remotes.getFunction("RequestInventory")

	inventoryUpdated.OnClientEvent:Connect(render)

	task.spawn(function()
		local ok, inventory = pcall(function()
			return requestInventory:InvokeServer()
		end)
		if ok then
			render(inventory)
		end
	end)

	UserInputService.InputBegan:Connect(function(input, gameProcessed)
		if gameProcessed then
			return
		end
		if input.KeyCode == Enum.KeyCode.I then
			gui.Enabled = not gui.Enabled
		end
	end)
end

return InventoryUI
