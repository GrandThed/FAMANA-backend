-- Fetches game-content defs from the backend at boot and overlays them onto
-- the Luau mirrors (Items.apply), then publishes the raw payload through a
-- ContentData StringValue in ReplicatedStorage so clients (including late
-- joiners) can apply the same overlay — see client/ContentSync.lua. If the
-- backend is unreachable the game keeps running on the built-in mirror, the
-- same fail-safe as everything else backend-related.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local HttpService = game:GetService("HttpService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Items = require(Shared:WaitForChild("Items"))
local Config = require(Shared:WaitForChild("Config"))

local BackendService = require(script.Parent:WaitForChild("BackendService"))

local ATTEMPTS = 3

local ContentService = {}

function ContentService.start()
	-- Created empty before the fetch so clients always have something to wait
	-- on; "" means "no backend content" and they stay on their mirror.
	local holder = Instance.new("StringValue")
	holder.Name = "ContentData"
	holder.Value = ""
	holder.Parent = ReplicatedStorage

	task.spawn(function()
		for attempt = 1, ATTEMPTS do
			local content = BackendService.getContent()
			if content then
				if not Items.apply(content) then
					warn("[ContentService] malformed content payload; staying on the mirror")
					return
				end

				-- Grid dims are structural (stored stack positions assume
				-- them) — a mismatch means the deploy and the Place disagree.
				local grid = content.grid
				if
					grid
					and (grid.width ~= Config.inventoryGrid.width or grid.height ~= Config.inventoryGrid.height)
				then
					warn(
						"[ContentService] backend grid "
							.. grid.width .. "x" .. grid.height
							.. " != Config.inventoryGrid "
							.. Config.inventoryGrid.width .. "x" .. Config.inventoryGrid.height
					)
				end

				holder.Value = HttpService:JSONEncode(content)
				print("[ContentService] applied backend content " .. tostring(content.version))
				return
			end
			task.wait(2 * attempt)
		end
		warn("[ContentService] backend content unavailable; running on the built-in mirror")
	end)
end

return ContentService
