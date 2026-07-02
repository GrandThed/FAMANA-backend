-- 20-slot inventory panel. Toggled with the I key. Pulls the initial contents
-- via RequestInventory and listens to InventoryUpdated for live changes.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local UserInputService = game:GetService("UserInputService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Items = require(Shared:WaitForChild("Items"))
local Remotes = require(Shared:WaitForChild("Remotes"))
local Config = require(Shared:WaitForChild("Config"))
local ClientState = require(script.Parent.ClientState)

local player = Players.LocalPlayer

local InventoryUI = {}

local COLUMNS = 5
local SLOT = 60
local PAD = 8

function InventoryUI.start()
	local gui = Instance.new("ScreenGui")
	gui.Name = "InventoryUI"
	gui.ResetOnSpawn = false
	gui.Enabled = true -- always on; we toggle the panel's Visibility instead
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
	panel.Visible = false -- hidden until the button or I key opens it
	panel.Parent = gui

	local title = Instance.new("TextLabel")
	title.Size = UDim2.new(1, -34, 0, 30)
	title.BackgroundTransparency = 1
	title.TextColor3 = Color3.new(1, 1, 1)
	title.Font = Enum.Font.GothamBold
	title.TextSize = 16
	title.Text = "Inventory"
	title.Parent = panel

	-- Close (X) button in the panel's top-right corner.
	local closeBtn = Instance.new("TextButton")
	closeBtn.Size = UDim2.new(0, 30, 0, 30)
	closeBtn.Position = UDim2.new(1, -2, 0, 2)
	closeBtn.AnchorPoint = Vector2.new(1, 0)
	closeBtn.BackgroundColor3 = Color3.fromRGB(180, 60, 60)
	closeBtn.BorderSizePixel = 0
	closeBtn.Font = Enum.Font.GothamBold
	closeBtn.TextSize = 16
	closeBtn.TextColor3 = Color3.new(1, 1, 1)
	closeBtn.Text = "X"
	closeBtn.Parent = panel

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

	local function toggle()
		panel.Visible = not panel.Visible
		-- Free the cursor (via ShiftLockController) while the panel is open.
		ClientState.inventoryOpen = panel.Visible
	end

	-- Always-visible button to open/close the inventory (works regardless of
	-- keyboard focus, unlike the I key).
	local openBtn = Instance.new("TextButton")
	openBtn.Name = "InventoryButton"
	openBtn.Size = UDim2.new(0, 120, 0, 34)
	openBtn.Position = UDim2.new(1, -16, 1, -16)
	openBtn.AnchorPoint = Vector2.new(1, 1)
	openBtn.BackgroundColor3 = Color3.fromRGB(60, 90, 160)
	openBtn.BorderSizePixel = 0
	openBtn.Font = Enum.Font.GothamBold
	openBtn.TextSize = 15
	openBtn.TextColor3 = Color3.new(1, 1, 1)
	openBtn.Text = "Inventory (I)"
	openBtn.Parent = gui

	openBtn.Activated:Connect(toggle)
	closeBtn.Activated:Connect(toggle)

	-- Keep the I key too (works once the game viewport has focus).
	UserInputService.InputBegan:Connect(function(input, gameProcessed)
		if gameProcessed then
			return
		end
		if input.KeyCode == Enum.KeyCode.I then
			toggle()
		end
	end)

	-- Wire up the remotes in the background so a slow/missing server can never
	-- block the keybind above.
	task.spawn(function()
		local inventoryUpdated = Remotes.get("InventoryUpdated")
		inventoryUpdated.OnClientEvent:Connect(render)

		local requestInventory = Remotes.getFunction("RequestInventory")
		local ok, inventory = pcall(function()
			return requestInventory:InvokeServer()
		end)
		if ok then
			render(inventory)
		end
	end)
end

return InventoryUI
