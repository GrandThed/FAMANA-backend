-- Render-only item grid view (docs/VENDOR_UI.md §6): footprint-sized tiles
-- in the InventoryUI recipe (viewport thumb, rarity stroke/glow, qty badge)
-- plus store extras — price/barter chip (top-left), lock badge (top-right),
-- dimming.
-- The store screen drives all three of its panes with this one module;
-- InventoryUI's grid migrates onto it later (consolidation decided).
--
--   local grid = ItemGrid.create(parent, {
--       columns = 8,            -- grid width in cells
--       visibleRows = 11,       -- pane height in cells
--       canvasRows = 30,        -- fixed scroll canvas; omit → auto-size to
--                               -- content (still min visibleRows); equal to
--                               -- visibleRows → plain frame, no scrolling
--       zIndex = 3,
--   })
--   grid.frame                  -- position/size me (width fits columns)
--   grid.render(entries)        -- diffed; entries: { itemId, quantity, x, y,
--                               --   rotated?, meta?, chip?, chipColor?,
--                               --   dimmed?, locked? }
--   grid.callbacks = { onClick(entry, shift), onDragOut(entry, screenPos),
--                      onHover(entry | nil) }
--
-- Tiles are diffed across renders (thumbnails built once, like InventoryUI).
-- A press that travels > 6 px becomes a drag: a ghost thumb follows the
-- cursor and onDragOut fires with the release position — the HOST decides
-- what zone that landed in. Locked tiles (barter costs riding a deal) fire
-- no callbacks. There is no drag-WITHIN: placement is always first-fit via
-- ItemGrid.findSpot (the §4 auto-placement — unrotated, then rotated).

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Items = require(Shared:WaitForChild("Items"))
local ItemModels = require(Shared:WaitForChild("ItemModels"))
local Rarity = require(Shared:WaitForChild("Rarity"))
local Theme = require(script.Parent.Theme)
local UIKit = require(script.Parent.UIKit)

local player = Players.LocalPlayer
local mouse = player:GetMouse()

local CELL = Theme.Size.Cell
local DRAG_THRESHOLD = 6 -- px of travel before a press becomes a drag

local ItemGrid = {}

-- ---- packing ----------------------------------------------------------------

local function footprintFits(entries, x, y, w, h, columns, rows)
	if x < 0 or y < 0 or x + w > columns or y + h > rows then
		return false
	end
	for _, entry in ipairs(entries) do
		local ew, eh = Items.sizeFor(entry.itemId, entry.rotated)
		if entry.x < x + w and x < entry.x + ew and entry.y < y + h and y < entry.y + eh then
			return false
		end
	end
	return true
end

-- First position where `itemId` fits among `entries` (each with x/y/rotated
-- set), unrotated then rotated — the shared "optimal space" rule. Returns
-- (x, y, rotated) or nil when the grid is full.
function ItemGrid.findSpot(entries, itemId, columns, rows)
	local w, h = Items.sizeFor(itemId, false)
	local orientations = (w == h) and { false } or { false, true }
	for _, rotated in ipairs(orientations) do
		local tw, th = Items.sizeFor(itemId, rotated)
		for y = 0, rows - th do
			for x = 0, columns - tw do
				if footprintFits(entries, x, y, tw, th, columns, rows) then
					return x, y, rotated
				end
			end
		end
	end
	return nil
end

-- Packs `items` in order into a fresh grid (the stock pane's shelf layout),
-- assigning x/y/rotated on each. Returns (placed, overflow).
function ItemGrid.packFirstFit(items, columns, rows)
	local placed = {}
	local overflow = {}
	for _, item in ipairs(items) do
		local x, y, rotated = ItemGrid.findSpot(placed, item.itemId, columns, rows)
		if x then
			item.x, item.y, item.rotated = x, y, rotated
			placed[#placed + 1] = item
		else
			overflow[#overflow + 1] = item
		end
	end
	return placed, overflow
end

-- ---- view ----------------------------------------------------------------

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

local function makeViewport(parent)
	local thumb = Instance.new("ViewportFrame")
	thumb.Size = UDim2.new(1, -6, 1, -6)
	thumb.Position = UDim2.new(0, 3, 0, 3)
	thumb.BackgroundTransparency = 1
	thumb.Ambient = Color3.fromRGB(180, 180, 190)
	thumb.LightColor = Color3.new(1, 1, 1)
	thumb.Parent = parent
	return thumb
end

function ItemGrid.create(parent, opts)
	local columns = opts.columns
	local visibleRows = opts.visibleRows
	local canvasRows = opts.canvasRows
	local autoCanvas = canvasRows == nil
	local scrollable = autoCanvas or canvasRows > visibleRows
	local baseZ = opts.zIndex or 3

	local frame
	if scrollable then
		frame = Instance.new("ScrollingFrame")
		frame.ScrollBarThickness = 6
		frame.ScrollingDirection = Enum.ScrollingDirection.Y
		frame.CanvasSize = UDim2.new(0, 0, 0, (canvasRows or visibleRows) * CELL)
	else
		frame = Instance.new("Frame")
	end
	frame.Size = UDim2.new(0, columns * CELL + (scrollable and 8 or 0), 0, visibleRows * CELL)
	frame.BackgroundColor3 = Theme.Semantic.SurfaceWell
	frame.BorderSizePixel = 0
	frame.Parent = parent

	local frameStroke = Instance.new("UIStroke")
	frameStroke.Thickness = 1
	frameStroke.Color = Theme.Semantic.BorderHair
	frameStroke.Parent = frame

	-- Cell hairlines under the tiles (redrawn when the canvas grows).
	local linesLayer = Instance.new("Frame")
	linesLayer.BackgroundTransparency = 1
	linesLayer.Size = UDim2.new(0, columns * CELL, 1, 0)
	linesLayer.ZIndex = baseZ - 2
	linesLayer.Parent = frame

	local drawnRows = 0
	local function drawLines(rows)
		if rows <= drawnRows then
			return
		end
		drawnRows = rows
		for _, child in ipairs(linesLayer:GetChildren()) do
			child:Destroy()
		end
		for c = 1, columns - 1 do
			local line = Instance.new("Frame")
			line.Size = UDim2.new(0, 1, 0, rows * CELL)
			line.Position = UDim2.new(0, c * CELL, 0, 0)
			line.BackgroundColor3 = Theme.Semantic.BorderHair
			line.BackgroundTransparency = 0.5
			line.BorderSizePixel = 0
			line.ZIndex = baseZ - 2
			line.Parent = linesLayer
		end
		for r = 1, rows - 1 do
			local line = Instance.new("Frame")
			line.Size = UDim2.new(0, columns * CELL, 0, 1)
			line.Position = UDim2.new(0, 0, 0, r * CELL)
			line.BackgroundColor3 = Theme.Semantic.BorderHair
			line.BackgroundTransparency = 0.5
			line.BorderSizePixel = 0
			line.ZIndex = baseZ - 2
			line.Parent = linesLayer
		end
	end
	drawLines(canvasRows or visibleRows)

	local grid = { frame = frame, columns = columns, callbacks = {} }

	-- One live drag session per grid (a second press cancels into it).
	local dragSession

	local function endDragSession(fireDrop)
		local session = dragSession
		if not session then
			return
		end
		dragSession = nil
		if session.stepConn then
			session.stepConn:Disconnect()
		end
		if session.endConn then
			session.endConn:Disconnect()
		end
		if session.ghost then
			session.ghost:Destroy()
		end
		if fireDrop and session.dragging and grid.callbacks.onDragOut then
			grid.callbacks.onDragOut(session.entry, Vector2.new(mouse.X, mouse.Y))
		elseif fireDrop and not session.dragging and grid.callbacks.onClick then
			local shift = UserInputService:IsKeyDown(Enum.KeyCode.LeftShift)
				or UserInputService:IsKeyDown(Enum.KeyCode.RightShift)
			grid.callbacks.onClick(session.entry, shift)
		end
	end

	local function beginDragSession(record)
		endDragSession(false)
		local session = { entry = record.entry, start = Vector2.new(mouse.X, mouse.Y) }
		dragSession = session

		session.stepConn = RunService.RenderStepped:Connect(function()
			local pos = Vector2.new(mouse.X, mouse.Y)
			if not session.dragging and (pos - session.start).Magnitude > DRAG_THRESHOLD then
				session.dragging = true
				if grid.callbacks.onHover then
					grid.callbacks.onHover(nil) -- kill any pending tooltip mid-drag
				end
				-- Ghost thumb chasing the cursor; the real tile stays put —
				-- drops are settled by the host, not previewed here. Absolute
				-- size because the ghost lives at the ScreenGui root, outside
				-- the panel's UIScale.
				local ghost = Instance.new("Frame")
				ghost.Size = UDim2.new(0, record.frame.AbsoluteSize.X, 0, record.frame.AbsoluteSize.Y)
				ghost.BackgroundColor3 = Theme.Color.Ink900
				ghost.BackgroundTransparency = 0.35
				ghost.BorderSizePixel = 0
				ghost.ZIndex = 90
				ghost.Parent = frame:FindFirstAncestorWhichIsA("ScreenGui")
				local ghostStroke = Instance.new("UIStroke")
				ghostStroke.Thickness = 1
				ghostStroke.Color = Theme.Semantic.BorderSlot
				ghostStroke.Parent = ghost
				local thumb = makeViewport(ghost)
				thumb.ZIndex = 91
				ItemModels.preview(thumb, session.entry.itemId)
				session.ghost = ghost
			end
			if session.ghost then
				session.ghost.Position = UDim2.new(0, pos.X - session.ghost.AbsoluteSize.X / 2, 0, pos.Y - session.ghost.AbsoluteSize.Y / 2)
			end
		end)
		session.endConn = UserInputService.InputEnded:Connect(function(input)
			if input.UserInputType == Enum.UserInputType.MouseButton1 then
				endDragSession(true)
			end
		end)
	end

	-- ---- tiles (diffed: reused across renders, thumbnails built once) ------
	local tileRecords = {}

	local function createTileRecord(entry)
		local def = Items.get(entry.itemId)
		local record = { itemId = entry.itemId, entry = entry }

		local tile = Instance.new("TextButton")
		tile.Text = ""
		tile.AutoButtonColor = false
		tile.BackgroundColor3 = Theme.Color.Ink750
		tile.BackgroundTransparency = 0.15
		tile.BorderSizePixel = 0
		tile.ZIndex = baseZ
		tile.Parent = frame
		record.frame = tile

		local stroke = Instance.new("UIStroke")
		-- TextButton: Contextual would stroke the empty TEXT (see InventoryUI).
		stroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
		stroke.Thickness = 1
		stroke.Color = Theme.Semantic.BorderSlot
		stroke.Parent = tile
		record.stroke = stroke

		record.glow = UIKit.addGlow(tile, Color3.new(1, 1, 1), 0.78)
		if record.glow then
			record.glow.Visible = false
			record.glow.ZIndex = baseZ
		end

		local thumb = makeViewport(tile)
		thumb.ZIndex = baseZ + 1
		record.thumb = thumb
		if not ItemModels.preview(thumb, entry.itemId) then
			local fallback = makeLabel(tile, def and def.name or entry.itemId, 11)
			fallback.Size = UDim2.new(1, -6, 1, -6)
			fallback.Position = UDim2.new(0, 3, 0, 3)
			fallback.TextWrapped = true
			fallback.ZIndex = baseZ + 1
		end

		local qty = makeLabel(tile, "", 13, Theme.Semantic.Currency)
		qty.Size = UDim2.new(1, -6, 0, 14)
		qty.Position = UDim2.new(0, 3, 1, -16)
		qty.TextXAlignment = Enum.TextXAlignment.Right
		qty.ZIndex = baseZ + 2
		record.qty = qty

		-- Price/barter chip, top-left (qty keeps bottom-right).
		local chip = makeLabel(tile, "", Theme.Text.Xs, Theme.Semantic.Currency)
		chip.BackgroundTransparency = 0.2
		chip.BackgroundColor3 = Theme.Color.Ink900
		chip.AutomaticSize = Enum.AutomaticSize.X
		chip.Size = UDim2.new(0, 0, 0, 14)
		chip.Position = UDim2.new(0, 2, 0, 2)
		chip.Visible = false
		chip.ZIndex = baseZ + 2
		record.chip = chip

		-- Lock badge (barter costs riding a "You get" item), top-right —
		-- the chip owns the top-left corner.
		local lock = makeLabel(tile, "🔒", 11, Theme.Semantic.TextMuted)
		lock.Size = UDim2.new(0, 14, 0, 14)
		lock.Position = UDim2.new(1, -16, 0, 2)
		lock.Visible = false
		lock.ZIndex = baseZ + 2
		record.lock = lock

		tile.MouseEnter:Connect(function()
			if grid.callbacks.onHover and not record.entry.locked then
				grid.callbacks.onHover(record.entry)
			end
		end)
		tile.MouseLeave:Connect(function()
			if grid.callbacks.onHover then
				grid.callbacks.onHover(nil)
			end
		end)
		tile.InputBegan:Connect(function(input)
			if input.UserInputType == Enum.UserInputType.MouseButton1 and not record.entry.locked then
				beginDragSession(record)
			elseif input.UserInputType == Enum.UserInputType.MouseButton2 and not record.entry.locked then
				if grid.callbacks.onRightClick then
					grid.callbacks.onRightClick(record.entry, Vector2.new(input.Position.X, input.Position.Y))
				end
			end
		end)

		table.insert(tileRecords, record)
		return record
	end

	local function updateTileRecord(record, entry)
		record.entry = entry
		local w, h = Items.sizeFor(entry.itemId, entry.rotated)
		record.frame.Size = UDim2.new(0, w * CELL - 2, 0, h * CELL - 2)
		record.frame.Position = UDim2.new(0, entry.x * CELL + 1, 0, entry.y * CELL + 1)
		record.qty.Text = (entry.quantity or 1) > 1 and tostring(entry.quantity) or ""

		local def = Items.get(entry.itemId)
		local rarity = Rarity.forEntry(entry, def)
		record.stroke.Color = rarity.color
		if record.glow then
			record.glow.Visible = rarity.hasGlow and not entry.dimmed
			record.glow.ImageColor3 = rarity.glowColor
		end

		record.chip.Visible = entry.chip ~= nil
		record.chip.Text = entry.chip and (" " .. entry.chip .. " ") or ""
		record.chip.TextColor3 = entry.chipColor or Theme.Semantic.Currency
		record.lock.Visible = entry.locked == true

		local dim = entry.dimmed and 0.5 or 0
		record.thumb.ImageTransparency = dim
		record.frame.BackgroundTransparency = entry.dimmed and 0.5 or 0.15
		record.stroke.Transparency = dim
		record.qty.TextTransparency = dim
		record.chip.TextTransparency = dim
	end

	-- Diff render, same matching order as InventoryUI: exact spot first, then
	-- any leftover tile of the same item (keeps its thumbnail), then create;
	-- leftovers are destroyed.
	function grid.render(entries)
		endDragSession(false)
		for _, record in ipairs(tileRecords) do
			record.used = false
		end
		local unmatched = {}
		for _, entry in ipairs(entries) do
			local exact
			for _, record in ipairs(tileRecords) do
				if
					not record.used
					and record.itemId == entry.itemId
					and record.entry.x == entry.x
					and record.entry.y == entry.y
				then
					exact = record
					break
				end
			end
			if exact then
				exact.used = true
				updateTileRecord(exact, entry)
			else
				unmatched[#unmatched + 1] = entry
			end
		end
		for _, entry in ipairs(unmatched) do
			local match
			for _, record in ipairs(tileRecords) do
				if not record.used and record.itemId == entry.itemId then
					match = record
					break
				end
			end
			if not match then
				match = createTileRecord(entry)
			end
			match.used = true
			updateTileRecord(match, entry)
		end
		for i = #tileRecords, 1, -1 do
			local record = tileRecords[i]
			if not record.used then
				record.frame:Destroy()
				table.remove(tileRecords, i)
			end
		end

		if autoCanvas and scrollable then
			local maxRow = visibleRows
			for _, entry in ipairs(entries) do
				local _, h = Items.sizeFor(entry.itemId, entry.rotated)
				maxRow = math.max(maxRow, entry.y + h)
			end
			frame.CanvasSize = UDim2.new(0, 0, 0, maxRow * CELL)
			drawLines(maxRow)
		end
	end

	-- Whether a screen point sits inside this grid's frame (drop-zone test
	-- for the host; scale-aware because it uses absolute geometry).
	function grid.containsPoint(screenPos)
		local topLeft = frame.AbsolutePosition
		local size = frame.AbsoluteSize
		return screenPos.X >= topLeft.X
			and screenPos.X <= topLeft.X + size.X
			and screenPos.Y >= topLeft.Y
			and screenPos.Y <= topLeft.Y + size.Y
	end

	return grid
end

return ItemGrid
