-- Client-side spell registry. Tracks which spells the server says we know
-- (SpellsChanged remote / RequestSpells pull) and owns hotbar auto-placement:
--   * a spell that just unlocked goes into the next free hotbar slot (3–0);
--   * on login, if NO spell has ever been placed, the whole known list is
--     seeded in recommended order (server-sorted by hotbarPriority) — so
--     rearranged/removed spells aren't re-added behind the player's back.
-- HudUI reads isKnown() to dim binds for spells of a class you're not playing.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Spells = require(Shared:WaitForChild("Spells"))
local Remotes = require(Shared:WaitForChild("Remotes"))
local HotbarBinds = require(script.Parent.HotbarBinds)

local SpellsClient = {}

local known = {} -- [spellId] = true
local knownList = {} -- priority-sorted, as sent by the server
local changed = Instance.new("BindableEvent")

SpellsClient.changed = changed.Event

function SpellsClient.isKnown(spellId)
	return known[spellId] == true
end

function SpellsClient.list()
	return knownList
end

local FIRST_BIND_SLOT, LAST_BIND_SLOT = 2, 9

-- Whether the bind value already sits somewhere, on ANY page.
local function isBoundAnywhere(bindValue)
	for page = 1, HotbarBinds.pageCount do
		for slot = FIRST_BIND_SLOT, LAST_BIND_SLOT do
			if HotbarBinds.get(slot, page) == bindValue then
				return true
			end
		end
	end
	return false
end

local function anySpellBound()
	for page = 1, HotbarBinds.pageCount do
		for slot = FIRST_BIND_SLOT, LAST_BIND_SLOT do
			if Spells.fromBind(HotbarBinds.get(slot, page)) then
				return true
			end
		end
	end
	return false
end

-- Places each spell in the first free slot, filling page 1 first (the
-- defaults page), then 2, then 3. Everything full = the spell just isn't
-- placed; no replacement in v1.
local function autoPlace(spellIds)
	for _, spellId in ipairs(spellIds) do
		local bindValue = Spells.toBind(spellId)
		if not isBoundAnywhere(bindValue) then
			local placed = false
			for page = 1, HotbarBinds.pageCount do
				for slot = FIRST_BIND_SLOT, LAST_BIND_SLOT do
					if HotbarBinds.get(slot, page) == nil then
						HotbarBinds.set(slot, bindValue, page)
						placed = true
						break
					end
				end
				if placed then
					break
				end
			end
		end
	end
end

local function apply(payload, isInitial)
	if typeof(payload) ~= "table" then
		return
	end
	known = {}
	knownList = {}
	for _, spellId in ipairs(payload.known or {}) do
		if Spells.get(spellId) then
			known[spellId] = true
			table.insert(knownList, spellId)
		end
	end

	if typeof(payload.newlyUnlocked) == "table" then
		autoPlace(payload.newlyUnlocked)
	end
	-- First session with the spell system (or a fresh profile): seed the
	-- whole recommended loadout.
	if isInitial and not anySpellBound() then
		autoPlace(payload.recommended or knownList)
	end

	changed:Fire()
end

function SpellsClient.start()
	task.spawn(function()
		-- Don't touch binds until the persisted map arrived, or the first
		-- auto-place would push a spells-only map over the saved one. Pushes
		-- fired before we listen are covered by the RequestSpells pull below.
		HotbarBinds.waitReady(10)

		local spellsChanged = Remotes.get("SpellsChanged")
		spellsChanged.OnClientEvent:Connect(function(payload)
			apply(payload, false)
		end)

		local requestSpells = Remotes.getFunction("RequestSpells")
		local ok, payload = pcall(function()
			return requestSpells:InvokeServer()
		end)
		if ok then
			apply(payload, true)
		end
	end)
end

return SpellsClient
