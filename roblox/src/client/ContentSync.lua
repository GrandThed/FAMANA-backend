-- Applies backend-served content defs on the client. The server's
-- ContentService publishes the GET /content payload as JSON in the
-- ContentData StringValue; overlaying it here keeps client-side reads
-- (thumbnails, tooltips, grid footprints, reach) consistent with what the
-- server plays by. An empty value means no backend content — the Luau
-- mirror in shared/Items.lua stays in effect.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local HttpService = game:GetService("HttpService")

local Items = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Items"))

local ContentSync = {}

function ContentSync.start()
	task.spawn(function()
		local holder = ReplicatedStorage:WaitForChild("ContentData", 30)
		if not holder then
			return -- server without ContentService (shouldn't happen post-deploy)
		end

		local function apply()
			if holder.Value == "" then
				return
			end
			local ok, content = pcall(function()
				return HttpService:JSONDecode(holder.Value)
			end)
			if ok then
				Items.apply(content)
			end
		end

		holder:GetPropertyChangedSignal("Value"):Connect(apply)
		apply()
	end)
end

return ContentSync
