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
local Rarity = require(Shared:WaitForChild("Rarity"))
local Remotes = require(Shared:WaitForChild("Remotes"))
local Theme = require(script.Parent.Theme)
local UIKit = require(script.Parent.UIKit)

local player = Players.LocalPlayer

local StoreUI = {}

-- Aethelgard palette (client/Theme.lua).
local COLORS = {
	panel = Theme.Semantic.PanelTop,
	section = Theme.Semantic.SurfaceWell,
	line = Theme.Semantic.BorderHair,
	tile = Theme.Color.Ink900,
	accent = Theme.Color.Ember500,
	bad = Theme.Semantic.Danger,
	gold = Theme.Semantic.Currency,
	text = Theme.Semantic.TextBody,
	textDim = Theme.Semantic.TextMuted,
}

local ERROR_TEXT = {
	no_gold = "Not enough gold",
	no_space = "Not enough room in your inventory",
	no_items = "You don't have that many",
	too_far = "Too far from the vendor",
	not_traded = "That item isn't traded here",
	bad_request = "Something went wrong",
}

local PANEL_W = 620 -- two columns: trade list left, detail pane right (§8)
local PANEL_H = 470
local LIST_W = 296
local ROW_H = 46
local SHIFT_QUANTITY = 5

local function makeLabel(parent, text, size, color, font)
	local label = Instance.new("TextLabel")
	label.BackgroundTransparency = 1
	label.FontFace = font or Theme.Font.BodyBold
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
	panel.Visible = false
	panel.Parent = gui
	UIKit.stylePanel(panel)
	UIKit.addShadow(panel)
	UIKit.autoScale(panel)

	local title = makeLabel(panel, "", Theme.Text.Title, Theme.Semantic.TextTitle, Theme.Font.DisplayBold)
	title.Size = UDim2.new(1, -80, 0, 30)
	title.Position = UDim2.new(0, 12, 0, 4)
	title.TextXAlignment = Enum.TextXAlignment.Left

	local vendorLabel = makeLabel(panel, "", 12, COLORS.textDim, Theme.Font.Body)
	vendorLabel.Size = UDim2.new(1, -80, 0, 16)
	vendorLabel.Position = UDim2.new(0, 12, 0, 30)
	vendorLabel.TextXAlignment = Enum.TextXAlignment.Left

	local closeBtn = UIKit.closeButton(panel)
	closeBtn.Position = UDim2.new(1, -6, 0, 6)
	closeBtn.AnchorPoint = Vector2.new(1, 0)

	-- ---- tabs (over the list column) --------------------------------------------
	local tabs = Instance.new("Frame")
	tabs.Size = UDim2.new(0, LIST_W, 0, 30)
	tabs.Position = UDim2.new(0, 12, 0, 52)
	tabs.BackgroundTransparency = 1
	tabs.Parent = panel

	local function makeTab(text, x)
		local btn = Instance.new("TextButton")
		btn.Size = UDim2.new(0.5, -4, 1, 0)
		btn.Position = UDim2.new(x, x == 0 and 0 or 4, 0, 0)
		btn.BackgroundColor3 = COLORS.section
		btn.BorderSizePixel = 0
		btn.AutoButtonColor = false
		btn.FontFace = Theme.Font.DisplayBold
		btn.TextSize = Theme.Text.Lg
		btn.TextColor3 = COLORS.text
		btn.Text = text
		btn.Parent = tabs
		local btnStroke = Instance.new("UIStroke")
		btnStroke.Thickness = 1
		btnStroke.Color = Theme.Semantic.BorderMuted
		btnStroke.Parent = btn
		return btn
	end

	local buyTab = makeTab("Buy", 0)
	local sellTab = makeTab("Sell", 0.5)

	-- ---- rows (left column) -------------------------------------------------------
	local list = Instance.new("ScrollingFrame")
	list.Size = UDim2.new(0, LIST_W, 1, -(52 + 38 + 66))
	list.Position = UDim2.new(0, 12, 0, 90)
	list.BackgroundColor3 = COLORS.section
	list.BorderSizePixel = 0
	list.ScrollBarThickness = 6
	list.AutomaticCanvasSize = Enum.AutomaticSize.Y
	list.CanvasSize = UDim2.new(0, 0, 0, 0)
	list.Parent = panel

	local listStroke = Instance.new("UIStroke")
	listStroke.Thickness = 1
	listStroke.Color = Theme.Semantic.BorderHair
	listStroke.Parent = list

	-- ---- detail pane (right column: big preview + price + the action) -------------
	local detail = Instance.new("Frame")
	detail.Position = UDim2.new(0, LIST_W + 24, 0, 52)
	detail.Size = UDim2.new(1, -(LIST_W + 36), 1, -(52 + 66))
	detail.BackgroundColor3 = COLORS.section
	detail.BorderSizePixel = 0
	detail.Parent = panel

	local detailStroke = Instance.new("UIStroke")
	detailStroke.Thickness = 1
	detailStroke.Color = Theme.Semantic.BorderHair
	detailStroke.Parent = detail

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
	local goldLabel = makeLabel(panel, "◈ 0 Gold", 14, COLORS.gold)
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
	local selected -- itemId focused in the detail pane

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
		goldLabel.Text = ("◈ %d Gold"):format(player:GetAttribute("Gold") or 0)
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

	-- ---- detail pane rendering -----------------------------------------------
	local function detailText(text, size, color, font)
		local label = makeLabel(detail, text, size, color, font)
		label.TextXAlignment = Enum.TextXAlignment.Left
		return label
	end

	-- Rebuilds the right column for the focused trade: big rarity-framed
	-- preview, name, owned count (sell), price and the one action button.
	local function renderDetail()
		for _, child in ipairs(detail:GetChildren()) do
			if child:IsA("GuiObject") then
				child:Destroy()
			end
		end
		local store = current and Stores.get(current.storeId)
		local trade
		if store and selected then
			for _, candidate in ipairs(store.trades) do
				if candidate.itemId == selected then
					trade = candidate
					break
				end
			end
		end
		local price = trade and (tab == "buy" and trade.buyPrice or trade.sellPrice)
		if not trade or not price then
			local hint = detailText("Select an item", Theme.Text.Body, COLORS.textDim, Theme.Font.Body)
			hint.Size = UDim2.new(1, -24, 0, 40)
			hint.Position = UDim2.new(0, 12, 0, 8)
			return
		end

		local def = Items.get(trade.itemId)
		local rarity = Rarity.forDef(def)

		local thumbHolder = Instance.new("Frame")
		thumbHolder.Size = UDim2.new(0, 110, 0, 110)
		thumbHolder.Position = UDim2.new(0.5, -55, 0, 12)
		thumbHolder.BackgroundColor3 = Theme.Color.Ink900
		thumbHolder.BorderSizePixel = 0
		thumbHolder.Parent = detail
		local thumbStroke = Instance.new("UIStroke")
		thumbStroke.Thickness = 1
		thumbStroke.Color = rarity.color
		thumbStroke.Parent = thumbHolder
		if rarity.hasGlow then
			UIKit.addGlow(thumbHolder, rarity.glowColor, 0.7)
		end
		local thumb = Instance.new("ViewportFrame")
		thumb.Size = UDim2.new(1, -8, 1, -8)
		thumb.Position = UDim2.new(0, 4, 0, 4)
		thumb.BackgroundTransparency = 1
		thumb.Ambient = Color3.fromRGB(180, 180, 190)
		thumb.LightColor = Color3.new(1, 1, 1)
		thumb.ZIndex = 2
		thumb.Parent = thumbHolder
		ItemModels.preview(thumb, trade.itemId)

		local name =
			detailText(def and def.name or trade.itemId, Theme.Text.Item, rarity.textColor, Theme.Font.DisplayBold)
		name.Size = UDim2.new(1, -24, 0, 22)
		name.Position = UDim2.new(0, 12, 0, 128)
		name.TextTruncate = Enum.TextTruncate.AtEnd

		local rarityLabel = detailText(rarity.name, Theme.Text.Xs, rarity.textColor, Theme.Font.Body)
		rarityLabel.TextTransparency = 0.25
		rarityLabel.Size = UDim2.new(1, -24, 0, 14)
		rarityLabel.Position = UDim2.new(0, 12, 0, 150)

		local infoY = 172
		local owned = countOwned(trade.itemId)
		if tab == "sell" then
			local ownedLabel = detailText("You have " .. owned, Theme.Text.Sm, COLORS.textDim, Theme.Font.Body)
			ownedLabel.Size = UDim2.new(1, -24, 0, 16)
			ownedLabel.Position = UDim2.new(0, 12, 0, infoY)
			infoY += 20
		end

		local priceLabel = detailText("◈ " .. price, Theme.Text.Lg, COLORS.gold)
		priceLabel.Size = UDim2.new(1, -24, 0, 20)
		priceLabel.Position = UDim2.new(0, 12, 0, infoY)

		local canTrade = tab == "buy" or owned > 0
		local actionBtn
		if canTrade then
			actionBtn = UIKit.primaryButton(detail, tab == "buy" and "Buy" or "Sell")
			actionBtn.MouseButton1Click:Connect(function()
				doTrade(tab, trade.itemId)
			end)
		else
			actionBtn = UIKit.ghostButton(detail, "Nothing to sell")
			actionBtn.TextColor3 = Theme.Semantic.TextDim
		end
		actionBtn.Size = UDim2.new(1, -24, 0, 32)
		actionBtn.Position = UDim2.new(0, 12, 1, -12)
		actionBtn.AnchorPoint = Vector2.new(0, 1)
	end

	-- ---- trade rows -------------------------------------------------------------
	local rowWidgets = {} -- [itemId] = { row, stroke } for selection styling

	local function styleRowSelection()
		for itemId, widgets in pairs(rowWidgets) do
			local isSelected = itemId == selected
			widgets.row.BackgroundTransparency = isSelected and 0.05 or 0.35
			widgets.stroke.Thickness = isSelected and 2 or 1
		end
	end

	local function makeRow(order, trade, price)
		local def = Items.get(trade.itemId)
		local name = def and def.name or trade.itemId
		local rarity = Rarity.forDef(def) -- store rows are plain defs, never rolled

		local row = Instance.new("TextButton")
		row.Text = ""
		row.AutoButtonColor = false
		row.Size = UDim2.new(1, 0, 0, ROW_H)
		row.BackgroundColor3 = COLORS.tile
		row.BackgroundTransparency = 0.35
		row.BorderSizePixel = 0
		row.LayoutOrder = order
		row.Parent = list

		local rowStroke = Instance.new("UIStroke")
		rowStroke.Thickness = 1
		rowStroke.Color = rarity.color
		rowStroke.Parent = row
		if rarity.hasGlow then
			UIKit.addGlow(row, rarity.glowColor, 0.85)
		end

		local thumbHolder = Instance.new("Frame")
		thumbHolder.Size = UDim2.new(0, ROW_H - 6, 0, ROW_H - 6)
		thumbHolder.Position = UDim2.new(0, 3, 0, 3)
		thumbHolder.BackgroundColor3 = Theme.Color.Ink850
		thumbHolder.BorderSizePixel = 0
		thumbHolder.Parent = row

		local thumb = Instance.new("ViewportFrame")
		thumb.Size = UDim2.new(1, -4, 1, -4)
		thumb.Position = UDim2.new(0, 2, 0, 2)
		thumb.BackgroundTransparency = 1
		thumb.Ambient = Color3.fromRGB(180, 180, 190)
		thumb.LightColor = Color3.new(1, 1, 1)
		thumb.Parent = thumbHolder
		ItemModels.preview(thumb, trade.itemId)

		local nameLabel = makeLabel(row, name, 13, rarity.textColor)
		nameLabel.Size = UDim2.new(1, -(ROW_H + 76), 1, 0)
		nameLabel.Position = UDim2.new(0, ROW_H + 4, 0, 0)
		nameLabel.TextXAlignment = Enum.TextXAlignment.Left
		nameLabel.TextTruncate = Enum.TextTruncate.AtEnd

		local priceLabel = makeLabel(row, "◈ " .. price, 13, COLORS.gold)
		priceLabel.Size = UDim2.new(0, 60, 1, 0)
		priceLabel.Position = UDim2.new(1, -66, 0, 0)
		priceLabel.TextXAlignment = Enum.TextXAlignment.Right

		row.MouseButton1Click:Connect(function()
			selected = trade.itemId
			statusLabel.Text = ""
			styleRowSelection()
			renderDetail()
		end)

		rowWidgets[trade.itemId] = { row = row, stroke = rowStroke }
	end

	refresh = function()
		for _, child in ipairs(list:GetChildren()) do
			if child:IsA("GuiObject") then
				child:Destroy()
			end
		end
		rowWidgets = {}
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
		local selectionListed = false
		for _, trade in ipairs(store.trades) do
			local price = tab == "buy" and trade.buyPrice or trade.sellPrice
			if price then
				order += 1
				makeRow(order, trade, price)
				if not selected then
					selected = trade.itemId -- focus the first trade by default
				end
				if trade.itemId == selected then
					selectionListed = true
				end
			end
		end
		if not selectionListed then
			selected = nil
		end
		styleRowSelection()
		renderDetail()
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
		selected = nil -- refresh() focuses the first trade
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
