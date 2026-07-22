-- Guild Bank screen: two 2D spatial grid panes — GUILD BANK (left) and YOUR PACK (right),
-- reusing the exact same ItemGrid component as the inventory and camp chest.
-- Supports click-to-transfer, right-click floating context menu, split-stack modal, and drag-and-drop.
-- Opens when interacting with a planted "Cofre de Gremio" in your camp.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local UserInputService = game:GetService("UserInputService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared:WaitForChild("Config"))
local Remotes = require(Shared:WaitForChild("Remotes"))
local Items = require(Shared:WaitForChild("Items"))
local ItemGrid = require(script.Parent.ItemGrid)
local ItemTooltip = require(script.Parent.ItemTooltip)
local Theme = require(script.Parent.Theme)
local UIKit = require(script.Parent.UIKit)
local Sfx = require(script.Parent.Sfx)

local player = Players.LocalPlayer

local GuildBankUI = {}

local CELL = Theme.Size.Cell
local PACK_COLS = Config.inventoryGrid.width
local PACK_ROWS = Config.inventoryGrid.height
local BANK_COLS = 6
local BANK_ROWS = 6
local VISIBLE_ROWS = 12

local BANK_X = 12
local PACK_GAP = 24
local PANE_TOP = 76

function GuildBankUI.start()
	local requestInventory = Remotes.getFunction("RequestInventory")
	local requestBank = Remotes.getFunction("RequestGuildBank")
	local bankDeposit = Remotes.get("GuildBankDeposit")
	local bankWithdraw = Remotes.get("GuildBankWithdraw")

	local gui = Instance.new("ScreenGui")
	gui.Name = "GuildBankUI"
	gui.ResetOnSpawn = false
	gui.DisplayOrder = 6
	gui.Parent = player:WaitForChild("PlayerGui")

	local panel = Instance.new("Frame")
	panel.Position = UDim2.new(0.5, 0, 0.5, 0)
	panel.AnchorPoint = Vector2.new(0.5, 0.5)
	panel.Visible = false
	panel.Parent = gui
	UIKit.stylePanel(panel)
	UIKit.addShadow(panel)
	UIKit.autoScale(panel)

	local title = UIKit.titleBar(panel, "Banco de Gremio", 36)

	local closeBtn = UIKit.closeButton(panel)
	closeBtn.Position = UDim2.new(1, -6, 0, 5)
	closeBtn.AnchorPoint = Vector2.new(1, 0)

	local statusLabel = UIKit.label(panel, "", 12, Theme.Semantic.Danger, Theme.Font.Body)
	statusLabel.Size = UDim2.new(0, 360, 0, 18)
	statusLabel.Position = UDim2.new(0, BANK_X, 0, PANE_TOP - 22)
	statusLabel.TextWrapped = true

	local function header(text, x, w)
		local label = UIKit.sectionLabel(panel, text)
		label.Size = UDim2.new(0, w, 0, 18)
		label.Position = UDim2.new(0, x, 0, 52)
		label.TextXAlignment = Enum.TextXAlignment.Left
		return label
	end

	local bankItems = {}
	local inventory = {}
	local busy = false

	local bankGrid, packGrid
	local tooltip = ItemTooltip.create(gui, function()
		return panel.Visible
	end)

	local function setStatus(text)
		statusLabel.Text = text or ""
	end

	-- Convert flat bank items [{ itemId, quantity }, ...] into grid-placed items
	local function layoutBankGrid(rawItems)
		local entries = {}
		local curX, curY = 0, 0
		for _, item in ipairs(rawItems) do
			local def = Items.get(item.itemId)
			local w = (def and def.size and def.size[1]) or 1
			local h = (def and def.size and def.size[2]) or 1
			if curX + w > BANK_COLS then
				curX = 0
				curY = curY + 1
			end
			table.insert(entries, {
				id = "bank_" .. item.itemId,
				itemId = item.itemId,
				quantity = item.quantity,
				x = curX,
				y = curY,
				meta = nil,
			})
			curX = curX + w
		end
		return entries
	end

	local function packEntries()
		local list = {}
		for _, entry in ipairs(inventory) do
			if entry.containerId == "main" then
				table.insert(list, entry)
			end
		end
		return list
	end

	local function refreshBank()
		bankGrid.render(layoutBankGrid(bankItems))
	end

	local function refreshPack()
		packGrid.render(packEntries())
	end

	local function refreshAll()
		task.spawn(function()
			local raw = requestBank:InvokeServer()
			if typeof(raw) == "table" then
				bankItems = raw
				refreshBank()
			end
			local inv = requestInventory:InvokeServer()
			if typeof(inv) == "table" then
				inventory = inv
				refreshPack()
			end
		end)
	end

	local function doDeposit(entry)
		if busy then
			return
		end
		busy = true
		setStatus(nil)
		bankDeposit:FireServer({ itemId = entry.itemId, quantity = entry.quantity or 1 })
		task.wait(0.25)
		refreshAll()
		busy = false
		Sfx.play("uiClick")
	end

	local function doWithdraw(entry)
		if busy then
			return
		end
		local iAmPrivileged = player:GetAttribute("GuildLeader") == true or player:GetAttribute("GuildOfficer") == true
		if not iAmPrivileged then
			setStatus("Solo oficiales o líderes pueden retirar del banco.")
			return
		end
		busy = true
		setStatus(nil)
		bankWithdraw:FireServer({ itemId = entry.itemId, quantity = entry.quantity or 1 })
		task.wait(0.25)
		refreshAll()
		busy = false
		Sfx.play("uiClick")
	end

	-- ---- Split Stack Modal (Stepper: [-] [ 12 ] [+], Mitad, Máx) -------------
	local splitModal = Instance.new("Frame")
	splitModal.Name = "SplitStackModal"
	splitModal.Size = UDim2.new(0, 260, 0, 190)
	splitModal.Position = UDim2.new(0.5, 0, 0.5, 0)
	splitModal.AnchorPoint = Vector2.new(0.5, 0.5)
	splitModal.Visible = false
	splitModal.ZIndex = 80
	splitModal.Parent = gui
	UIKit.stylePanel(splitModal)
	UIKit.addShadow(splitModal)
	UIKit.autoScale(splitModal)

	local splitModalTitle = UIKit.label(
		splitModal,
		"Elegir cantidad",
		Theme.Text.Title,
		Theme.Semantic.TextTitle,
		Theme.Font.DisplayBold
	)
	splitModalTitle.Size = UDim2.new(1, -40, 0, 26)
	splitModalTitle.Position = UDim2.new(0, 12, 0, 10)

	local splitModalClose = UIKit.closeButton(splitModal)
	splitModalClose.Position = UDim2.new(1, -6, 0, 6)
	splitModalClose.AnchorPoint = Vector2.new(1, 0)

	local splitItemLabel = UIKit.label(splitModal, "", Theme.Text.Sm, Theme.Semantic.TextMuted)
	splitItemLabel.Size = UDim2.new(1, -24, 0, 18)
	splitItemLabel.Position = UDim2.new(0, 12, 0, 40)

	local splitStepMinus = UIKit.ghostButton(splitModal, "-")
	splitStepMinus.Size = UDim2.new(0, 34, 0, 34)
	splitStepMinus.Position = UDim2.new(0, 12, 0, 66)

	local splitAmountBox = Instance.new("TextBox")
	splitAmountBox.Name = "SplitAmountBox"
	splitAmountBox.Size = UDim2.new(1, -152, 0, 34)
	splitAmountBox.Position = UDim2.new(0, 54, 0, 66)
	splitAmountBox.BackgroundColor3 = Theme.Semantic.SurfaceWell
	splitAmountBox.BorderSizePixel = 0
	splitAmountBox.FontFace = Theme.Font.BodyBold
	splitAmountBox.TextSize = Theme.Text.Lg
	splitAmountBox.TextColor3 = Theme.Semantic.TextBody
	splitAmountBox.TextXAlignment = Enum.TextXAlignment.Center
	splitAmountBox.Text = "1"
	splitAmountBox.ClearTextOnFocus = false
	splitAmountBox.ZIndex = 81
	splitAmountBox.Parent = splitModal

	local splitStepPlus = UIKit.ghostButton(splitModal, "+")
	splitStepPlus.Size = UDim2.new(0, 34, 0, 34)
	splitStepPlus.Position = UDim2.new(1, -46, 0, 66)

	local splitHalfBtn = UIKit.ghostButton(splitModal, "Mitad")
	splitHalfBtn.Size = UDim2.new(0, 110, 0, 26)
	splitHalfBtn.Position = UDim2.new(0, 12, 0, 108)

	local splitMaxBtn = UIKit.ghostButton(splitModal, "Máx")
	splitMaxBtn.Size = UDim2.new(0, 110, 0, 26)
	splitMaxBtn.Position = UDim2.new(1, -122, 0, 108)

	local splitConfirmBtn = UIKit.primaryButton(splitModal, "Confirmar")
	splitConfirmBtn.Size = UDim2.new(1, -24, 0, 32)
	splitConfirmBtn.Position = UDim2.new(0, 12, 1, -42)

	local splitTarget = nil
	local splitActionType = nil
	local splitMaxCap = 1

	local function clampAmount(n)
		n = math.floor(tonumber(n) or 1)
		return math.clamp(n, 1, math.max(splitMaxCap, 1))
	end

	local function setAmount(n)
		splitAmountBox.Text = tostring(clampAmount(n))
	end

	splitStepMinus.Activated:Connect(function()
		setAmount((tonumber(splitAmountBox.Text) or 1) - 1)
	end)
	splitStepPlus.Activated:Connect(function()
		setAmount((tonumber(splitAmountBox.Text) or 1) + 1)
	end)
	splitHalfBtn.Activated:Connect(function()
		setAmount(math.floor(splitMaxCap / 2))
	end)
	splitMaxBtn.Activated:Connect(function()
		setAmount(splitMaxCap)
	end)
	splitAmountBox.FocusLost:Connect(function()
		setAmount(splitAmountBox.Text)
	end)

	local function closeSplitModal()
		splitModal.Visible = false
		splitTarget = nil
		splitActionType = nil
	end
	splitModalClose.Activated:Connect(closeSplitModal)

	local function openSplitModal(entry, actionType)
		local def = Items.get(entry.itemId)
		splitTarget = entry
		splitActionType = actionType
		splitMaxCap = math.max(entry.quantity or 1, 1)
		splitItemLabel.Text = string.format(
			"%s — %s (x%d)",
			actionType == "deposit" and "Depositar" or "Retirar",
			def and def.name or entry.itemId,
			splitMaxCap
		)
		setAmount(splitMaxCap)
		splitModal.Visible = true
	end

	splitConfirmBtn.Activated:Connect(function()
		if not splitTarget or not splitActionType then
			closeSplitModal()
			return
		end
		local entry = { itemId = splitTarget.itemId, quantity = clampAmount(splitAmountBox.Text) }
		local action = splitActionType
		closeSplitModal()
		if action == "deposit" then
			doDeposit(entry)
		else
			doWithdraw(entry)
		end
	end)

	-- ---- Floating Context Menu (igual al inventario B) --------------------
	local contextMenu = Instance.new("Frame")
	contextMenu.Name = "GuildBankContextMenu"
	contextMenu.AutomaticSize = Enum.AutomaticSize.Y
	contextMenu.Size = UDim2.new(0, 150, 0, 0)
	contextMenu.BackgroundColor3 = Theme.Semantic.SurfaceWell
	contextMenu.BorderSizePixel = 0
	contextMenu.Visible = false
	contextMenu.ZIndex = 70
	contextMenu.Parent = gui

	local contextStroke = Instance.new("UIStroke")
	contextStroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
	contextStroke.Thickness = 1
	contextStroke.Color = Theme.Semantic.BorderDivider
	contextStroke.Parent = contextMenu

	UIKit.addShadow(contextMenu, 10)

	local contextLayout = Instance.new("UIListLayout")
	contextLayout.SortOrder = Enum.SortOrder.LayoutOrder
	contextLayout.Parent = contextMenu

	local function closeContextMenu()
		contextMenu.Visible = false
	end

	local function openContextMenu(entry, screenPos, actionType)
		tooltip.hide()
		for _, child in ipairs(contextMenu:GetChildren()) do
			if not child:IsA("UIListLayout") and not child:IsA("UIStroke") then
				child:Destroy()
			end
		end

		local quantity = entry.quantity or 1
		local isDeposit = actionType == "deposit"

		-- Botón 1: Depositar / Retirar Todo
		local allBtn = UIKit.ghostButton(contextMenu, isDeposit and "Depositar Todo" or "Retirar Todo")
		allBtn.Size = UDim2.new(1, 0, 0, 28)
		allBtn.ZIndex = 71
		allBtn.Activated:Connect(function()
			closeContextMenu()
			if isDeposit then
				doDeposit(entry)
			else
				doWithdraw(entry)
			end
		end)

		-- Botón 2: Depositar Cantidad / Retirar Cantidad (si quantity > 1)
		if quantity > 1 then
			local qtyBtn = UIKit.ghostButton(contextMenu, isDeposit and "Elegir cantidad..." or "Elegir cantidad...")
			qtyBtn.Size = UDim2.new(1, 0, 0, 28)
			qtyBtn.ZIndex = 71
			qtyBtn.Activated:Connect(function()
				closeContextMenu()
				openSplitModal(entry, actionType)
			end)
		end

		-- Position context menu near cursor, keeping it inside screen bounds
		local screenW = gui.AbsoluteSize.X
		local screenH = gui.AbsoluteSize.Y
		local menuW = 150
		local menuH = quantity > 1 and 60 or 32
		local posX = math.clamp(screenPos.X, 10, math.max(10, screenW - menuW - 10))
		local posY = math.clamp(screenPos.Y, 10, math.max(10, screenH - menuH - 10))

		contextMenu.Position = UDim2.new(0, posX, 0, posY)
		contextMenu.Visible = true
	end

	-- Dismiss context menu on click outside
	UserInputService.InputBegan:Connect(function(input)
		if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.MouseButton2 then
			if contextMenu.Visible then
				local mousePos = UserInputService:GetMouseLocation()
				local menuPos = contextMenu.AbsolutePosition
				local menuSize = contextMenu.AbsoluteSize
				if
					mousePos.X < menuPos.X
					or mousePos.X > menuPos.X + menuSize.X
					or mousePos.Y < menuPos.Y
					or mousePos.Y > menuPos.Y + menuSize.Y
				then
					closeContextMenu()
				end
			end
		end
	end)

	local function hoverTip(entry)
		if not entry then
			tooltip.hide()
			return
		end
		tooltip.schedule(entry, {})
	end

	-- ---- Panes -------------------------------------------------------------
	header("Banco de Gremio", BANK_X + 2, 200)
	bankGrid = ItemGrid.create(panel, { columns = BANK_COLS, visibleRows = BANK_ROWS, canvasRows = BANK_ROWS })
	bankGrid.frame.Position = UDim2.new(0, BANK_X, 0, PANE_TOP)
	bankGrid.callbacks = {
		onClick = function(entry)
			doWithdraw(entry)
		end,
		onRightClick = function(entry, screenPos)
			openContextMenu(entry, screenPos, "withdraw")
		end,
		onDragOut = function(entry, screenPos)
			if packGrid.containsPoint(screenPos) then
				doWithdraw(entry)
			end
		end,
		onHover = hoverTip,
	}

	local packX = BANK_X + BANK_COLS * CELL + 8 + PACK_GAP
	header("Tu Inventario", packX + 2, 200)
	packGrid = ItemGrid.create(panel, { columns = PACK_COLS, visibleRows = VISIBLE_ROWS, canvasRows = PACK_ROWS })
	packGrid.frame.Position = UDim2.new(0, packX, 0, PANE_TOP)
	packGrid.callbacks = {
		onClick = function(entry)
			doDeposit(entry)
		end,
		onRightClick = function(entry, screenPos)
			openContextMenu(entry, screenPos, "deposit")
		end,
		onDragOut = function(entry, screenPos)
			if bankGrid.containsPoint(screenPos) then
				doDeposit(entry)
			end
		end,
		onHover = hoverTip,
	}

	local panelW = packX + PACK_COLS * CELL + 8 + 12
	local panelH = PANE_TOP + math.max(BANK_ROWS, VISIBLE_ROWS) * CELL + 20
	panel.Size = UDim2.new(0, panelW, 0, panelH)

	-- ---- Lifecycle ---------------------------------------------------------
	local isOpen = false

	local function setOpen(open)
		isOpen = open
		panel.Visible = open
		splitModal.Visible = false
		contextMenu.Visible = false
		Sfx.play(open and "panelOpen" or "panelClose")
		if not open then
			tooltip.hide()
		else
			setStatus(nil)
			refreshAll()
		end
	end

	closeBtn.Activated:Connect(function()
		setOpen(false)
	end)

	function GuildBankUI.open()
		if not player:GetAttribute("GuildId") then
			return
		end
		setOpen(true)
	end

	function GuildBankUI.close()
		setOpen(false)
	end

	player:GetAttributeChangedSignal("GuildId"):Connect(function()
		if isOpen and not player:GetAttribute("GuildId") then
			setOpen(false)
		end
	end)

	Remotes.get("OpenGuildBank").OnClientEvent:Connect(function()
		GuildBankUI.open()
	end)

	Remotes.get("InventoryUpdated").OnClientEvent:Connect(function(entries)
		if isOpen and typeof(entries) == "table" then
			inventory = entries
			refreshPack()
		end
	end)
end

return GuildBankUI
