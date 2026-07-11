-- Client-side quick-bind registry for the hotbar, in THREE swappable pages.
-- Slots 0/1 are reserved for the equipped weapon/offhand (keys 1/2); slots
-- 2..9 (keys 3..0) are player-assigned binds: an itemId (InventoryUI: hover +
-- key) or a spell ("spell:<id>", auto-placed by SpellsClient / picked from
-- the hotbar's empty-slot list). Only the ACTIVE page renders; the switcher
-- at the right end of the hotbar cycles pages.
--
-- Binds persist across sessions: the server puts the saved structure
-- ({ active, pages }) in the player's `HotbarBinds` attribute (JSON) when the
-- profile loads, and every local change is pushed back through the
-- SetHotbarBinds remote so the backend saves it with the profile.

local Players = game:GetService("Players")
local HttpService = game:GetService("HttpService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Remotes = require(Shared:WaitForChild("Remotes"))

local player = Players.LocalPlayer

local HotbarBinds = {}

local PAGE_COUNT = 3
local FIRST_SLOT, LAST_SLOT = 2, 9

HotbarBinds.pageCount = PAGE_COUNT

local pages = { {}, {}, {} } -- [page][slot 2..9] = itemId or "spell:<id>"
local activePage = 1
local changed = Instance.new("BindableEvent")

HotbarBinds.changed = changed.Event

-- True once the saved map has been applied (or timed out). Systems that
-- auto-assign binds (SpellsClient placing new spells) must wait for this,
-- or their first push would overwrite the persisted binds server-side.
HotbarBinds.isReady = false

-- Yields until the saved binds landed (or `timeout` seconds passed).
function HotbarBinds.waitReady(timeout)
	local deadline = os.clock() + (timeout or 10)
	while not HotbarBinds.isReady and os.clock() < deadline do
		task.wait(0.1)
	end
	return HotbarBinds.isReady
end

local setBindsRemote -- resolved async below

local function push()
	if not setBindsRemote then
		return
	end
	-- JSON objects need string keys; the server sanitizes and persists it.
	local payload = { active = activePage, pages = {} }
	for p = 1, PAGE_COUNT do
		local map = {}
		for slot, value in pairs(pages[p]) do
			map[tostring(slot)] = value
		end
		payload.pages[p] = map
	end
	setBindsRemote:FireServer(payload)
end

function HotbarBinds.activePage()
	return activePage
end

function HotbarBinds.setActivePage(page)
	page = math.clamp(math.floor(page), 1, PAGE_COUNT)
	if page ~= activePage then
		activePage = page
		push()
		changed:Fire()
	end
end

function HotbarBinds.cyclePage()
	HotbarBinds.setActivePage(activePage % PAGE_COUNT + 1)
end

-- `page` defaults to the active one in all three accessors.
function HotbarBinds.set(slotIndex, value, page)
	local map = pages[page or activePage]
	if not map then
		return
	end
	-- One bind per value per page: rebinding moves it to the new key.
	for slot, existing in pairs(map) do
		if existing == value and slot ~= slotIndex then
			map[slot] = nil
		end
	end
	map[slotIndex] = value
	push()
	changed:Fire()
end

function HotbarBinds.get(slotIndex, page)
	local map = pages[page or activePage]
	return map and map[slotIndex]
end

-- Clears a slot (e.g. when its item is no longer in the inventory).
function HotbarBinds.clear(slotIndex, page)
	local map = pages[page or activePage]
	if map and map[slotIndex] ~= nil then
		map[slotIndex] = nil
		push()
		changed:Fire()
	end
end

-- Seed from the saved structure once the server publishes it (no push: this
-- is the server's own state coming back to us). Accepts both the current
-- { active, pages } shape and the legacy flat one-page map.
task.spawn(function()
	setBindsRemote = Remotes.get("SetHotbarBinds")

	-- 2026-07 English rename: spell ids persisted in pre-rename binds
	-- translate on load; the next push re-saves the new ids. (Item-id and
	-- trait-id legacies translate backend-side — see inventory.js LEGACY_IDS.)
	local LEGACY_SPELL_IDS = {
		toque_curativo = "healing_touch",
		bendicion = "blessing",
		renacimiento = "revival",
		golpe_sagrado = "holy_strike",
		represalia = "reprisal",
		juicio_divino = "divine_judgment",
		purificar = "purify",
		vinculo_espiritual = "spirit_link",
		intervencion = "intervention",
	}

	local function applyMap(target, map)
		for key, value in pairs(map) do
			local slot = tonumber(key)
			if slot and slot >= FIRST_SLOT and slot <= LAST_SLOT and typeof(value) == "string" then
				local spellId = value:match("^spell:(.+)$")
				if spellId and LEGACY_SPELL_IDS[spellId] then
					value = "spell:" .. LEGACY_SPELL_IDS[spellId]
				end
				target[slot] = value
			end
		end
	end

	local function apply(raw)
		if typeof(raw) ~= "string" or raw == "" then
			return false
		end
		local ok, decoded = pcall(HttpService.JSONDecode, HttpService, raw)
		if not ok or typeof(decoded) ~= "table" then
			return false
		end
		if typeof(decoded.pages) == "table" then
			for p = 1, PAGE_COUNT do
				if typeof(decoded.pages[p]) == "table" then
					applyMap(pages[p], decoded.pages[p])
				end
			end
			local active = tonumber(decoded.active)
			if active and active >= 1 and active <= PAGE_COUNT then
				activePage = math.floor(active)
			end
		else
			applyMap(pages[1], decoded)
		end
		changed:Fire()
		return true
	end

	if apply(player:GetAttribute("HotbarBinds")) then
		HotbarBinds.isReady = true
	else
		local conn
		conn = player:GetAttributeChangedSignal("HotbarBinds"):Connect(function()
			if apply(player:GetAttribute("HotbarBinds")) then
				HotbarBinds.isReady = true
				conn:Disconnect()
			end
		end)
	end
end)

return HotbarBinds
