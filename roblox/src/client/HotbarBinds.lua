-- Client-side quick-bind registry for the hotbar.
-- Slots 0/1 are reserved for the equipped weapon/offhand (keys 1/2); slots
-- 2..9 (keys 3..0) are player-assigned binds: InventoryUI writes them (hover
-- an item + press the key), HudUI renders them and clears a bind when its
-- item leaves the inventory.
--
-- Binds persist across sessions: the server puts the saved map in the
-- player's `HotbarBinds` attribute (JSON) when the profile loads, and every
-- local change is pushed back through the SetHotbarBinds remote so the
-- backend saves it with the profile.

local Players = game:GetService("Players")
local HttpService = game:GetService("HttpService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Remotes = require(Shared:WaitForChild("Remotes"))

local player = Players.LocalPlayer

local HotbarBinds = {}

local binds = {} -- [hotbarSlotIndex 2..9] = itemId
local changed = Instance.new("BindableEvent")

HotbarBinds.changed = changed.Event

local setBindsRemote -- resolved async below

local function push()
	if not setBindsRemote then
		return
	end
	-- JSON objects need string keys; the server sanitizes and persists it.
	local payload = {}
	for slot, itemId in pairs(binds) do
		payload[tostring(slot)] = itemId
	end
	setBindsRemote:FireServer(payload)
end

function HotbarBinds.set(slotIndex, itemId)
	-- One bind per item: rebinding an item moves it to the new key.
	for slot, id in pairs(binds) do
		if id == itemId and slot ~= slotIndex then
			binds[slot] = nil
		end
	end
	binds[slotIndex] = itemId
	push()
	changed:Fire()
end

function HotbarBinds.get(slotIndex)
	return binds[slotIndex]
end

-- Clears a slot (e.g. when its item is no longer in the inventory).
function HotbarBinds.clear(slotIndex)
	if binds[slotIndex] ~= nil then
		binds[slotIndex] = nil
		push()
		changed:Fire()
	end
end

-- Seed from the saved map once the server publishes it (no push: this is
-- the server's own state coming back to us).
task.spawn(function()
	setBindsRemote = Remotes.get("SetHotbarBinds")

	local function apply(raw)
		if typeof(raw) ~= "string" or raw == "" then
			return false
		end
		local ok, decoded = pcall(HttpService.JSONDecode, HttpService, raw)
		if not ok or typeof(decoded) ~= "table" then
			return false
		end
		local any = false
		for key, itemId in pairs(decoded) do
			local slot = tonumber(key)
			if slot and slot >= 2 and slot <= 9 and typeof(itemId) == "string" then
				binds[slot] = itemId
				any = true
			end
		end
		if any then
			changed:Fire()
		end
		return true
	end

	if not apply(player:GetAttribute("HotbarBinds")) then
		local conn
		conn = player:GetAttributeChangedSignal("HotbarBinds"):Connect(function()
			if apply(player:GetAttribute("HotbarBinds")) then
				conn:Disconnect()
			end
		end)
	end
end)

return HotbarBinds
