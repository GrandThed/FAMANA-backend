-- Serves LeaderboardUI's "GetLeaderboard" RemoteFunction by proxying to the
-- backend (BackendService.getLeaderboard — GET /leaderboards, see
-- backend/src/routes/leaderboards.js). Only the server holds the API key,
-- so this round-trip can't be skipped; a short per-metric cache keeps
-- several players opening the panel around the same time from hammering
-- the backend with identical queries.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Remotes = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Remotes"))
local BackendService = require(script.Parent.BackendService)

local CACHE_SECONDS = 15

local LeaderboardService = {}

local cache = {} -- [metricType] = { data = <response>, at = os.clock() }

function LeaderboardService.start()
	local getLeaderboard = Remotes.getFunction("GetLeaderboard")
	getLeaderboard.OnServerInvoke = function(_player, metricType)
		if typeof(metricType) ~= "string" then
			metricType = "level"
		end

		local cached = cache[metricType]
		if cached and (os.clock() - cached.at) < CACHE_SECONDS then
			return cached.data
		end

		local data = BackendService.getLeaderboard(metricType, 20)
		if data then
			cache[metricType] = { data = data, at = os.clock() }
			return data
		end
		-- Backend hiccup: serve a stale cache entry if we have one rather
		-- than leaving the panel empty.
		return cached and cached.data or { type = metricType, label = metricType, entries = {} }
	end
end

return LeaderboardService
