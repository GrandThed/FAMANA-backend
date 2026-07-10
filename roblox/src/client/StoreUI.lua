-- Tarkov-style vendor trade screen (docs/VENDOR_UI.md): three panes — the
-- vendor's STOCK grid (left), the DEAL zone (center: "you give" / "you get"
-- grids, net gold, the DEAL button), and YOUR PACK (right, the main grid).
-- Opens on OpenStore (vendor ProximityPrompt); the whole deal settles through
-- the StoreDeal RemoteFunction in ONE atomic backend transaction — on
-- failure nothing changed and the zone stays put.
--
-- Interactions (§4): click a tile → +1 into the deal; shift-click → one full
-- stack (vendor stock, regardless of gold) / the whole stack (your pack);
-- drag a tile into a deal grid → same; drag a deal tile out → remove it.
-- Click a deal tile → −/+/All/× popover. Rolled instances move whole as
-- positional sell lines (that's what makes them sellable at all); barter
-- buys auto-add locked cost tiles to "you give". Prices preview through the
-- same shared modules the server settles with (Stores + ItemValue) — the
-- server validates and prices everything again.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local UserInputService = game:GetService("UserInputService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared:WaitForChild("Config"))
local Items = require(Shared:WaitForChild("Items"))
local ItemValue = require(Shared:WaitForChild("ItemValue"))
local Stores = require(Shared:WaitForChild("Stores"))
local Remotes = require(Shared:WaitForChild("Remotes"))
local ClientState = require(script.Parent.ClientState)
local ItemGrid = require(script.Parent.ItemGrid)
local ItemTooltip = require(script.Parent.ItemTooltip)
local Theme = require(script.Parent.Theme)
local UIKit = require(script.Parent.UIKit)
local Sfx = require(script.Parent.Sfx)

local player = Players.LocalPlayer
local mouse = player:GetMouse() -- gui-space coords, same space as AbsolutePosition

local StoreUI = {}

local ERROR_TEXT = {
	no_gold = "Not enough gold",
	no_space = "Not enough room in your inventory",
	no_items = "You don't have that many",
	too_far = "Too far from the vendor",
	not_traded = "That item isn't traded here",
	bad_line = "That trade isn't valid anymore",
	too_many_lines = "Deal too large",
	offline = "Backend unavailable",
	bad_request = "Something went wrong",
}

local CELL = Theme.Size.Cell
local STOCK_COLS = 8
local PACK_COLS = Config.inventoryGrid.width
local PACK_ROWS = Config.inventoryGrid.height
local DEAL_COLS, DEAL_ROWS = 6, 6
local VISIBLE_ROWS = 14
local MAX_DEAL_LINES = 20 -- sendable lines; mirrors VendorService
local CLOSE_DISTANCE = 20 -- studs; walk away → the panel closes itself

-- Pane x offsets (§3 layout, authored at 1280×720).
local STOCK_X = 12
local STOCK_W = STOCK_COLS * CELL + 8 -- + scrollbar
local DEAL_X = STOCK_X + STOCK_W + 12
local DEAL_COL_W = DEAL_COLS * CELL + 24
local DEAL_GRID_X = DEAL_X + (DEAL_COL_W - DEAL_COLS * CELL) / 2
local PACK_X = DEAL_X + DEAL_COL_W + 12
local PANEL_W = PACK_X + PACK_COLS * CELL + 8 + 12
local PANEL_H = 714 -- two 6×6 deal grids + footer; stays inside the 720 design height
local PANE_TOP = 76

local function makeLabel(parent, text, size, color, font)
	local label = Instance.new("TextLabel")
	label.BackgroundTransparency = 1
	label.FontFace = font or Theme.Font.BodyBold
	label.TextSize = size
	label.TextColor3 = color or Theme.Semantic.TextBody
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
	panel.Position = UDim2.new(0.5, 0, 0.5, 0)
	panel.AnchorPoint = Vector2.new(0.5, 0.5)
	panel.Visible = false
	panel.Parent = gui
	UIKit.stylePanel(panel)
	UIKit.addShadow(panel)
	UIKit.autoScale(panel)

	local title = UIKit.titleBar(panel, "", 36)

	local vendorLabel = makeLabel(panel, "", 12, Theme.Semantic.TextMuted, Theme.Font.Body)
	vendorLabel.Size = UDim2.new(0, 300, 0, 36)
	vendorLabel.Position = UDim2.new(1, -340, 0, 0)
	vendorLabel.TextXAlignment = Enum.TextXAlignment.Right

	local closeBtn = UIKit.closeButton(panel)
	closeBtn.Position = UDim2.new(1, -6, 0, 5)
	closeBtn.AnchorPoint = Vector2.new(1, 0)

	-- ---- pane headers -----------------------------------------------------
	local function header(text, x, w)
		local label = UIKit.sectionLabel(panel, text)
		label.Size = UDim2.new(0, w, 0, 18)
		label.Position = UDim2.new(0, x, 0, 52)
		label.TextXAlignment = Enum.TextXAlignment.Left
		return label
	end
	header("Stock", STOCK_X + 2, STOCK_W)
	header("You give", DEAL_GRID_X + 2, DEAL_COLS * CELL)
	header("Your pack", PACK_X + 2, 200)

	local goldLabel = makeLabel(panel, "◈ 0", 14, Theme.Semantic.Currency)
	goldLabel.Size = UDim2.new(0, 160, 0, 18)
	goldLabel.Position = UDim2.new(0, PACK_X + PACK_COLS * CELL + 8 - 160, 0, 52)
	goldLabel.TextXAlignment = Enum.TextXAlignment.Right

	-- ---- the three panes ----------------------------------------------------
	local stockGrid = ItemGrid.create(panel, { columns = STOCK_COLS, visibleRows = VISIBLE_ROWS })
	stockGrid.frame.Position = UDim2.new(0, STOCK_X, 0, PANE_TOP)

	local giveGrid = ItemGrid.create(panel, { columns = DEAL_COLS, visibleRows = DEAL_ROWS, canvasRows = DEAL_ROWS })
	giveGrid.frame.Position = UDim2.new(0, DEAL_GRID_X, 0, PANE_TOP)

	local getHeader = header("You get", DEAL_GRID_X + 2, DEAL_COLS * CELL)
	getHeader.Position = UDim2.new(0, DEAL_GRID_X + 2, 0, PANE_TOP + DEAL_ROWS * CELL + 10)

	local getGrid = ItemGrid.create(panel, { columns = DEAL_COLS, visibleRows = DEAL_ROWS, canvasRows = DEAL_ROWS })
	getGrid.frame.Position = UDim2.new(0, DEAL_GRID_X, 0, PANE_TOP + DEAL_ROWS * CELL + 32)

	local packGrid = ItemGrid.create(
		panel,
		{ columns = PACK_COLS, visibleRows = VISIBLE_ROWS, canvasRows = PACK_ROWS }
	)
	packGrid.frame.Position = UDim2.new(0, PACK_X, 0, PANE_TOP)

	-- ---- net row + DEAL + status --------------------------------------------
	local dealBottom = PANE_TOP + DEAL_ROWS * CELL + 32 + DEAL_ROWS * CELL

	local netLabel = makeLabel(panel, "", 14, Theme.Semantic.TextBody)
	netLabel.Size = UDim2.new(0, DEAL_COL_W - 16, 0, 18)
	netLabel.Position = UDim2.new(0, DEAL_X + 8, 0, dealBottom + 6)

	local dealBtn = UIKit.primaryButton(panel, "DEAL")
	dealBtn.Size = UDim2.new(0, DEAL_COLS * CELL, 0, 36)
	dealBtn.Position = UDim2.new(0, DEAL_GRID_X, 0, dealBottom + 28)

	local statusLabel = makeLabel(panel, "", 12, Theme.Semantic.Danger)
	statusLabel.Size = UDim2.new(0, DEAL_COL_W - 16, 0, 30)
	statusLabel.Position = UDim2.new(0, DEAL_X + 8, 0, dealBottom + 68)
	statusLabel.TextWrapped = true
	statusLabel.TextYAlignment = Enum.TextYAlignment.Top

	-- ---- state ---------------------------------------------------------------
	local current = nil -- { storeId, storeName, vendorName, position }
	local inventory = {}
	local busy = false
	-- Deal lines. side "buy" fills the GET grid; "sell" and "cost" (locked
	-- barter costs, derived from barter buys, never sent) fill GIVE. Each
	-- carries its deal-grid placement (x, y, rotated); instance sells also
	-- remember their pack position (srcX, srcY) — that's the sell reference.
	local dealLines = {}

	local storeDeal = Remotes.getFunction("StoreDeal")

	local tooltip = ItemTooltip.create(gui, function()
		return panel.Visible
	end)

	local refreshDeal -- forward declarations (helpers call across sections)
	local refreshPack

	-- ---- pricing helpers ------------------------------------------------------
	local function tradeFor(itemId)
		return current and Stores.trade(current.storeId, itemId)
	end

	local function storeDef()
		return current and Stores.get(current.storeId)
	end

	-- The gold the store pays for ONE unit of an entry (nil = won't buy it).
	-- Resolution order — MUST match VendorService's: rolled instances (meta)
	-- price by the shared formula; listed plain items by the curated trade
	-- sellPrice (even when their def carries starter trait points — the
	-- curated price wins); unlisted def-trait gear by the formula.
	local function sellPriceFor(entry, itemId)
		local def = Items.get(itemId)
		local store = storeDef()
		local buysGear = store and store.buysGear
		if buysGear and entry and entry.meta then
			local value = ItemValue.forEntry(entry, def)
			if value then
				return value
			end
		end
		local trade = tradeFor(itemId)
		if trade and trade.sellPrice then
			return trade.sellPrice
		end
		if buysGear then
			return ItemValue.forEntry(entry, def)
		end
		return nil
	end

	local function countOwned(itemId)
		local total = 0
		for _, entry in ipairs(inventory) do
			if entry.containerId == "main" and entry.itemId == itemId and not entry.meta then
				total += entry.quantity
			end
		end
		return total
	end

	-- Quantity of `itemId` the give side already consumes (plain sells +
	-- barter costs — instance sells are their own rows and don't count).
	local function committedGive(itemId)
		local total = 0
		for _, line in ipairs(dealLines) do
			if line.itemId == itemId and (line.side == "cost" or (line.side == "sell" and not line.meta)) then
				total += line.quantity
			end
		end
		return total
	end

	local function linesOn(gridSide) -- "give" | "get"
		local out = {}
		for _, line in ipairs(dealLines) do
			local isGive = line.side ~= "buy"
			if (gridSide == "give") == isGive then
				out[#out + 1] = line
			end
		end
		return out
	end

	local function sendableCount()
		local count = 0
		for _, line in ipairs(dealLines) do
			if line.side ~= "cost" then
				count += 1
			end
		end
		return count
	end

	local function lineTotal(line)
		if line.side == "buy" then
			local trade = tradeFor(line.itemId)
			return trade and trade.buyPrice and trade.buyPrice * line.quantity or nil -- barter buys carry no gold
		elseif line.side == "sell" then
			local price = sellPriceFor(line.meta and { itemId = line.itemId, meta = line.meta } or nil, line.itemId)
			return price and price * line.quantity or 0
		end
		return nil -- cost lines: the barter chip explains them
	end

	local function netGold()
		local net = 0
		for _, line in ipairs(dealLines) do
			local total = lineTotal(line)
			if total then
				net += line.side == "buy" and -total or total
			end
		end
		return net
	end

	-- ---- deal mutation ---------------------------------------------------------
	local function setStatus(code)
		statusLabel.Text = code and (ERROR_TEXT[code] or code) or ""
	end

	local function placeLine(line)
		local gridSide = line.side == "buy" and "get" or "give"
		local x, y, rotated = ItemGrid.findSpot(linesOn(gridSide), line.itemId, DEAL_COLS, DEAL_ROWS)
		if not x then
			return false
		end
		line.x, line.y, line.rotated = x, y, rotated
		return true
	end

	-- Rebuilds the locked cost tiles from the barter buys (derived data).
	-- Fails without mutating when the costs don't fit or aren't owned —
	-- callers undo whatever change they were attempting.
	local function syncBarterCosts()
		local keep = {}
		for _, line in ipairs(dealLines) do
			if line.side ~= "cost" then
				keep[#keep + 1] = line
			end
		end

		local needs = {} -- [itemId] = qty, merged across barter buys
		local order = {}
		for _, line in ipairs(keep) do
			if line.side == "buy" then
				local trade = tradeFor(line.itemId)
				if trade and trade.barter then
					for _, cost in ipairs(trade.barter) do
						if not needs[cost.itemId] then
							order[#order + 1] = cost.itemId
						end
						needs[cost.itemId] = (needs[cost.itemId] or 0) + cost.qty * line.quantity
					end
				end
			end
		end

		local placedGive = {}
		for _, line in ipairs(keep) do
			if line.side ~= "buy" then
				placedGive[#placedGive + 1] = line
			end
		end
		local costLines = {}
		for _, itemId in ipairs(order) do
			local needed = needs[itemId]
			local sold = 0
			for _, line in ipairs(keep) do
				if line.side == "sell" and not line.meta and line.itemId == itemId then
					sold += line.quantity
				end
			end
			if countOwned(itemId) - sold < needed then
				return false, "no_items"
			end
			local x, y, rotated = ItemGrid.findSpot(placedGive, itemId, DEAL_COLS, DEAL_ROWS)
			if not x then
				return false, "deal_full"
			end
			local costLine =
				{ side = "cost", itemId = itemId, quantity = needed, locked = true, x = x, y = y, rotated = rotated }
			placedGive[#placedGive + 1] = costLine
			costLines[#costLines + 1] = costLine
		end

		dealLines = keep
		for _, line in ipairs(costLines) do
			dealLines[#dealLines + 1] = line
		end
		return true
	end

	local function removeLine(line)
		for i, candidate in ipairs(dealLines) do
			if candidate == line then
				table.remove(dealLines, i)
				break
			end
		end
		if line.side == "buy" then
			syncBarterCosts() -- shrinking always succeeds
		end
		refreshDeal()
	end

	local function addBuy(itemId, quantity)
		setStatus(nil)
		local trade = tradeFor(itemId)
		if not trade or (not trade.buyPrice and not trade.barter) then
			setStatus("not_traded")
			return
		end
		local existing
		for _, line in ipairs(dealLines) do
			if line.side == "buy" and line.itemId == itemId then
				existing = line
				break
			end
		end
		local undo
		if existing then
			local before = existing.quantity
			existing.quantity = math.clamp(before + quantity, 1, 99)
			undo = function()
				existing.quantity = before
			end
		else
			if sendableCount() >= MAX_DEAL_LINES then
				setStatus("too_many_lines")
				return
			end
			local line = { side = "buy", itemId = itemId, quantity = math.clamp(quantity, 1, 99) }
			if not placeLine(line) then
				setStatus("Deal grid is full")
				return
			end
			dealLines[#dealLines + 1] = line
			undo = function()
				for i, candidate in ipairs(dealLines) do
					if candidate == line then
						table.remove(dealLines, i)
						break
					end
				end
			end
		end
		local ok, err = syncBarterCosts()
		if not ok then
			undo()
			syncBarterCosts()
			setStatus(err == "deal_full" and "Deal grid is full" or err)
			return
		end
		refreshDeal()
	end

	local function addSell(entry, quantity)
		setStatus(nil)
		if entry.meta then
			-- Rolled instance: the whole row moves, one line per pack position.
			for _, line in ipairs(dealLines) do
				if line.side == "sell" and line.srcX == entry.x and line.srcY == entry.y then
					return -- already in the deal
				end
			end
			if not sellPriceFor(entry, entry.itemId) then
				setStatus("not_traded")
				return
			end
			if sendableCount() >= MAX_DEAL_LINES then
				setStatus("too_many_lines")
				return
			end
			local line = {
				side = "sell",
				itemId = entry.itemId,
				quantity = entry.quantity,
				meta = entry.meta,
				srcX = entry.x,
				srcY = entry.y,
			}
			if not placeLine(line) then
				setStatus("Deal grid is full")
				return
			end
			dealLines[#dealLines + 1] = line
			refreshDeal()
			return
		end

		if not sellPriceFor(nil, entry.itemId) then
			setStatus("not_traded")
			return
		end
		local available = countOwned(entry.itemId) - committedGive(entry.itemId)
		quantity = math.min(quantity, available)
		if quantity <= 0 then
			return
		end
		local existing
		for _, line in ipairs(dealLines) do
			if line.side == "sell" and not line.meta and line.itemId == entry.itemId then
				existing = line
				break
			end
		end
		if existing then
			existing.quantity += quantity
		else
			if sendableCount() >= MAX_DEAL_LINES then
				setStatus("too_many_lines")
				return
			end
			local line = { side = "sell", itemId = entry.itemId, quantity = quantity }
			if not placeLine(line) then
				setStatus("Deal grid is full")
				return
			end
			dealLines[#dealLines + 1] = line
		end
		refreshDeal()
	end

	local function clearDeal()
		dealLines = {}
		refreshDeal()
	end

	-- Re-check the deal against a fresh inventory push (gathering, drops and
	-- the settled deal itself all change it under the open panel).
	local function revalidateDeal()
		local changed = false
		for i = #dealLines, 1, -1 do
			local line = dealLines[i]
			if line.side == "sell" and line.meta then
				local still
				for _, entry in ipairs(inventory) do
					if
						entry.containerId == "main"
						and entry.x == line.srcX
						and entry.y == line.srcY
						and entry.itemId == line.itemId
						and entry.meta
					then
						still = entry
						break
					end
				end
				if not still then
					table.remove(dealLines, i)
					changed = true
				end
			elseif line.side == "sell" then
				local available = countOwned(line.itemId)
				if available < line.quantity then
					line.quantity = available
					changed = true
					if line.quantity <= 0 then
						table.remove(dealLines, i)
					end
				end
			end
		end
		-- Barter buys whose costs vanished shrink until the deal is payable.
		while not syncBarterCosts() do
			local victim
			for i = #dealLines, 1, -1 do
				local line = dealLines[i]
				local trade = tradeFor(line.itemId)
				if line.side == "buy" and trade and trade.barter then
					victim = line
					break
				end
			end
			if not victim then
				break
			end
			if victim.quantity > 1 then
				victim.quantity -= 1
			else
				for i, line in ipairs(dealLines) do
					if line == victim then
						table.remove(dealLines, i)
						break
					end
				end
			end
			changed = true
		end
		if changed then
			setStatus("Deal updated — inventory changed")
		end
	end

	-- ---- quantity popover -------------------------------------------------------
	local popover = Instance.new("Frame")
	popover.Size = UDim2.new(0, 168, 0, 40)
	popover.Visible = false
	popover.ZIndex = 70
	popover.Parent = gui
	UIKit.stylePanel(popover)
	UIKit.autoScale(popover)

	local popoverLine -- the deal line being edited

	local function popoverButton(text, x, w)
		local btn = UIKit.ghostButton(popover, text)
		btn.Size = UDim2.new(0, w, 0, 26)
		btn.Position = UDim2.new(0, x, 0, 7)
		btn.ZIndex = 71
		return btn
	end

	local minusBtn = popoverButton("−", 8, 26)
	local qtyLabel = makeLabel(popover, "", 13, Theme.Semantic.TextStrong)
	qtyLabel.Size = UDim2.new(0, 30, 0, 26)
	qtyLabel.Position = UDim2.new(0, 38, 0, 7)
	qtyLabel.TextXAlignment = Enum.TextXAlignment.Center
	qtyLabel.ZIndex = 71
	local plusBtn = popoverButton("+", 72, 26)
	local allBtn = popoverButton("All", 102, 30)
	local removeBtn = popoverButton("✕", 136, 26)
	removeBtn.TextColor3 = Theme.Semantic.Danger

	local function hidePopover()
		popover.Visible = false
		popoverLine = nil
	end

	local function popoverMax(line)
		if line.side == "buy" then
			local def = Items.get(line.itemId)
			return (def and def.stackable) and math.min(Items.maxStackFor(line.itemId), 99) or 99
		end
		return countOwned(line.itemId) - committedGive(line.itemId) + line.quantity
	end

	local function setLineQuantity(line, quantity)
		if quantity <= 0 then
			hidePopover()
			removeLine(line)
			return
		end
		local before = line.quantity
		line.quantity = math.clamp(quantity, 1, math.max(1, popoverMax(line)))
		if line.side == "buy" then
			local ok, err = syncBarterCosts()
			if not ok then
				line.quantity = before
				syncBarterCosts()
				setStatus(err == "deal_full" and "Deal grid is full" or err)
			end
		end
		qtyLabel.Text = tostring(line.quantity)
		refreshDeal()
	end

	local function openPopover(line)
		-- Instance sells move whole: nothing to adjust, offer remove only.
		local fixed = line.meta ~= nil
		minusBtn.Visible = not fixed
		plusBtn.Visible = not fixed
		allBtn.Visible = not fixed
		qtyLabel.Text = tostring(line.quantity)
		popoverLine = line
		popover.Position = UDim2.new(0, mouse.X - 84, 0, mouse.Y + 8)
		popover.Visible = true
	end

	minusBtn.Activated:Connect(function()
		if popoverLine then
			setLineQuantity(popoverLine, popoverLine.quantity - 1)
		end
	end)
	plusBtn.Activated:Connect(function()
		if popoverLine then
			setLineQuantity(popoverLine, popoverLine.quantity + 1)
		end
	end)
	allBtn.Activated:Connect(function()
		if popoverLine then
			setLineQuantity(popoverLine, popoverMax(popoverLine))
		end
	end)
	removeBtn.Activated:Connect(function()
		if popoverLine then
			local line = popoverLine
			hidePopover()
			removeLine(line)
		end
	end)

	-- Click anywhere outside the popover dismisses it.
	UserInputService.InputBegan:Connect(function(input)
		if not popover.Visible or input.UserInputType ~= Enum.UserInputType.MouseButton1 then
			return
		end
		local topLeft = popover.AbsolutePosition
		local size = popover.AbsoluteSize
		if
			mouse.X < topLeft.X
			or mouse.X > topLeft.X + size.X
			or mouse.Y < topLeft.Y
			or mouse.Y > topLeft.Y + size.Y
		then
			hidePopover()
		end
	end)

	-- ---- rendering ------------------------------------------------------------
	local function updateGold()
		goldLabel.Text = ("◈ %d"):format(player:GetAttribute("Gold") or 0)
	end

	local function refreshDealButton()
		local net = netGold()
		local hasLines = #dealLines > 0
		local gold = player:GetAttribute("Gold") or 0
		local affordable = net >= 0 or gold >= -net

		if not hasLines then
			netLabel.Text = "Add items to trade"
			netLabel.TextColor3 = Theme.Semantic.TextMuted
			dealBtn.Text = "DEAL"
		elseif net < 0 then
			netLabel.Text = ("Net — pay ◈ %d"):format(-net)
			netLabel.TextColor3 = affordable and Theme.Semantic.TextBody or Theme.Semantic.Danger
			dealBtn.Text = ("DEAL — PAY ◈ %d"):format(-net)
		elseif net > 0 then
			netLabel.Text = ("Net — get ◈ %d"):format(net)
			netLabel.TextColor3 = Theme.Semantic.Currency
			dealBtn.Text = ("DEAL — GET ◈ %d"):format(net)
		else
			netLabel.Text = "Net — even trade"
			netLabel.TextColor3 = Theme.Semantic.TextBody
			dealBtn.Text = "DEAL"
		end

		local enabled = hasLines and affordable and not busy
		dealBtn.Active = enabled
		dealBtn.TextTransparency = enabled and 0 or 0.45
	end

	refreshPack = function()
		if not current then
			return
		end
		local entries = {}
		for _, entry in ipairs(inventory) do
			if entry.containerId == "main" then
				local price = sellPriceFor(entry, entry.itemId)
				local committed = false
				if entry.meta then
					for _, line in ipairs(dealLines) do
						if line.side == "sell" and line.srcX == entry.x and line.srcY == entry.y then
							committed = true
							break
						end
					end
				end
				-- Clone: display fields must not leak into the shared entry
				-- tables other UIs read from the same remote push.
				entries[#entries + 1] = {
					itemId = entry.itemId,
					quantity = entry.quantity,
					x = entry.x,
					y = entry.y,
					rotated = entry.rotated,
					meta = entry.meta,
					chip = price and ("◈ " .. price) or nil,
					dimmed = price == nil or committed,
					locked = committed,
				}
			end
		end
		packGrid.render(entries)
	end

	refreshDeal = function()
		local give = {}
		local get = {}
		for _, line in ipairs(dealLines) do
			local total = lineTotal(line)
			local entry = {
				itemId = line.itemId,
				quantity = line.quantity,
				x = line.x,
				y = line.y,
				rotated = line.rotated,
				meta = line.meta,
				locked = line.side == "cost",
				chip = total and ("◈ " .. total) or (line.side == "buy" and "⇄" or nil),
				_line = line,
			}
			if line.side == "buy" then
				get[#get + 1] = entry
			else
				give[#give + 1] = entry
			end
		end
		giveGrid.render(give)
		getGrid.render(get)
		refreshDealButton()
		refreshPack() -- committed instances dim in the pack
	end

	local function refreshStock()
		local store = storeDef()
		if not store then
			return
		end
		local items = {}
		for _, trade in ipairs(store.trades) do
			if trade.buyPrice or trade.barter then
				items[#items + 1] = {
					itemId = trade.itemId,
					quantity = 1,
					chip = trade.buyPrice and ("◈ " .. trade.buyPrice) or "⇄",
				}
			end
		end
		local placed, overflow = ItemGrid.packFirstFit(items, STOCK_COLS, 60)
		if #overflow > 0 then
			warn("[StoreUI] stock overflow: " .. #overflow .. " trades didn't fit the shelf")
		end
		stockGrid.render(placed)
	end

	-- ---- the deal itself --------------------------------------------------------
	local function doDeal()
		if busy or not current or #dealLines == 0 or not dealBtn.Active then
			return
		end
		busy = true
		refreshDealButton()
		setStatus(nil)

		local lines = {}
		for _, line in ipairs(dealLines) do
			if line.side == "buy" then
				lines[#lines + 1] = { side = "buy", itemId = line.itemId, quantity = line.quantity }
			elseif line.side == "sell" and line.meta then
				lines[#lines + 1] = { side = "sell", itemId = line.itemId, x = line.srcX, y = line.srcY }
			elseif line.side == "sell" then
				lines[#lines + 1] = { side = "sell", itemId = line.itemId, quantity = line.quantity }
			end
		end

		local ok, result = pcall(function()
			return storeDeal:InvokeServer({ storeId = current.storeId, lines = lines })
		end)
		busy = false
		if ok and typeof(result) == "table" and result.ok == true then
			hidePopover()
			clearDeal()
			-- The server pushes InventoryUpdated + the Gold attribute + the toast.
		else
			local code = ok and typeof(result) == "table" and result.error or "bad_request"
			setStatus(code)
			refreshDealButton()
		end
	end
	dealBtn.Activated:Connect(doDeal)

	-- ---- tile interaction wiring -------------------------------------------------
	local function inDealZone(screenPos)
		return giveGrid.containsPoint(screenPos) or getGrid.containsPoint(screenPos)
	end

	stockGrid.callbacks.onClick = function(entry, shift)
		local def = Items.get(entry.itemId)
		-- Shift = one full stack, gold-blind (§4); DEAL stays disabled if short.
		local quantity = (shift and def and def.stackable) and Items.maxStackFor(entry.itemId) or 1
		addBuy(entry.itemId, quantity)
	end
	stockGrid.callbacks.onDragOut = function(entry, screenPos)
		if inDealZone(screenPos) then
			addBuy(entry.itemId, 1)
		end
	end
	stockGrid.callbacks.onHover = function(entry)
		if not entry then
			tooltip.hide()
			return
		end
		local lines = {}
		local trade = tradeFor(entry.itemId)
		if trade and trade.buyPrice then
			lines[#lines + 1] = { text = ("Buy ◈ %d"):format(trade.buyPrice), color = Theme.Semantic.Currency }
		elseif trade and trade.barter then
			local parts = {}
			for _, cost in ipairs(trade.barter) do
				local def = Items.get(cost.itemId)
				parts[#parts + 1] = ("%d× %s"):format(cost.qty, def and def.name or cost.itemId)
			end
			lines[#lines + 1] = { text = "Costs " .. table.concat(parts, ", "), color = Theme.Semantic.Currency }
		end
		lines[#lines + 1] = { text = "Click: add 1 · Shift: full stack" }
		tooltip.schedule(entry, lines)
	end

	packGrid.callbacks.onClick = function(entry, shift)
		local quantity = (shift or entry.meta) and entry.quantity or 1
		addSell(entry, quantity)
	end
	packGrid.callbacks.onDragOut = function(entry, screenPos)
		if inDealZone(screenPos) then
			addSell(entry, entry.quantity) -- drag = the whole stack (§4)
		end
	end
	packGrid.callbacks.onHover = function(entry)
		if not entry then
			tooltip.hide()
			return
		end
		local price = sellPriceFor(entry, entry.itemId)
		local lines = {}
		if price then
			lines[#lines + 1] = { text = ("Sell ◈ %d each"):format(price), color = Theme.Semantic.Currency }
			lines[#lines + 1] = { text = "Click: add 1 · Shift: whole stack" }
		else
			lines[#lines + 1] = { text = "Not traded here", color = Theme.Semantic.Danger }
		end
		tooltip.schedule(entry, lines)
	end

	local function dealTileClick(entry)
		if entry._line then
			openPopover(entry._line)
		end
	end
	local function dealTileDragOut(grid)
		return function(entry, screenPos)
			if not grid.containsPoint(screenPos) and entry._line then
				removeLine(entry._line)
			end
		end
	end
	local function dealTileHover(entry)
		if not entry then
			tooltip.hide()
			return
		end
		tooltip.schedule(entry, { { text = "In deal — click to adjust, drag out to remove" } })
	end
	giveGrid.callbacks = { onClick = dealTileClick, onDragOut = dealTileDragOut(giveGrid), onHover = dealTileHover }
	getGrid.callbacks = { onClick = dealTileClick, onDragOut = dealTileDragOut(getGrid), onHover = dealTileHover }

	-- ---- open / close lifecycle ---------------------------------------------------
	local function close()
		current = nil
		panel.Visible = false
		ClientState.storeOpen = false
		hidePopover()
		tooltip.hide()
		Sfx.play("panelClose")
	end
	closeBtn.Activated:Connect(close)
	ClientState.closeStore = close

	Remotes.get("OpenStore").OnClientEvent:Connect(function(info)
		if typeof(info) ~= "table" then
			return
		end
		if ClientState.inventoryOpen and ClientState.closeInventory then
			ClientState.closeInventory() -- the panes overlap; one screen at a time
		end
		current = info
		dealLines = {}
		title.Text = info.storeName or "Store"
		vendorLabel.Text = info.vendorName or ""
		setStatus(nil)
		panel.Visible = true
		ClientState.storeOpen = true
		Sfx.play("panelOpen")
		updateGold()
		refreshStock()
		refreshDeal()
	end)

	-- Walk away → close (the server enforces its own distance on the deal).
	task.spawn(function()
		while true do
			task.wait(0.5)
			if current and typeof(current.position) == "Vector3" then
				local character = player.Character
				local root = character and character:FindFirstChild("HumanoidRootPart")
				if root and (root.Position - current.position).Magnitude > CLOSE_DISTANCE then
					close()
				end
			end
		end
	end)

	player:GetAttributeChangedSignal("Gold"):Connect(function()
		updateGold()
		refreshDealButton()
	end)
	updateGold()

	Remotes.get("InventoryUpdated").OnClientEvent:Connect(function(entries)
		inventory = entries or {}
		if current then
			revalidateDeal()
			refreshDeal()
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
