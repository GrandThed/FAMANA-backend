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

-- Save coarse fields { health, cell, position = {x,y,z} }. Returns bool.
function BackendService.savePlayer(userId, fields)
	local ok = request("POST", "/player/" .. tostring(userId) .. "/save", fields)
	return ok
end

-- Add an item. Returns (ok, updatedInventory).
function BackendService.addItem(userId, itemId, quantity)
	local ok, data = request(
		"POST",
		"/player/" .. tostring(userId) .. "/inventory/add",
		{ itemId = itemId, quantity = quantity }
	)
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

-- Fetch the player's current inventory (used to refresh after an admin edit).
function BackendService.getInventory(userId)
	local ok, data = request("GET", "/player/" .. tostring(userId) .. "/inventory")
	if ok and data then
		return data.inventory
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

return BackendService
