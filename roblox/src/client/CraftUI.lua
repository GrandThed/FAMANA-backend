-- Crafting panel (V key / top-right button, stacked under Character).
-- Left column lists every recipe the player COULD craft right now: always
-- the station-less ones, plus any whose `station` matches the live
-- `NearbyStations` attribute (CraftingService recomputes it ~1x/second as
-- the player walks around). Right column shows the ingredient breakdown —
-- green when owned, red when short — and the Craft button. The server is
-- the only authority: this UI previews affordability and re-renders off
-- InventoryUpdated / the attribute, same as StoreUI does for gold/stock.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ContextActionService = game:GetService("ContextActionService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Items = require(Shared:WaitForChild("Items"))
local Recipes = require(Shared:WaitForChild("Recipes"))
local ItemModels = require(Shared:WaitForChild("ItemModels"))
local Rarity = require(Shared:WaitForChild("Rarity"))
local Remotes = require(Shared:WaitForChild("Remotes"))
local Theme = require(script.Parent.Theme)
local TopRightMenu = require(script.Parent.TopRightMenu)
local UIKit = require(script.Parent.UIKit)
local Sfx = require(script.Parent.Sfx)

local player = Players.LocalPlayer

local CraftUI = {}

-- Aethelgard palette (client/Theme.lua).
local COLORS = {
	section = Theme.Semantic.SurfaceWell,
	line = Theme.Semantic.BorderHair,
	tile = Theme.Color.Ink900,
	accent = Theme.Color.Ember500,
	good = Theme.Semantic.Good,
	bad = Theme.Semantic.Bad,
	text = Theme.Semantic.TextBody,
	textDim = Theme.Semantic.TextMuted,
}

local ERROR_TEXT = {
	missing_materials = "Missing materials",
	no_space = "Not enough room in your inventory",
	too_far = "Not near the right station anymore",
	unknown_recipe = "That recipe doesn't exist",
	bad_request = "Something went wrong",
}

local PANEL_W = 620
local PANEL_H = 470
local LIST_W = 296
local ROW_H = 46

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

function CraftUI.start()
	local gui = Instance.new("ScreenGui")
	gui.Name = "CraftUI"
	gui.ResetOnSpawn = false
	gui.Enabled = true
	-- Crafting deliberately COEXISTS with the vendor screen (buy materials,
	-- craft on the spot): neither closes the other, and this panel must
	-- reliably draw ABOVE the trade window — sibling ScreenGuis with equal
	-- DisplayOrder stack by insertion order, which is accidental.
	gui.DisplayOrder = 5
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

	local title = makeLabel(panel, "Crafting", Theme.Text.Title, Theme.Semantic.TextTitle, Theme.Font.DisplayBold)
	title.Size = UDim2.new(1, -80, 0, 30)
	title.Position = UDim2.new(0, 12, 0, 4)
	title.TextXAlignment = Enum.TextXAlignment.Left

	local hintLabel = makeLabel(panel, "", 12, COLORS.textDim, Theme.Font.Body)
	hintLabel.Size = UDim2.new(1, -80, 0, 16)
	hintLabel.Position = UDim2.new(0, 12, 0, 30)
	hintLabel.TextXAlignment = Enum.TextXAlignment.Left

	local closeBtn = UIKit.closeButton(panel)
	closeBtn.Position = UDim2.new(1, -6, 0, 6)
	closeBtn.AnchorPoint = Vector2.new(1, 0)

	-- ---- rows (left column) -------------------------------------------------
	local list = Instance.new("ScrollingFrame")
	list.Size = UDim2.new(0, LIST_W, 1, -(52 + 66))
	list.Position = UDim2.new(0, 12, 0, 52)
	list.BackgroundColor3 = COLORS.section
	list.BorderSizePixel = 0
	list.ScrollBarThickness = 6
	list.AutomaticCanvasSize = Enum.AutomaticSize.Y
	list.CanvasSize = UDim2.new(0, 0, 0, 0)
	list.Parent = panel

	local listStroke = Instance.new("UIStroke")
	listStroke.Thickness = 1
	listStroke.Color = COLORS.line
	listStroke.Parent = list

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

	-- ---- detail pane (right column) -----------------------------------------
	local detail = Instance.new("Frame")
	detail.Position = UDim2.new(0, LIST_W + 24, 0, 52)
	detail.Size = UDim2.new(1, -(LIST_W + 36), 1, -(52 + 24))
	detail.BackgroundColor3 = COLORS.section
	detail.BorderSizePixel = 0
	detail.Parent = panel

	local detailStroke = Instance.new("UIStroke")
	detailStroke.Thickness = 1
	detailStroke.Color = COLORS.line
	detailStroke.Parent = detail

	local statusLabel = makeLabel(panel, "", 12, COLORS.bad)
	statusLabel.Size = UDim2.new(1, -24, 0, 20)
	statusLabel.Position = UDim2.new(0, 12, 1, -28)
	statusLabel.TextXAlignment = Enum.TextXAlignment.Left

	-- ---- state ----------------------------------------------------------------
	local isOpen = false
	local busy = false
	local inventory = {}
	local nearby = {} -- set of station ids currently in range, from the attribute
	local selected = Recipes.list()[1] and Recipes.list()[1].id
	local quantity = 1 -- how many of `selected` to craft on next click; reset per-selection

	local craftItem = Remotes.getFunction("CraftItem")

	local function countOwned(itemId)
		local total = 0
		for _, entry in ipairs(inventory) do
			if entry.containerId == "main" and entry.itemId == itemId then
				total += entry.quantity
			end
		end
		return total
	end

	-- A recipe is currently offered if it needs no station, or its station
	-- is in the live nearby set.
	local function isAvailable(def)
		return def.station == nil or nearby[def.station] == true
	end

	local function canAfford(def, qty)
		qty = qty or 1
		for _, ingredient in ipairs(def.ingredients) do
			if countOwned(ingredient.itemId) < ingredient.quantity * qty then
				return false
			end
		end
		return true
	end

	-- Highest quantity of `def` craftable right now given owned materials
	-- (ignores station distance / inventory space, both re-checked server-side).
	local function maxCraftable(def)
		local max = math.huge
		for _, ingredient in ipairs(def.ingredients) do
			local owned = countOwned(ingredient.itemId)
			max = math.min(max, math.floor(owned / ingredient.quantity))
		end
		if max == math.huge then
			max = 0
		end
		return max
	end

	local refresh -- forward declaration

	local function doCraft(recipeId, qty)
		if busy then
			return
		end
		busy = true
		statusLabel.Text = ""
		local result = craftItem:InvokeServer(recipeId, qty)
		busy = false
		if typeof(result) ~= "table" or not result.ok then
			local code = typeof(result) == "table" and result.error or nil
			statusLabel.Text = ERROR_TEXT[code] or ERROR_TEXT.bad_request
		end
		-- Success needs no local bookkeeping: InventoryUpdated re-renders.
	end

	-- ---- detail pane rendering -----------------------------------------------
	local function detailText(text, size, color, font)
		local label = makeLabel(detail, text, size, color, font)
		label.TextXAlignment = Enum.TextXAlignment.Left
		return label
	end

	local function renderDetail()
		for _, child in ipairs(detail:GetChildren()) do
			if child:IsA("GuiObject") then
				child:Destroy()
			end
		end
		local def = selected and Recipes.get(selected)
		if not def then
			local hint = detailText("Select a recipe", Theme.Text.Body, COLORS.textDim, Theme.Font.Body)
			hint.Size = UDim2.new(1, -24, 0, 40)
			hint.Position = UDim2.new(0, 12, 0, 8)
			return
		end

		local maxQty = math.max(1, maxCraftable(def))
		quantity = math.clamp(quantity, 1, maxQty)

		local resultDef = Items.get(def.result.itemId)
		local rarity = Rarity.forDef(resultDef)

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
		local thumb = Instance.new("ViewportFrame")
		thumb.Size = UDim2.new(1, -8, 1, -8)
		thumb.Position = UDim2.new(0, 4, 0, 4)
		thumb.BackgroundTransparency = 1
		thumb.Ambient = Color3.fromRGB(180, 180, 190)
		thumb.LightColor = Color3.new(1, 1, 1)
		thumb.ZIndex = 2
		thumb.Parent = thumbHolder
		ItemModels.preview(thumb, def.result.itemId)

		local resultLabel = def.result.quantity > 1 and (def.name .. " x" .. def.result.quantity) or def.name
		local name = detailText(resultLabel, Theme.Text.Item, rarity.textColor, Theme.Font.DisplayBold)
		name.Size = UDim2.new(1, -24, 0, 22)
		name.Position = UDim2.new(0, 12, 0, 128)
		name.TextTruncate = Enum.TextTruncate.AtEnd

		-- Station ids are named after the item you craft to get them (e.g.
		-- "crafting_table" is both), so Items has the friendly display name.
		local stationLabel = detailText(
			def.station and ("Needs: " .. (Items.get(def.station) and Items.get(def.station).name or def.station))
				or "Craftable anywhere",
			Theme.Text.Xs,
			def.station and (isAvailable(def) and COLORS.good or COLORS.bad) or COLORS.textDim,
			Theme.Font.Body
		)
		stationLabel.Size = UDim2.new(1, -24, 0, 16)
		stationLabel.Position = UDim2.new(0, 12, 0, 150)

		-- Ingredient costs scale with the currently selected batch quantity,
		-- so "5/3" style shortfalls are visible before the player commits.
		local y = 174
		for _, ingredient in ipairs(def.ingredients) do
			local owned = countOwned(ingredient.itemId)
			local needed = ingredient.quantity * quantity
			local have = owned >= needed
			local ingredientDef = Items.get(ingredient.itemId)
			local label = detailText(
				("%s  %d/%d"):format(ingredientDef and ingredientDef.name or ingredient.itemId, owned, needed),
				Theme.Text.Sm,
				have and COLORS.good or COLORS.bad,
				Theme.Font.Body
			)
			label.Size = UDim2.new(1, -24, 0, 18)
			label.Position = UDim2.new(0, 12, 0, y)
			y += 20
		end

		-- ---- batch quantity stepper --------------------------------------
		-- Sits pinned above the action button (not flowed under the
		-- ingredient list) so its position doesn't jump around as recipes
		-- with different ingredient counts get selected.
		local stepper = Instance.new("Frame")
		stepper.BackgroundTransparency = 1
		stepper.Size = UDim2.new(1, -24, 0, 28)
		stepper.Position = UDim2.new(0, 12, 1, -54)
		stepper.AnchorPoint = Vector2.new(0, 1)
		stepper.Parent = detail

		local function stepButton(text, xOffset)
			local btn = Instance.new("TextButton")
			btn.Text = text
			btn.Size = UDim2.new(0, 28, 0, 28)
			btn.Position = UDim2.new(0, xOffset, 0, 0)
			btn.BackgroundColor3 = Theme.Color.Ink700
			btn.BackgroundTransparency = 0.4
			btn.BorderSizePixel = 0
			btn.AutoButtonColor = false
			btn.FontFace = Theme.Font.BodyBold
			btn.TextSize = Theme.Text.Sm
			btn.TextColor3 = COLORS.text
			btn.Parent = stepper
			local stroke = Instance.new("UIStroke")
			stroke.Thickness = 1
			stroke.Color = COLORS.line
			stroke.Parent = btn
			UIKit.hover(btn, Theme.Color.Ink700, Theme.Color.Ink650)
			return btn
		end

		local minusBtn = stepButton("-", 0)
		local qtyLabel = detailText(quantity .. " / " .. maxQty, Theme.Text.Sm, COLORS.text, Theme.Font.BodyBold)
		qtyLabel.Size = UDim2.new(0, 70, 0, 28)
		qtyLabel.Position = UDim2.new(0, 34, 0, 0)
		qtyLabel.TextXAlignment = Enum.TextXAlignment.Center
		qtyLabel.Parent = stepper
		local plusBtn = stepButton("+", 106)

		local maxBtn = Instance.new("TextButton")
		maxBtn.Text = "Max"
		maxBtn.Size = UDim2.new(0, 56, 0, 28)
		maxBtn.Position = UDim2.new(1, -56, 0, 0)
		maxBtn.BackgroundColor3 = Theme.Color.Ink700
		maxBtn.BackgroundTransparency = 0.4
		maxBtn.BorderSizePixel = 0
		maxBtn.AutoButtonColor = false
		maxBtn.FontFace = Theme.Font.BodyBold
		maxBtn.TextSize = Theme.Text.Sm
		maxBtn.TextColor3 = COLORS.text
		maxBtn.Parent = stepper
		local maxStroke = Instance.new("UIStroke")
		maxStroke.Thickness = 1
		maxStroke.Color = COLORS.line
		maxStroke.Parent = maxBtn
		UIKit.hover(maxBtn, Theme.Color.Ink700, Theme.Color.Ink650)

		minusBtn.Activated:Connect(function()
			if quantity > 1 then
				quantity -= 1
				renderDetail()
			end
		end)
		plusBtn.Activated:Connect(function()
			if quantity < maxQty then
				quantity += 1
				renderDetail()
			end
		end)
		maxBtn.Activated:Connect(function()
			if quantity ~= maxQty then
				quantity = maxQty
				renderDetail()
			end
		end)

		local available = isAvailable(def)
		local affordable = canAfford(def, quantity)
		local actionBtn
		if available and affordable then
			actionBtn = UIKit.primaryButton(detail, quantity > 1 and ("Craft x" .. quantity) or "Craft")
			actionBtn.MouseButton1Click:Connect(function()
				doCraft(def.id, quantity)
			end)
		else
			actionBtn = UIKit.ghostButton(detail, not available and "Too far" or "Missing materials")
			actionBtn.TextColor3 = Theme.Semantic.TextDim
		end
		actionBtn.Size = UDim2.new(1, -24, 0, 32)
		actionBtn.Position = UDim2.new(0, 12, 1, -12)
		actionBtn.AnchorPoint = Vector2.new(0, 1)
	end

	-- ---- recipe rows ------------------------------------------------------------
	local rowWidgets = {} -- [recipeId] = { row, stroke }

	local function styleRowSelection()
		for recipeId, widgets in pairs(rowWidgets) do
			local isSelected = recipeId == selected
			widgets.row.BackgroundTransparency = isSelected and 0.05 or 0.35
			widgets.stroke.Thickness = isSelected and 2 or 1
		end
	end

	local function makeRow(order, def)
		local resultDef = Items.get(def.result.itemId)
		local rarity = Rarity.forDef(resultDef)
		local available = isAvailable(def)
		local affordable = canAfford(def)

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
		rowStroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
		rowStroke.Thickness = 1
		rowStroke.Color = rarity.color
		rowStroke.Parent = row

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
		ItemModels.preview(thumb, def.result.itemId)

		local nameLabel = makeLabel(row, def.name, 13, (available and affordable) and rarity.textColor or COLORS.textDim)
		nameLabel.Size = UDim2.new(1, -(ROW_H + 40), 1, 0)
		nameLabel.Position = UDim2.new(0, ROW_H + 4, 0, 0)
		nameLabel.TextXAlignment = Enum.TextXAlignment.Left
		nameLabel.TextTruncate = Enum.TextTruncate.AtEnd

		local dot = makeLabel(row, "●", 13, affordable and COLORS.good or COLORS.bad)
		dot.Size = UDim2.new(0, 24, 1, 0)
		dot.Position = UDim2.new(1, -30, 0, 0)
		dot.TextXAlignment = Enum.TextXAlignment.Right

		row.MouseButton1Click:Connect(function()
			selected = def.id
			quantity = 1
			statusLabel.Text = ""
			styleRowSelection()
			renderDetail()
		end)

		rowWidgets[def.id] = { row = row, stroke = rowStroke }
	end

	refresh = function()
		for _, child in ipairs(list:GetChildren()) do
			if child:IsA("GuiObject") then
				child:Destroy()
			end
		end
		rowWidgets = {}
		local order = 0
		local selectionListed = false
		for _, def in ipairs(Recipes.list()) do
			-- Station-gated recipes are hidden entirely until you're near
			-- the right workbench — that's the "more crafts appear" bit.
			if isAvailable(def) then
				order += 1
				makeRow(order, def)
				if not selected then
					selected = def.id
				end
				if def.id == selected then
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

	-- ---- toggling ---------------------------------------------------------------
	local function setOpen(open)
		isOpen = open
		Sfx.play(isOpen and "panelOpen" or "panelClose")
		panel.Visible = isOpen
		if isOpen then
			statusLabel.Text = ""
			refresh()
		end
	end

	local function toggle()
		setOpen(not isOpen)
	end

	local openBtn = TopRightMenu.addButton("Craft (V)", 3)
	openBtn.Name = "CraftButton"

	openBtn.Activated:Connect(toggle)
	closeBtn.Activated:Connect(function()
		setOpen(false)
	end)

	ContextActionService:BindAction("ToggleCrafting", function(_, inputState)
		if inputState == Enum.UserInputState.Begin then
			toggle()
		end
		return Enum.ContextActionResult.Pass
	end, false, Enum.KeyCode.V)

	-- ---- live data ----------------------------------------------------------------
	Remotes.get("InventoryUpdated").OnClientEvent:Connect(function(entries)
		inventory = entries or {}
		if isOpen then
			refresh()
		end
	end)
	task.spawn(function()
		local entries = Remotes.getFunction("RequestInventory"):InvokeServer()
		if typeof(entries) == "table" and #inventory == 0 then
			inventory = entries
		end
	end)

	local function readNearby()
		nearby = {}
		local raw = player:GetAttribute("NearbyStations")
		if typeof(raw) == "string" then
			for station in raw:gmatch("[^,]+") do
				nearby[station] = true
			end
		end
	end
	readNearby()
	player:GetAttributeChangedSignal("NearbyStations"):Connect(function()
		readNearby()
		if isOpen then
			refresh()
		end
	end)
end

return CraftUI
