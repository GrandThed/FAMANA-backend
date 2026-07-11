-- Owns player persistence: load on join (create if new), autosave, save on
-- leave. Holds the authoritative in-memory profile cache for the server.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local HttpService = game:GetService("HttpService")

local BackendService = require(script.Parent.BackendService)

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared:WaitForChild("Config"))
local Items = require(Shared:WaitForChild("Items"))
local Remotes = require(Shared:WaitForChild("Remotes"))
local GridConfig = require(Shared:WaitForChild("GridConfig"))
local Classes = require(Shared:WaitForChild("Classes"))
local Spells = require(Shared:WaitForChild("Spells"))

local PlayerService = {}

-- xp required to go from `level` to `level + 1`.
local function xpToNext(level)
	local Leveling = Config.PlayerLeveling
	return Leveling.baseXp + (level - 1) * Leveling.xpPerLevel
end
PlayerService.xpToNext = xpToNext

-- [userId] = { health, maxHealth, gold, cell, position = {x,y,z}, inventory = {...}, _temporary? }
local cache = {}

-- Persisted client preferences (the options menu): [key] = allowed values.
-- Anything outside this whitelist is dropped on load AND on the remote.
local SETTING_VALUES = {
	traitTracker = { compact = true, minimal = true }, -- SpellTrackerUI layout
}

local function sanitizeSettings(raw)
	local clean = {}
	if typeof(raw) == "table" then
		for key, allowed in pairs(SETTING_VALUES) do
			local value = raw[key]
			if typeof(value) == "string" and allowed[value] then
				clean[key] = value
			end
		end
	end
	return clean
end

local inventoryUpdated -- RemoteEvent
local requestInventory -- RemoteFunction
local levelUpRemote -- RemoteEvent, resolved in start()

-- Other services (ClassService, for HP/Mana caps that scale with level) can
-- hook into level-ups here instead of PlayerService requiring them directly
-- (that would create a require cycle, since ClassService already requires
-- PlayerService).
local levelUpHandlers = {}
function PlayerService.registerLevelUpHandler(fn)
	table.insert(levelUpHandlers, fn)
end

function PlayerService.get(player)
	return cache[player.UserId]
end

-- Camp furniture layout persistence (see CampFurnitureService.lua). These
-- work by ownerUserId rather than a Player instance because a camp can be
-- torn down (expired) while its owner is offline — unlike the rest of
-- PlayerService, which only ever touches the online cache.

-- Returns the owner's saved layout ({} if they never had one). Prefers the
-- online cache (authoritative if they're connected); falls back to a direct
-- backend read for offline owners.
function PlayerService.getCampLayout(ownerUserId)
	local profile = cache[ownerUserId]
	if profile then
		return profile.campLayout or {}
	end
	local data = BackendService.getPlayer(ownerUserId)
	return (data and typeof(data.campLayout) == "table") and data.campLayout or {}
end

-- Persists a new layout for ownerUserId, online or not: updates the cache
-- (so a same-session replant sees it immediately, with no backend round
-- trip) AND always writes through to the backend (so it survives the owner
-- reconnecting, or the server restarting).
function PlayerService.setCampLayout(ownerUserId, layoutData)
	local profile = cache[ownerUserId]
	if profile then
		profile.campLayout = layoutData
	end
	BackendService.savePlayer(ownerUserId, { campLayout = layoutData })
end

-- Server-side listeners notified whenever a player's inventory changes
-- (e.g. ToolService rebuilding hotbar tools). Decouples PlayerService from
-- the systems that react to inventory changes.
local inventoryListeners = {}

function PlayerService.onInventoryChanged(fn)
	table.insert(inventoryListeners, fn)
end

function PlayerService.pushInventory(player)
	local profile = cache[player.UserId]
	if profile and inventoryUpdated then
		inventoryUpdated:FireClient(player, profile.inventory)
	end
	for _, fn in ipairs(inventoryListeners) do
		task.spawn(fn, player)
	end
end

local function loadProfile(player)
	local userId = player.UserId
	local data, err = BackendService.getPlayer(userId)

	if not data and err == "not_found" then
		data = BackendService.createPlayer(userId, player.Name)
	end

	if not data then
		-- Backend unreachable or errored: use a temporary profile so the player
		-- can still play. Marked _temporary so we never persist over real data.
		warn("[PlayerService] Using temporary profile for " .. player.Name .. " (backend unavailable).")
		data = {
			gold = 0,
			cell = GridConfig.currentCell(),
			position = { x = 0, y = 0, z = 0 },
			inventory = {},
			_temporary = true,
		}
	end

	-- Profiles saved before the gold column existed come back without it.
	data.gold = data.gold or 0
	player:SetAttribute("Gold", data.gold)

	-- Profiles saved before leveling existed come back without it.
	data.level = data.level or 1
	data.xp = data.xp or 0

	-- Profiles saved before the class system existed come back without
	-- currentClass/classLevels. Migrate: seed the default class's track from
	-- the old flat level/xp so nobody loses progress, then everyone else
	-- starts fresh at level 1.
	if not Classes.isValid(data.currentClass) then
		data.currentClass = Classes.DEFAULT
	end
	data.classLevels = typeof(data.classLevels) == "table" and data.classLevels or {}
	for _, classId in ipairs(Classes.order) do
		if not data.classLevels[classId] then
			if classId == data.currentClass then
				data.classLevels[classId] = { level = data.level, xp = data.xp }
			else
				data.classLevels[classId] = { level = 1, xp = 0 }
			end
		end
	end

	-- Mirror the active class's level/xp onto the flat fields/attributes so
	-- the rest of the game (HUD, LevelUpUI) doesn't need to know classes exist.
	local activeLv = data.classLevels[data.currentClass]
	data.level = activeLv.level
	data.xp = activeLv.xp

	player:SetAttribute("Class", data.currentClass)
	player:SetAttribute("Level", data.level)
	player:SetAttribute("Xp", data.xp)
	player:SetAttribute("XpToNext", xpToNext(data.level))

	-- Hotbar quick binds (keys 3–0) persist with the profile as THREE
	-- swappable pages ({ active, pages }); the client seeds its HotbarBinds
	-- registry from this attribute. Legacy flat maps become page 1.
	local binds = typeof(data.hotbarBinds) == "table" and data.hotbarBinds or {}
	if typeof(binds.pages) ~= "table" then
		binds = { active = 1, pages = { binds, {}, {} } }
	end
	for p = 1, 3 do
		binds.pages[p] = typeof(binds.pages[p]) == "table" and binds.pages[p] or {}
	end
	local active = tonumber(binds.active)
	binds.active = (active and active >= 1 and active <= 3) and math.floor(active) or 1
	-- Fresh profiles (nothing ever bound anywhere) start with the gathering
	-- tools on keys 3/4 of the first page.
	local anyBind = false
	for p = 1, 3 do
		if next(binds.pages[p]) ~= nil then
			anyBind = true
			break
		end
	end
	if not anyBind then
		binds.pages[1] = { ["2"] = "axe_basic", ["3"] = "pickaxe_basic" }
	end
	data.hotbarBinds = binds
	player:SetAttribute("HotbarBinds", HttpService:JSONEncode(binds))

	-- Client preferences (trait tracker layout, ...) travel like the binds:
	-- published as JSON for the client's PlayerSettings module, pushed back
	-- through SetPlayerSettings, saved with the profile.
	data.settings = sanitizeSettings(data.settings)
	player:SetAttribute("PlayerSettings", HttpService:JSONEncode(data.settings))

	-- Quest progress ({ [questId] = { status, objectives } }, same shape
	-- QuestService used to keep purely in memory). Profiles saved before
	-- this existed come back without it.
	data.questProgress = typeof(data.questProgress) == "table" and data.questProgress or {}

	-- Which quest the quest log has marked as tracked ("" = none). Kept as
	-- an empty string rather than nil so it always round-trips through
	-- JSONEncode/the backend save — a nil table field just vanishes instead
	-- of clearing the stored value.
	data.trackedQuestId = typeof(data.trackedQuestId) == "string" and data.trackedQuestId or ""

	-- Saved camp furniture layout (see CampFurnitureService.lua). Profiles
	-- saved before this existed come back without it.
	data.campLayout = typeof(data.campLayout) == "table" and data.campLayout or {}

	-- This Place represents a specific cell; record it so saves reflect reality.
	data.cell = GridConfig.currentCell()

	-- If the player arrived via a border crossing, spawn them at the entry edge
	-- instead of their saved position from the previous cell.
	local joinData = player:GetJoinData()
	local teleportData = joinData and joinData.TeleportData
	if teleportData and teleportData.entryEdge then
		local entry = GridConfig.entryPoint(teleportData.entryEdge)
		data.position = { x = entry.X, y = entry.Y, z = entry.Z }
	end

	cache[userId] = data
	return data
end

-- Add/remove go through the backend (source of truth), then update the cache
-- and notify the client. With `partial`, stackables fill whatever grid space
-- exists (drop pickups). `meta` marks a rolled item instance (never stacks).
-- Returns (ok, addedCount).
function PlayerService.addItem(player, itemId, quantity, partial, meta)
	local profile = cache[player.UserId]
	if not profile or profile._temporary then
		return false, 0
	end
	local ok, inventory, added = BackendService.addItem(player.UserId, itemId, quantity, partial, meta)
	if ok and (not partial or (added or 0) > 0) then
		profile.inventory = inventory
		PlayerService.pushInventory(player)
		return true, added or quantity
	end
	return false, 0
end

-- Total quantity of `itemId` currently owned across every stack (main grid +
-- equipped). Used for pickup toasts ("+1 Slime Goo (5)") so they can show a
-- running total without the caller needing to scan the inventory itself.
function PlayerService.getItemCount(player, itemId)
	local profile = cache[player.UserId]
	if not profile then
		return 0
	end
	local total = 0
	for _, stack in ipairs(profile.inventory) do
		if stack.itemId == itemId then
			total += stack.quantity
		end
	end
	return total
end

-- Move a stack between/within containers (the drag & drop verb). The backend
-- validates placement; on success the cache and client are refreshed.
-- Returns (ok, errorCode).
function PlayerService.moveItem(player, from, to)
	local profile = cache[player.UserId]
	if not profile or profile._temporary then
		return false, "offline"
	end
	local ok, inventory, errorCode = BackendService.moveItem(player.UserId, from, to)
	if ok then
		profile.inventory = inventory
		PlayerService.pushInventory(player)
		return true
	end
	return false, errorCode
end

-- Removes the whole stack at `ref` so it can be thrown on the ground.
-- The backend validates the position. Returns (ok, itemId, quantity, meta) —
-- the caller (DropService) is responsible for spawning the ground drop
-- (carrying the meta so rolled items survive the round trip).
function PlayerService.dropItem(player, ref)
	local profile = cache[player.UserId]
	if not profile or profile._temporary then
		return false
	end
	local ok, inventory, itemId, quantity, meta = BackendService.dropItem(player.UserId, ref)
	if ok and itemId then
		profile.inventory = inventory
		PlayerService.pushInventory(player)
		return true, itemId, quantity, meta
	end
	return false
end

-- Repack the main grid (the Sort button).
function PlayerService.sortInventory(player)
	local profile = cache[player.UserId]
	if not profile or profile._temporary then
		return false
	end
	local ok, inventory = BackendService.sortInventory(player.UserId)
	if ok then
		profile.inventory = inventory
		PlayerService.pushInventory(player)
		return true
	end
	return false
end

-- Re-fetch the inventory from the backend and push it to the client + tools.
-- Used to reflect out-of-band changes (e.g. an admin edit) on an online player.
function PlayerService.refreshInventory(player)
	local profile = cache[player.UserId]
	if not profile or profile._temporary then
		return
	end
	local inventory = BackendService.getInventory(player.UserId)
	if inventory then
		profile.inventory = inventory
		PlayerService.pushInventory(player)
	end
end

function PlayerService.removeItem(player, itemId, quantity)
	local profile = cache[player.UserId]
	if not profile or profile._temporary then
		return false
	end
	local ok, inventory = BackendService.removeItem(player.UserId, itemId, quantity)
	if ok then
		profile.inventory = inventory
		PlayerService.pushInventory(player)
		return true
	end
	return false
end

-- Settles a vendor deal atomically (docs/VENDOR_UI.md §5): the backend
-- lands the gold delta + item removes + adds in one transaction, or none
-- of it. plan = { goldDelta, removes, adds } — already validated and
-- priced by VendorService. Gold lives in this cache between autosaves, so
-- the cached balance is flushed to the backend first: the transaction's
-- no-negative-gold check must run against the real number, not the last
-- autosave's. Returns (ok, errorCode).
function PlayerService.executeDeal(player, plan)
	local profile = cache[player.UserId]
	if not profile or profile._temporary then
		return false, "offline"
	end
	if not BackendService.savePlayer(player.UserId, { gold = profile.gold }) then
		return false, "offline"
	end
	local ok, result = BackendService.deal(player.UserId, plan)
	if not ok then
		return false, typeof(result) == "string" and result or "offline"
	end
	profile.gold = result.gold or profile.gold
	player:SetAttribute("Gold", profile.gold)
	profile.inventory = result.inventory or profile.inventory
	PlayerService.pushInventory(player)
	return true
end

-- Gold is a live server-authoritative stat (like health): mutate it here,
-- mirror it to the Gold attribute for UI, and let autosave/leave persist it.
function PlayerService.addGold(player, amount)
	local profile = cache[player.UserId]
	if not profile or amount <= 0 then
		return false
	end
	profile.gold = profile.gold + amount
	player:SetAttribute("Gold", profile.gold)
	return true
end

-- Returns false (and changes nothing) if the player can't afford it.
function PlayerService.spendGold(player, amount)
	local profile = cache[player.UserId]
	if not profile or amount <= 0 or profile.gold < amount then
		return false
	end
	profile.gold = profile.gold - amount
	player:SetAttribute("Gold", profile.gold)
	return true
end

-- Grants XP (e.g. from an enemy kill or, later, a quest reward), rolling
-- over into as many level-ups as the amount covers. Each level-up re-derives
-- HP/Mana caps (see shared/Classes.lua statsAtLevel, wired via
-- registerLevelUpHandler below) on top of the persisted level/xp + toast.
-- XP is per-class: it only advances the currently active class's own
-- level/xp track (profile.classLevels[currentClass]). profile.level/xp keep
-- mirroring that active track so the rest of the game stays unaware classes
-- exist at all.
function PlayerService.addXp(player, amount)
	local profile = cache[player.UserId]
	local Leveling = Config.PlayerLeveling
	if not profile or amount <= 0 or profile.level >= Leveling.maxLevel then
		return
	end

	local lv = profile.classLevels[profile.currentClass]

	lv.xp += amount
	local leveledUp = false
	while lv.level < Leveling.maxLevel and lv.xp >= xpToNext(lv.level) do
		lv.xp -= xpToNext(lv.level)
		lv.level += 1
		leveledUp = true
	end
	if lv.level >= Leveling.maxLevel then
		lv.xp = 0 -- capped: stop accruing rather than show a bar past 100%
	end

	profile.level = lv.level
	profile.xp = lv.xp

	player:SetAttribute("Level", profile.level)
	player:SetAttribute("Xp", profile.xp)
	player:SetAttribute("XpToNext", xpToNext(profile.level))

	if leveledUp then
		for _, fn in ipairs(levelUpHandlers) do
			task.spawn(fn, player)
		end
		if levelUpRemote then
			levelUpRemote:FireClient(player, profile.level)
		end
	end
end

-- Applies an admin-pushed stats update (see the backend's updateProgress:
-- the payload carries the final resolved gold/level/xp/currentClass/
-- classLevels) to the live profile + attributes — without it, the next
-- autosave would clobber the admin's edit with the stale cached values.
-- Returns (applied, classChanged); on a class change the caller
-- (AdminSyncService) respecs live stats through ClassService.
function PlayerService.applyStats(player, stats)
	local profile = cache[player.UserId]
	if not profile or profile._temporary or typeof(stats) ~= "table" then
		return false, false
	end

	if typeof(stats.gold) == "number" then
		profile.gold = stats.gold
		player:SetAttribute("Gold", profile.gold)
	end
	if typeof(stats.classLevels) == "table" then
		profile.classLevels = stats.classLevels
	end

	local classChanged = false
	if typeof(stats.currentClass) == "string" and Classes.isValid(stats.currentClass) then
		classChanged = profile.currentClass ~= stats.currentClass
		profile.currentClass = stats.currentClass
		profile.classLevels[profile.currentClass] = profile.classLevels[profile.currentClass]
			or { level = 1, xp = 0 }
		player:SetAttribute("Class", profile.currentClass)
	end

	if typeof(stats.level) == "number" and typeof(stats.xp) == "number" then
		local lv = profile.classLevels[profile.currentClass]
		lv.level = stats.level
		lv.xp = stats.xp
		profile.level = lv.level
		profile.xp = lv.xp
		player:SetAttribute("Level", profile.level)
		player:SetAttribute("Xp", profile.xp)
		player:SetAttribute("XpToNext", xpToNext(profile.level))
	end

	return true, classChanged
end

local function buildSaveFields(player)
	local profile = cache[player.UserId]
	if not profile then
		return nil
	end

	local character = player.Character
	if character then
		local root = character:FindFirstChild("HumanoidRootPart")
		local humanoid = character:FindFirstChildOfClass("Humanoid")
		if root then
			profile.position = { x = root.Position.X, y = root.Position.Y, z = root.Position.Z }
		end
		if humanoid and humanoid.Health > 0 then
			profile.health = math.floor(humanoid.Health + 0.5)
		end
	end

	return {
		health = profile.health,
		gold = profile.gold,
		level = profile.level,
		xp = profile.xp,
		currentClass = profile.currentClass,
		classLevels = profile.classLevels,
		hotbarBinds = profile.hotbarBinds,
		settings = profile.settings,
		questProgress = profile.questProgress,
		trackedQuestId = profile.trackedQuestId,
		campLayout = profile.campLayout,
		cell = profile.cell,
		position = profile.position,
	}
end

function PlayerService.save(player)
	local profile = cache[player.UserId]
	if not profile or profile._temporary then
		return
	end
	local fields = buildSaveFields(player)
	if fields then
		BackendService.savePlayer(player.UserId, fields)
	end
end

function PlayerService.start()
	inventoryUpdated = Remotes.get("InventoryUpdated")
	requestInventory = Remotes.getFunction("RequestInventory")
	levelUpRemote = Remotes.get("LevelUp")

	-- Client pulls its inventory once its UI is ready. The profile loads
	-- asynchronously (backend HTTP), and the client may ask before it's ready,
	-- so wait for it (up to a timeout) instead of returning an empty list.
	requestInventory.OnServerInvoke = function(player)
		local deadline = os.clock() + 10
		while not cache[player.UserId] and os.clock() < deadline do
			task.wait(0.1)
		end
		local profile = cache[player.UserId]
		return profile and profile.inventory or {}
	end

	-- Drag & drop from the client. Arguments are sanitized here (ints only);
	-- real placement validation happens on the backend.
	local moveItem = Remotes.getFunction("MoveItem")
	moveItem.OnServerInvoke = function(player, from, to)
		if typeof(from) ~= "table" or typeof(to) ~= "table" then
			return { ok = false, error = "bad_move" }
		end
		local function sanitize(ref, withRotation)
			local x, y = tonumber(ref.x), tonumber(ref.y)
			local containerId = ref.containerId
			if not x or not y or (containerId ~= "main" and containerId ~= "equipment") then
				return nil
			end
			local safe = { containerId = containerId, x = math.floor(x), y = math.floor(y) }
			if withRotation then
				safe.rotated = ref.rotated == true
			end
			return safe
		end
		local safeFrom = sanitize(from, false)
		local safeTo = sanitize(to, true)
		if not safeFrom or not safeTo then
			return { ok = false, error = "bad_move" }
		end
		local ok, errorCode = PlayerService.moveItem(player, safeFrom, safeTo)
		return { ok = ok, error = errorCode }
	end

	local sortInventory = Remotes.getFunction("SortInventory")
	sortInventory.OnServerInvoke = function(player)
		return { ok = PlayerService.sortInventory(player) }
	end

	-- The client pushes its full quick-bind structure ({ active, pages }) on
	-- every change; it's sanitized here and persisted with the next save
	-- (autosave/leave). A bind is either a spell ("spell:<id>") or a
	-- quick-bindable item (tools/consumables — weapons live on the 1/2 keys).
	local function validBind(bindValue)
		local spellId = Spells.fromBind(bindValue)
		if spellId then
			return Spells.get(spellId) ~= nil
		end
		local def = Items.get(bindValue)
		return def ~= nil and (def.type == "tool" or def.type == "consumable")
	end

	local setHotbarBinds = Remotes.get("SetHotbarBinds")
	setHotbarBinds.OnServerEvent:Connect(function(player, payload)
		local profile = cache[player.UserId]
		if not profile or typeof(payload) ~= "table" then
			return
		end
		local clean = { active = 1, pages = {} }
		local active = tonumber(payload.active)
		if active and active >= 1 and active <= 3 then
			clean.active = math.floor(active)
		end
		-- Legacy clients sent a flat one-page map; treat it as page 1.
		local pagesIn = typeof(payload.pages) == "table" and payload.pages or { payload }
		for p = 1, 3 do
			local map = {}
			local source = typeof(pagesIn[p]) == "table" and pagesIn[p] or {}
			local count = 0
			for key, bindValue in pairs(source) do
				local slot = tonumber(key)
				if slot and slot >= 2 and slot <= 9 and slot == math.floor(slot)
					and typeof(bindValue) == "string" and validBind(bindValue) then
					map[tostring(slot)] = bindValue
					count += 1
					if count >= 8 then
						break
					end
				end
			end
			clean.pages[p] = map
		end
		profile.hotbarBinds = clean
	end)

	-- The client pushes its whole preference map on change (SettingsUI);
	-- whitelisted keys/values only, persisted with the next save.
	local setSettings = Remotes.get("SetPlayerSettings")
	setSettings.OnServerEvent:Connect(function(player, payload)
		local profile = cache[player.UserId]
		if not profile then
			return
		end
		profile.settings = sanitizeSettings(payload)
	end)

	-- Load data BEFORE the character spawns so HealthService can restore HP/pos.
	Players.CharacterAutoLoads = false

	Players.PlayerAdded:Connect(function(player)
		loadProfile(player)
		-- Push the freshly-loaded inventory in case the client already asked.
		PlayerService.pushInventory(player)
		player:LoadCharacter()
	end)

	Players.PlayerRemoving:Connect(function(player)
		PlayerService.save(player)
		cache[player.UserId] = nil
	end)

	task.spawn(function()
		while true do
			task.wait(Config.autosaveInterval)
			for _, player in ipairs(Players:GetPlayers()) do
				PlayerService.save(player)
			end
		end
	end)

	game:BindToClose(function()
		for _, player in ipairs(Players:GetPlayers()) do
			PlayerService.save(player)
		end
		-- Give the final HTTP saves a moment to flush before shutdown.
		task.wait(2)
	end)
end

return PlayerService