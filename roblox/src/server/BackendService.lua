-- Thin wrapper around HttpService for talking to the FAMANA backend.
-- Handles auth header, JSON encode/decode, and error classification.
-- Server-only: the API key never leaves this context.

local HttpService = game:GetService("HttpService")

local BackendConfig = require(script.Parent.BackendConfig)

local BackendService = {}

local warnedNoKey = false
local function getApiKey()
	local secret = script.Parent:FindFirstChild("Secret")
	if not secret then
		if not warnedNoKey then
			warn(
				"[BackendService] Missing 'Secret' ModuleScript. Create roblox/src/server/Secret.lua "
					.. "returning your backend API key. Backend calls will fail until then."
			)
			warnedNoKey = true
		end
		return nil
	end
	return require(secret)
end

-- Returns: ok (bool), data (decoded body or nil), statusCode (number or nil)
local function request(method, path, body)
	local apiKey = getApiKey()
	if not apiKey then
		return false, nil, nil
	end

	local ok, response = pcall(function()
		return HttpService:RequestAsync({
			Url = BackendConfig.baseUrl .. path,
			Method = method,
			Headers = {
				["Content-Type"] = "application/json",
				["X-Api-Key"] = apiKey,
			},
			Body = body and HttpService:JSONEncode(body) or nil,
		})
	end)

	if not ok then
		-- pcall failure = HttpService threw (e.g. HTTP not enabled, DNS failure)
		warn("[BackendService] request error on " .. method .. " " .. path .. ": " .. tostring(response))
		return false, nil, nil
	end

	local decoded
	if response.Body and #response.Body > 0 then
		local decodeOk, result = pcall(function()
			return HttpService:JSONDecode(response.Body)
		end)
		if decodeOk then
			decoded = result
		end
	end

	local status = response.StatusCode
	if status >= 200 and status < 300 then
		return true, decoded, status
	end
	local errMsg = decoded and decoded.error or response.Body
	warn(string.format("[BackendService] %s %s -> %d: %s", method, path, status, tostring(errMsg)))
	return false, decoded, status
end

-- Load a player. Returns (profile) on success, (nil, "not_found") if new,
-- or (nil, "error") on backend failure (caller must NOT overwrite on error).
function BackendService.getPlayer(userId)
	local ok, data, status = request("GET", "/player/" .. tostring(userId))
	if ok then
		return data
	elseif status == 404 then
		return nil, "not_found"
	end
	return nil, "error"
end

-- Create a default player (starter items). Returns profile or nil.
function BackendService.createPlayer(userId, username)
	local ok, data = request("POST", "/player", { id = userId, username = username })
	if ok then
		return data
	end
	return nil
end

-- Save coarse fields { health, gold, cell, position = {x,y,z} }. Returns bool.
function BackendService.savePlayer(userId, fields)
	local ok = request("POST", "/player/" .. tostring(userId) .. "/save", fields)
	return ok
end

-- Add an item. With `partial`, stackables fill whatever grid space exists
-- instead of failing outright. `meta` marks a rolled item instance
-- ({ itemLevel, traits }; the backend sanitizes and stores it per row).
-- Returns (ok, updatedInventory, added).
function BackendService.addItem(userId, itemId, quantity, partial, meta)
	local ok, data = request(
		"POST",
		"/player/" .. tostring(userId) .. "/inventory/add",
		{ itemId = itemId, quantity = quantity, partial = partial == true, meta = meta }
	)
	if ok and data then
		return true, data.inventory, data.added
	end
	return false, nil, 0
end

-- Move a stack (drag & drop): from/to are { containerId, x, y[, rotated] }.
-- Returns (ok, updatedInventory, errorCode).
function BackendService.moveItem(userId, from, to)
	local ok, data = request(
		"POST",
		"/player/" .. tostring(userId) .. "/inventory/move",
		{ from = from, to = to }
	)
	if ok and data then
		return true, data.inventory, nil
	end
	return false, nil, data and data.error or nil
end

-- Remove the whole stack at a position (thrown on the ground by the game).
-- ref = { containerId, x, y }. Returns (ok, updatedInventory, itemId,
-- quantity, meta) — meta rides along so a thrown rolled item keeps its roll.
function BackendService.dropItem(userId, ref)
	local ok, data = request("POST", "/player/" .. tostring(userId) .. "/inventory/drop", ref)
	if ok and data then
		return true, data.inventory, data.itemId, data.quantity, data.meta
	end
	return false, nil, nil, nil, nil
end

-- Split `quantity` off the stack at `ref` into a new stack at the first
-- free grid spot (the "Dividir" action) — stays in the inventory, doesn't
-- touch the ground. ref = { containerId, x, y }. Returns (ok,
-- updatedInventory, errorCode).
function BackendService.splitStack(userId, ref, quantity)
	local ok, data = request(
		"POST",
		"/player/" .. tostring(userId) .. "/inventory/split",
		{ containerId = ref.containerId, x = ref.x, y = ref.y, quantity = quantity }
	)
	if ok and data then
		return true, data.inventory, nil
	end
	return false, nil, data and data.error or nil
end

-- Repack the main grid (the Sort button). Returns (ok, updatedInventory).
function BackendService.sortInventory(userId)
	-- Non-empty body so Fastify's JSON parser doesn't reject the POST.
	local ok, data = request("POST", "/player/" .. tostring(userId) .. "/inventory/sort", { sort = true })
	if ok and data then
		return true, data.inventory
	end
	return false, nil
end

-- Remove an item. Returns (ok, updatedInventory).
function BackendService.removeItem(userId, itemId, quantity)
	local ok, data = request(
		"POST",
		"/player/" .. tostring(userId) .. "/inventory/remove",
		{ itemId = itemId, quantity = quantity }
	)
	if ok and data then
		return true, data.inventory
	end
	return false, nil
end

-- Settle an atomic vendor deal (docs/VENDOR_UI.md §5.2): gold delta + item
-- removes + adds land in ONE backend transaction, or none of them do.
-- plan = { goldDelta, removes = {...}, adds = {...} }.
-- Returns (ok, data) on success where data = { gold, inventory }, or
-- (false, errorCode) — the backend's reason on a 409, nil on transport
-- failure.
function BackendService.deal(userId, plan)
	local ok, data = request("POST", "/player/" .. tostring(userId) .. "/deal", plan)
	if ok and data then
		return true, data
	end
	return false, data and data.error or nil
end

-- Fetch the player's current inventory (used to refresh after an admin edit).
function BackendService.getInventory(userId)
	local ok, data = request("GET", "/player/" .. tostring(userId) .. "/inventory")
	if ok and data then
		return data.inventory
	end
	return nil
end

-- Fetch the game-content payload (items, starter kit, grid dims, equipment
-- slots + a version hash). Returns the decoded table or nil.
function BackendService.getContent()
	local ok, data = request("GET", "/content")
	if ok then
		return data
	end
	return nil
end

-- Top-N players by `metricType` ("level" | "gold" | "kills", see backend
-- routes/leaderboards.js). Returns { type, label, entries = { { rank,
-- playerId, username, score }, ... } } or nil on failure.
function BackendService.getLeaderboard(metricType, limit)
	local path = "/leaderboards?type=" .. HttpService:UrlEncode(metricType)
	if limit then
		path ..= "&limit=" .. tostring(math.floor(limit))
	end
	local ok, data = request("GET", path)
	if ok then
		return data
	end
	return nil
end

-- Drain pending events for the given online user ids. Returns a list of
-- { playerId, kind, message, payload } or nil on failure.
function BackendService.pollEvents(userIds)
	local ok, data = request("POST", "/player/events", { userIds = userIds })
	if ok and data then
		return data.events
	end
	return nil
end

-- Guild currently held by `userId`, or nil if they're not in one. Second
-- return is true only on an actual transport/decode failure (so callers can
-- tell "no guild" apart from "backend unreachable, don't overwrite state").
function BackendService.getGuildForPlayer(userId)
	local ok, data = request("GET", "/guild/player/" .. tostring(userId))
	if ok and data then
		return data.guild, false
	end
	return nil, true
end

-- Full guild by id (roster included), or nil if it doesn't exist / on
-- failure. Used by GuildService.getGuildInfo for the panel's roster read.
function BackendService.getGuildById(guildId)
	local ok, data = request("GET", "/guild/" .. tostring(guildId))
	if ok and data then
		return data.guild
	end
	return nil
end

-- Returns (guild) on success, (nil, errorCode) on failure — errorCode is the
-- backend's reason string ("name_taken", "already_in_guild", ...) on a 4xx,
-- nil on transport failure.
function BackendService.createGuild(leaderId, name, tag)
	local ok, data = request("POST", "/guild", { leaderId = leaderId, name = name, tag = tag })
	if ok and data then
		return data.guild
	end
	return nil, data and data.error or nil
end

function BackendService.joinGuild(guildId, userId)
	local ok, data = request("POST", "/guild/" .. tostring(guildId) .. "/join", { playerId = userId })
	if ok and data then
		return data.guild
	end
	return nil, data and data.error or nil
end

function BackendService.kickFromGuild(guildId, requesterId, targetId)
	local ok, data = request(
		"POST",
		"/guild/" .. tostring(guildId) .. "/kick",
		{ requesterId = requesterId, targetId = targetId }
	)
	if ok and data then
		return data.guild
	end
	return nil, data and data.error or nil
end

-- Returns (disbanded: bool, guild: table?) on success, (nil, errorCode) on
-- failure. `guild` is nil when disbanded is true.
function BackendService.leaveGuild(guildId, userId)
	local ok, data = request("POST", "/guild/" .. tostring(guildId) .. "/leave", { playerId = userId })
	if ok and data then
		return data.disbanded == true, data.guild
	end
	return nil, data and data.error or nil
end

-- All settlements with a current owner: { { settlementId, guildId,
-- claimedAt, graceUntil }, ... }. Called on server start to paint initial
-- ownership; SettlementService keeps its own copy in sync after that from
-- local claim/kill events rather than re-polling.
function BackendService.listSettlementClaims()
	local ok, data = request("GET", "/settlements")
	if ok and data then
		return data.claims
	end
	return nil
end

-- Reports a guardian/challenger kill: `guildId` takes ownership of
-- `settlementId`, credited to `killerUserId`. Returns (claim) on success,
-- (nil, "in_grace") if the backend rejected it as still-protected (should be
-- rare — SettlementService should already be enforcing the grace window
-- before it even lets a challenger die), (nil, "error") on transport
-- failure.
function BackendService.claimSettlement(settlementId, guildId, killerUserId, graceSeconds)
	local ok, data = request(
		"POST",
		"/settlements/" .. settlementId .. "/claim",
		{ guildId = guildId, killerId = killerUserId, graceSeconds = graceSeconds }
	)
	if ok and data then
		return data.claim
	end
	return nil, (data and data.error) or "error"
end

return BackendService