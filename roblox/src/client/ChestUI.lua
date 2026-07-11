-- Camp chest screen: two panes — the CHEST grid (left) and YOUR PACK (right,
-- the main inventory grid), reusing the same ItemGrid component as the
-- inventory/store (docs/VENDOR_UI.md §6). Opens on OpenChest (chest
-- ProximityPrompt, see server/CampFurnitureService.lua).
--
-- Kept deliberately simpler than StoreUI's deal-building flow: there's no
-- price/deal to negotiate, just "move this stack to the other side" — click
-- a tile in your pack to deposit it, click a tile in the chest to withdraw
-- it. Every transfer is a whole-stack move, resolved by the server
-- (ChestDeposit / ChestWithdraw RemoteFunctions), which also pushes
-- ChestUpdated to everyone currently looking at the same chest so a party
-- doesn't see a stale view for long (each transfer refreshes it; there's no
-- live cursor/drag sync between simultaneous viewers — good enough for a
-- first version).

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared:WaitForChild("Config"))
local Remotes = require(Shared:WaitForChild("Remotes"))
local ClientState = require(script.Parent.ClientState)
local ItemGrid = require(script.Parent.ItemGrid)
local ItemTooltip = require(script.Parent.ItemTooltip)
local Theme = require(script.Parent.Theme)
local UIKit = require(script.Parent.UIKit)
local Sfx = require(script.Parent.Sfx)

local player = Players.LocalPlayer

local ChestUI = {}

local ERROR_TEXT = {
	no_space = "Not enough room in your inventory",
	chest_full = "Not enough room in the chest",
	too_far = "Too far from the chest",
	not_supported = "Can't store that in a chest yet",
	bad_line = "That item moved — try again",
	offline = "Backend unavailable",
	bad_request = "Something went wrong",
}

local CELL = Theme.Size.Cell
local PACK_COLS = Config.inventoryGrid.width
local PACK_ROWS = Config.inventoryGrid.height
local VISIBLE_ROWS = 12
local CLOSE_DISTANCE = 16 -- studs; walk away → the panel closes itself

local CHEST_X = 12
local PACK_GAP = 24
local PANE_TOP = 76

function ChestUI.start()
	local gui = Instance.new("ScreenGui")
	gui.Name = "ChestUI"
	gui.ResetOnSpawn = false
	gui.Enabled = true
	gui.Parent = player:WaitForChild("PlayerGui")

	-- Panel width/height depend on the chest's own grid size, so they're
	-- finalized on first open() rather than hardcoded here.
	local panel = Instance.new("Frame")
	panel.Position = UDim2.new(0.5, 0, 0.5, 0)
	panel.AnchorPoint = Vector2.new(0.5, 0.5)
	panel.Visible = false
	panel.Parent = gui
	UIKit.stylePanel(panel)
	UIKit.addShadow(panel)
	UIKit.autoScale(panel)

	local title = UIKit.titleBar(panel, "Chest", 36)

	local closeBtn = UIKit.closeButton(panel)
	closeBtn.Position = UDim2.new(1, -6, 0, 5)
	closeBtn.AnchorPoint = Vector2.new(1, 0)

	local statusLabel = UIKit.label(panel, "", 12, Theme.Semantic.Danger, Theme.Font.Body)
	statusLabel.Size = UDim2.new(0, 360, 0, 18)
	statusLabel.Position = UDim2.new(0, CHEST_X, 0, PANE_TOP - 22)
	statusLabel.TextWrapped = true

	local function header(text, x, w)
		local label = UIKit.sectionLabel(panel, text)
		label.Size = UDim2.new(0, w, 0, 18)
		label.Position = UDim2.new(0, x, 0, 52)
		label.TextXAlignment = Enum.TextXAlignment.Left
		return label
	end

	-- ---- state -----------------------------------------------------------
	local current = nil -- { chestId, columns, rows, position }
	local chestItems = {} -- last snapshot from the server
	local inventory = {}
	local busy = false

	local chestGrid, packGrid, chestHeader, packHeader

	local tooltip = ItemTooltip.create(gui, function()
		return panel.Visible
	end)

	local function setStatus(text)
		statusLabel.Text = text or ""
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

	local function refreshChest()
		chestGrid.render(chestItems)
	end

	local function refreshPack()
		packGrid.render(packEntries())
	end

	-- ---- transfers ---------------------------------------------------------
	local chestDeposit = Remotes.getFunction("ChestDeposit")
	local chestWithdraw = Remotes.getFunction("ChestWithdraw")

	local function withStatus(fn)
		if busy then
			return
		end
		busy = true
		setStatus(nil)
		local ok, result = pcall(fn)
		busy = false
		if not ok then
			setStatus("Something went wrong")
			return
		end
		if result and not result.ok then
			setStatus(ERROR_TEXT[result.error] or "Something went wrong")
		elseif result and result.ok then
			Sfx.play("uiClick")
		end
	end

	local function onPackClick(entry)
		if not current then
			return
		end
		withStatus(function()
			return chestDeposit:InvokeServer(current.chestId, { x = entry.x, y = entry.y })
		end)
	end

	local function onChestClick(entry)
		if not current then
			return
		end
		withStatus(function()
			return chestWithdraw:InvokeServer(current.chestId, entry.id)
		end)
	end

	local function hoverTip(entry)
		if not entry then
			tooltip.hide()
			return
		end
		tooltip.schedule(entry, {})
	end

	-- ---- panes (built once at fixed max size; chest columns/rows come from
	-- the server, but Config.CampFurniture keeps them constant in practice) --
	chestHeader = header("Chest", CHEST_X + 2, 200)
	chestGrid = ItemGrid.create(panel, { columns = 6, visibleRows = 6, canvasRows = 6 })
	chestGrid.frame.Position = UDim2.new(0, CHEST_X, 0, PANE_TOP)
	chestGrid.callbacks = { onClick = onChestClick, onHover = hoverTip }

	local packX = CHEST_X + 6 * CELL + 8 + PACK_GAP
	packHeader = header("Your pack", packX + 2, 200)
	packGrid = ItemGrid.create(panel, { columns = PACK_COLS, visibleRows = VISIBLE_ROWS, canvasRows = PACK_ROWS })
	packGrid.frame.Position = UDim2.new(0, packX, 0, PANE_TOP)
	packGrid.callbacks = { onClick = onPackClick, onHover = hoverTip }

	local panelW = packX + PACK_COLS * CELL + 8 + 12
	local panelH = PANE_TOP + math.max(6, VISIBLE_ROWS) * CELL + 20
	panel.Size = UDim2.new(0, panelW, 0, panelH)

	-- ---- open / close lifecycle --------------------------------------------
	local function close()
		current = nil
		panel.Visible = false
		ClientState.chestOpen = false
		tooltip.hide()
		Sfx.play("panelClose")
	end
	closeBtn.Activated:Connect(close)
	ClientState.closeChest = close

	Remotes.get("OpenChest").OnClientEvent:Connect(function(info)
		if typeof(info) ~= "table" then
			return
		end
		if ClientState.inventoryOpen and ClientState.closeInventory then
			ClientState.closeInventory()
		end
		if ClientState.storeOpen and ClientState.closeStore then
			ClientState.closeStore()
		end
		current = info
		chestItems = info.items or {}
		title.Text = "Chest"
		setStatus(nil)
		panel.Visible = true
		ClientState.chestOpen = true
		Sfx.play("panelOpen")
		refreshChest()
		refreshPack()
	end)

	Remotes.get("ChestUpdated").OnClientEvent:Connect(function(info)
		if typeof(info) ~= "table" or not current or info.chestId ~= current.chestId then
			return
		end
		chestItems = info.items or {}
		refreshChest()
	end)

	-- Walk away → close (the server enforces its own distance on transfers).
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

	Remotes.get("InventoryUpdated").OnClientEvent:Connect(function(entries)
		inventory = entries or {}
		if current then
			refreshPack()
		end
	end)
	task.spawn(function()
		local entries = Remotes.getFunction("RequestInventory"):InvokeServer()
		if typeof(entries) == "table" and #inventory == 0 then
			inventory = entries
		end
	end)
end

return ChestUI
