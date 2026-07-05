-- Vendor NPCs: low-poly merchants with a ProximityPrompt that opens the
-- store UI on the client (OpenStore remote). Trades come back through the
-- StoreTrade RemoteFunction and are validated here — store carries the item,
-- the right price side exists, the player is actually near the vendor — then
-- orchestrated through PlayerService so gold and inventory stay authoritative
-- and persisted (buy: spend gold, add item, refund on full inventory;
-- sell: remove items, then pay out).
--
-- Store contents/prices are data (shared/Stores, overlaid from GET /content);
-- vendor placement is world layout and lives here in VENDOR_DEFS.

local Workspace = game:GetService("Workspace")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local ArtKit = require(Shared:WaitForChild("ArtKit"))
local Items = require(Shared:WaitForChild("Items"))
local Stores = require(Shared:WaitForChild("Stores"))
local Remotes = require(Shared:WaitForChild("Remotes"))
local PlayerService = require(script.Parent.PlayerService)

local VendorService = {}

-- Prompt range is 10; the trade check is looser so a step back mid-purchase
-- doesn't reject a click the player already lined up.
local MAX_TRADE_DISTANCE = 16
local MAX_TRADE_QUANTITY = 99

-- { storeId, name, position, facing? (degrees yaw; vendor looks along -Z) }
local VENDOR_DEFS = {
	{ storeId = "general_goods", name = "Marla the Trader", position = Vector3.new(-16, 0, -34), facing = 205 },
}

local vendorFolder
local vendorsByStore = {} -- [storeId] = { Vector3 positions, for the distance check }
local notifyRemote

local function groundY(x, z)
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	params.FilterDescendantsInstances = { vendorFolder }
	local result = Workspace:Raycast(Vector3.new(x, 200, z), Vector3.new(0, -1000, 0), params)
	return result and result.Position.Y or 0
end

local function buildVendor(def)
	local store = Stores.get(def.storeId)
	if not store then
		warn("[VendorService] no store def for " .. tostring(def.storeId))
		return
	end

	local y = groundY(def.position.X, def.position.Z)
	local origin = CFrame.new(def.position.X, y, def.position.Z)
		* CFrame.Angles(0, math.rad(def.facing or 0), 0)

	local model = ArtKit.build("Vendor_" .. def.storeId, origin, {
		-- torso first: the PrimaryPart anchors the prompt
		{ name = "Tunic", size = Vector3.new(1.8, 1.8, 1.0), offset = Vector3.new(0, 2.3, 0), color = "leather", primary = true },
		{ name = "Belt", size = Vector3.new(1.9, 0.3, 1.1), offset = Vector3.new(0, 1.7, 0), color = "gold" },
		{ name = "LegL", size = Vector3.new(0.6, 1.4, 0.6), offset = Vector3.new(-0.4, 0.7, 0), color = "leatherDark" },
		{ name = "LegR", size = Vector3.new(0.6, 1.4, 0.6), offset = Vector3.new(0.4, 0.7, 0), color = "leatherDark" },
		{ name = "ArmL", size = Vector3.new(0.5, 1.5, 0.5), offset = Vector3.new(-1.2, 2.4, 0), rot = Vector3.new(0, 0, 8), color = "leather" },
		{ name = "ArmR", size = Vector3.new(0.5, 1.5, 0.5), offset = Vector3.new(1.2, 2.4, 0), rot = Vector3.new(0, 0, -8), color = "leather" },
		{ name = "Head", size = Vector3.new(1.1, 1.1, 1.1), offset = Vector3.new(0, 3.85, 0), color = "skin" },
		{ name = "EyeL", size = Vector3.new(0.14, 0.22, 0.06), offset = Vector3.new(-0.24, 3.95, -0.56), color = "ink" },
		{ name = "EyeR", size = Vector3.new(0.14, 0.22, 0.06), offset = Vector3.new(0.24, 3.95, -0.56), color = "ink" },
		{ name = "HatBrim", size = Vector3.new(1.7, 0.15, 1.7), offset = Vector3.new(0, 4.45, 0), color = "leatherDark" },
		{ name = "HatTop", size = Vector3.new(1.0, 0.55, 1.0), offset = Vector3.new(0, 4.8, 0), color = "leatherDark" },
	})
	model.Parent = vendorFolder

	vendorsByStore[def.storeId] = vendorsByStore[def.storeId] or {}
	table.insert(vendorsByStore[def.storeId], model.PrimaryPart.Position)

	local prompt = Instance.new("ProximityPrompt")
	prompt.ActionText = "Trade"
	prompt.ObjectText = def.name
	prompt.HoldDuration = 0.25
	prompt.MaxActivationDistance = 10
	prompt.RequiresLineOfSight = false
	prompt.Parent = model.PrimaryPart

	local openStore = Remotes.get("OpenStore")
	prompt.Triggered:Connect(function(player)
		openStore:FireClient(player, {
			storeId = def.storeId,
			storeName = store.name,
			vendorName = def.name,
		})
	end)
end

-- Whether the player stands near any vendor running this store.
local function nearVendor(player, storeId)
	local positions = vendorsByStore[storeId]
	local character = player.Character
	local root = character and character:FindFirstChild("HumanoidRootPart")
	if not positions or not root then
		return false
	end
	for _, position in ipairs(positions) do
		if (root.Position - position).Magnitude <= MAX_TRADE_DISTANCE then
			return true
		end
	end
	return false
end

local function tradeMessage(verb, def, quantity, total)
	local label = quantity > 1 and (quantity .. "x " .. def.name) or def.name
	return verb .. " " .. label .. " for " .. total .. "g"
end

local function handleTrade(player, payload)
	if typeof(payload) ~= "table" then
		return { ok = false, error = "bad_request" }
	end
	local storeId = payload.storeId
	local itemId = payload.itemId
	local action = payload.action
	if
		typeof(storeId) ~= "string"
		or typeof(itemId) ~= "string"
		or (action ~= "buy" and action ~= "sell")
	then
		return { ok = false, error = "bad_request" }
	end

	local quantity = math.floor(tonumber(payload.quantity) or 1)
	quantity = math.clamp(quantity, 1, MAX_TRADE_QUANTITY)

	if not nearVendor(player, storeId) then
		return { ok = false, error = "too_far" }
	end

	local trade = Stores.trade(storeId, itemId)
	local def = Items.get(itemId)
	if not trade or not def then
		return { ok = false, error = "not_traded" }
	end
	if not def.stackable then
		quantity = 1
	end

	if action == "buy" then
		if not trade.buyPrice then
			return { ok = false, error = "not_traded" }
		end
		local total = trade.buyPrice * quantity
		if not PlayerService.spendGold(player, total) then
			return { ok = false, error = "no_gold" }
		end
		local added = PlayerService.addItem(player, itemId, quantity)
		if not added then
			PlayerService.addGold(player, total) -- refund; nothing was granted
			return { ok = false, error = "no_space" }
		end
		notifyRemote:FireClient(player, tradeMessage("Bought", def, quantity, total))
		return { ok = true }
	end

	if not trade.sellPrice then
		return { ok = false, error = "not_traded" }
	end
	if not PlayerService.removeItem(player, itemId, quantity) then
		return { ok = false, error = "no_items" }
	end
	local total = trade.sellPrice * quantity
	PlayerService.addGold(player, total)
	notifyRemote:FireClient(player, tradeMessage("Sold", def, quantity, total))
	return { ok = true }
end

function VendorService.start()
	notifyRemote = Remotes.get("Notify")

	vendorFolder = Instance.new("Folder")
	vendorFolder.Name = "Vendors"
	vendorFolder.Parent = Workspace

	for _, def in ipairs(VENDOR_DEFS) do
		buildVendor(def)
	end

	local storeTrade = Remotes.getFunction("StoreTrade")
	storeTrade.OnServerInvoke = handleTrade
end

return VendorService
