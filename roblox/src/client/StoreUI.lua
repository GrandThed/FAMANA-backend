-- Vendor store panel. Opens when the server fires OpenStore (vendor
-- ProximityPrompt) and trades through the StoreTrade RemoteFunction — the
-- server validates everything; this UI just previews prices and owned
-- counts. Buy tab lists the store's buyable trades, Sell tab the sellable
-- ones with how many the player holds (main grid only). Shift-click trades
-- five at a time for stackables.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local UserInputService = game:GetService("UserInputService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Items = require(Shared:WaitForChild("Items"))
local Stores = require(Shared:WaitForChild("Stores"))
local ItemModels = require(Shared:WaitForChild("ItemModels"))
local Remotes = require(Shared:WaitForChild("Remotes"))

local player = Players.LocalPlayer

local StoreUI = {}

local COLORS = {
	panel = Color3.fromRGB(25, 25, 28),
	section = Color3.fromRGB(33, 33, 38),
	line = Color3.fromRGB(48, 48, 55),
	tile = Color3.fromRGB(52, 52, 62),
	accent = Color3.fromRGB(60, 90, 160),
	bad = Color3.fromRGB(200, 70, 60),
	gold = Color3.fromRGB(255, 220, 120),
	text = Color3.fromRGB(235, 235, 240),
	textDim = Color3.fromRGB(150, 150, 160),
}

local ERROR_TEXT = {
	no_gold = "Not enough gold",
	no_space = "Not enough room in your inventory",
	no_items = "You don't have that many",
	too_far = "Too far from the vendor",
	not_traded = "That item isn't traded here",
	bad_request = "Something went wrong",
}

local PANEL_W = 380
local PANEL_H = 470
local ROW_H = 46
local SHIFT_QUANTITY = 5

local function makeLabel(parent, text, size, color)
	local label = Instance.new("TextLabel")
	label.BackgroundTransparency = 1
	label.Font = Enum.Font.GothamBold
	label.TextSize = size
	label.TextColor3 = color or COLORS.text
	label.Text = text
	label.Parent = parent
	return label
end

function StoreUI.start()
	local gui = Instance.new("ScreenGui")
	gui.Name = "StoreUI"
	gui.ResetOnSpawn = false
	gui.Enabled = true
	gui.Parent = player:WaitForChild("PlayerGui")

	local panel = Instance.new("Frame")
	panel.Size = UDim2.new(0, PANEL_W, 0, PANEL_H)
	panel.Position = UDim2.new(0.72, 0, 0.5, 0)
	panel.AnchorPoint = Vector2.new(0.5, 0.5)
	panel.BackgroundColor3 = COLORS.panel
	panel.BorderSizePixel = 0
	panel.Visible = false
	panel.Parent = gui

	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0, 10)
	corner.Parent = panel

	local title = makeLabel(panel, "", 16)
	title.Size = UDim2.new(1, -80, 0, 30)
	title.Position = UDim2.new(0, 12, 0, 4)
	title.TextXAlignment = Enum.TextXAlignment.Left

	local vendorLabel = makeLabel(panel, "", 12, COLORS.textDim)
	vendorLabel.Size = UDim2.new(1, -80, 0, 16)
	vendorLabel.Position = UDim2.new(0, 12, 0, 30)
	vendorLabel.TextXAlignment = Enum.TextXAlignment.Left

	local closeBtn = Instance.new("TextButton")
	closeBtn.Size = UDim2.new(0, 30, 0, 30)
	closeBtn.Position = UDim2.new(1, -6, 0, 6)
	closeBtn.AnchorPoint = Vector2.new(1, 0)
	closeBtn.BackgroundColor3 = Color3.fromRGB(180, 60, 60)
	closeBtn.BorderSizePixel = 0
	closeBtn.Font = Enum.Font.GothamBold
	closeBtn.TextSize = 16
	closeBtn.TextColor3 = Color3.new(1, 1, 1)
	closeBtn.Text = "X"
	closeBtn.Parent = panel

	-- ---- tabs ----------------------------------------------------------------
	local tabs = Instance.new("Frame")
	tabs.Size = UDim2.new(1, -24, 0, 30)
	tabs.Position = UDim2.new(0, 12, 0, 52)
	tabs.BackgroundTransparency = 1
	tabs.Parent = panel

	local function makeTab(text, x)
		local btn = Instance.new("TextButton")
		btn.Size = UDim2.new(0.5, -4, 1, 0)
		btn.Position = UDim2.new(x, x == 0 and 0 or 4, 0, 0)
		btn.BackgroundColor3 = COLORS.section
		btn.BorderSizePixel = 0
		btn.Font = Enum.Font.GothamBold
		btn.TextSize = 14
		btn.TextColor3 = COLORS.text
		btn.Text = text
		btn.Parent = tabs
		local btnCorner = Instance.new("UICorner")
		btnCorner.CornerRadius = UDim.new(0, 6)
		btnCorner.Parent = btn
		return btn
	end

	local buyTab = makeTab("Buy", 0)
	local sellTab = makeTab("Sell", 0.5)

	-- ---- rows ------------------------------------------------------------------
	local list = Instance.new("ScrollingFrame")
	list.Size = UDim2.new(1, -24, 1, -(52 + 38 + 66))
	list.Position = UDim2.new(0, 12, 0, 90)
	list.BackgroundColor3 = COLORS.section
	list.BorderSizePixel = 0
	list.ScrollBarThickness = 6
	list.AutomaticCanvasSize = Enum.AutomaticSize.Y
	list.CanvasSize = UDim2.new(0, 0, 0, 0)
	list.Parent = panel

	local listCorner = Instance.new("UICorner")
	listCorner.CornerRadius = UDim.new(0, 8)
	listCorner.Parent = list

	local layout = Instance.new("UIListLayout")
	layout.SortOrder = Enum.SortOrder.LayoutOrder
	layout.Padding = UDim.new(0, 4)
	layout.Parent = list

	local listPadding = Instance.new("UIPadding")
	listPadding.PaddingTop = UDim.new(0, 6)
	listPadding.PaddingLeft = UDim.new(0, 6)
	listPadding.PaddingRight = UDim.new(0, 6)
	listPadding.PaddingBottom = UDim.new(0, 6)
	listPadding.Parent = list

	-- ---- footer: gold, status, hint -------------------------------------------
	local goldLabel = makeLabel(panel, "Gold: 0", 14, COLORS.gold)
	goldLabel.Size = UDim2.new(0.5, -12, 0, 20)
	goldLabel.Position = UDim2.new(0, 12, 1, -56)
	goldLabel.TextXAlignment = Enum.TextXAlignment.Left

	local hintLabel = makeLabel(panel, "Shift-click: x" .. SHIFT_QUANTITY, 11, COLORS.textDim)
	hintLabel.Size = UDim2.new(0.5, -12, 0, 20)
	hintLabel.Position = UDim2.new(0.5, 0, 1, -56)
	hintLabel.TextXAlignment = Enum.TextXAlignment.Right

	local statusLabel = makeLabel(panel, "", 12, COLORS.bad)
	statusLabel.Size = UDim2.new(1, -24, 0, 24)
	statusLabel.Position = UDim2.new(0, 12, 1, -32)
	statusLabel.TextXAlignment = Enum.TextXAlignment.Left

	-- ---- state -----------------------------------------------------------------
	local current = nil -- { storeId, storeName, vendorName }
	local tab = "buy"
	local busy = false
	local inventory = {}

	local storeTrade = Remotes.getFunction("StoreTrade")

	local function countOwned(itemId)
		local total = 0
		for _, entry in ipairs(inventory) do
			if entry.containerId == "main" and entry.itemId == itemId then
				total += entry.quantity
			end
		end
		return total
	end

	local function updateGold()
		goldLabel.Text = "Gold: " .. tostring(player:GetAttribute("Gold") or 0)
	end
	player:GetAttributeChangedSignal("Gold"):Connect(updateGold)
	updateGold()

	local refresh -- forward declaration; row buttons re-render after a trade

	local function doTrade(action, itemId)
		if busy or not current then
			return
		end
		busy = true
		statusLabel.Text = ""
		local def = Items.get(itemId)
		local quantity = 1
		if def and def.stackable and UserInputService:IsKeyDown(Enum.KeyCode.LeftShift) then
			quantity = SHIFT_QUANTITY
		end
		local result = storeTrade:InvokeServer({
			storeId = current.storeId,
			action = action,
			itemId = itemId,
			quantity = quantity,
		})
		busy = false
		if typeof(result) ~= "table" or not result.ok then
			local code = typeof(result) == "table" and result.error or nil
			statusLabel.Text = ERROR_TEXT[code] or ERROR_TEXT.bad_request
		end
		-- Success needs no local bookkeeping: the server pushes InventoryUpdated
		-- and the Gold attribute, which re-render the rows and footer.
	end

	local function makeRow(order, trade, price, action)
		local def = Items.get(trade.itemId)
		local name = def and def.name or trade.itemId

		local row = Instance.new("Frame")
		row.Size = UDim2.new(1, 0, 0, ROW_H)
		row.BackgroundColor3 = COLORS.tile
		row.BorderSizePixel = 0
		row.LayoutOrder = order
		row.Parent = list

		local rowCorner = Instance.new("UICorner")
		rowCorner.CornerRadius = UDim.new(0, 6)
		rowCorner.Parent = row

		local thumbHolder = Instance.new("Frame")
		thumbHolder.Size = UDim2.new(0, ROW_H - 6, 0, ROW_H - 6)
		thumbHolder.Position = UDim2.new(0, 3, 0, 3)
		thumbHolder.BackgroundColor3 = COLORS.section
		thumbHolder.BorderSizePixel = 0
		thumbHolder.Parent = row
		local thumbCorner = Instance.new("UICorner")
		thumbCorner.CornerRadius = UDim.new(0, 6)
		thumbCorner.Parent = thumbHolder

		local thumb = Instance.new("ViewportFrame")
		thumb.Size = UDim2.new(1, -4, 1, -4)
		thumb.Position = UDim2.new(0, 2, 0, 2)
		thumb.BackgroundTransparency = 1
		thumb.Ambient = Color3.fromRGB(180, 180, 190)
		thumb.LightColor = Color3.new(1, 1, 1)
		thumb.Parent = thumbHolder
		ItemModels.preview(thumb, trade.itemId)

		local nameLabel = makeLabel(row, name, 13)
		nameLabel.Size = UDim2.new(1, -(ROW_H + 150), 0, 18)
		nameLabel.Position = UDim2.new(0, ROW_H + 4, 0, action == "sell" and 5 or 14)
		nameLabel.TextXAlignment = Enum.TextXAlignment.Left
		nameLabel.TextTruncate = Enum.TextTruncate.AtEnd

		local owned = 0
		if action == "sell" then
			owned = countOwned(trade.itemId)
			local ownedLabel = makeLabel(row, "You have " .. owned, 11, COLORS.textDim)
			ownedLabel.Size = UDim2.new(1, -(ROW_H + 150), 0, 14)
			ownedLabel.Position = UDim2.new(0, ROW_H + 4, 0, 24)
			ownedLabel.TextXAlignment = Enum.TextXAlignment.Left
		end

		local priceLabel = makeLabel(row, price .. "g", 13, COLORS.gold)
		priceLabel.Size = UDim2.new(0, 60, 1, 0)
		priceLabel.Position = UDim2.new(1, -140, 0, 0)
		priceLabel.TextXAlignment = Enum.TextXAlignment.Right

		local actionBtn = Instance.new("TextButton")
		actionBtn.Size = UDim2.new(0, 64, 0, 28)
		actionBtn.Position = UDim2.new(1, -8, 0.5, 0)
		actionBtn.AnchorPoint = Vector2.new(1, 0.5)
		actionBtn.BorderSizePixel = 0
		actionBtn.Font = Enum.Font.GothamBold
		actionBtn.TextSize = 13
		actionBtn.TextColor3 = COLORS.text
		actionBtn.Text = action == "buy" and "Buy" or "Sell"
		actionBtn.Parent = row
		local actionCorner = Instance.new("UICorner")
		actionCorner.CornerRadius = UDim.new(0, 6)
		actionCorner.Parent = actionBtn

		local enabled = action == "buy" or owned > 0
		actionBtn.BackgroundColor3 = enabled and COLORS.accent or COLORS.line
		actionBtn.AutoButtonColor = enabled
		if enabled then
			actionBtn.MouseButton1Click:Connect(function()
				doTrade(action, trade.itemId)
			end)
		end
	end

	refresh = function()
		for _, child in ipairs(list:GetChildren()) do
			if child:IsA("Frame") then
				child:Destroy()
			end
		end
		if not current then
			return
		end
		local store = Stores.get(current.storeId)
		if not store then
			statusLabel.Text = "Store unavailable"
			return
		end
		buyTab.BackgroundColor3 = tab == "buy" and COLORS.accent or COLORS.section
		sellTab.BackgroundColor3 = tab == "sell" and COLORS.accent or COLORS.section
		local order = 0
		for _, trade in ipairs(store.trades) do
			local price = tab == "buy" and trade.buyPrice or trade.sellPrice
			if price then
				order += 1
				makeRow(order, trade, price, tab)
			end
		end
	end

	local function setTab(name)
		tab = name
		statusLabel.Text = ""
		refresh()
	end
	buyTab.MouseButton1Click:Connect(function()
		setTab("buy")
	end)
	sellTab.MouseButton1Click:Connect(function()
		setTab("sell")
	end)

	local function close()
		current = nil
		panel.Visible = false
	end
	closeBtn.MouseButton1Click:Connect(close)

	Remotes.get("OpenStore").OnClientEvent:Connect(function(info)
		if typeof(info) ~= "table" then
			return
		end
		current = info
		tab = "buy"
		title.Text = info.storeName or "Store"
		vendorLabel.Text = info.vendorName or ""
		statusLabel.Text = ""
		panel.Visible = true
		refresh()
	end)

	-- Sell counts come from the same push the inventory screen uses.
	Remotes.get("InventoryUpdated").OnClientEvent:Connect(function(entries)
		inventory = entries or {}
		if current and tab == "sell" then
			refresh()
		end
	end)
	task.spawn(function()
		local entries = Remotes.getFunction("RequestInventory"):InvokeServer()
		if typeof(entries) == "table" and #inventory == 0 then
			inventory = entries
		end
	end)
end

return StoreUI
