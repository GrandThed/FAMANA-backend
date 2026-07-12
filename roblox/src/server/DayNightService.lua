-- Ticks Lighting.ClockTime forward to create a day/night cycle. Lighting
-- properties replicate to clients automatically, so this is server-only and
-- needs no remotes.
--
-- Other server systems hook in via DayNightService.onChanged(fn) — same
-- decoupled-hook style as EnemyService.onKilled / PlayerService.onInventory
-- Changed — instead of cross-requiring this module and polling it. Anything
-- that just needs a one-off check (e.g. a spawn roll) can call
-- DayNightService.isNight() directly.
--
-- In-memory per server, same as the rest of "world state" (trees, enemies) —
-- no persistence, no cross-cell sync. Each cell's clock runs independently.

local Lighting = game:GetService("Lighting")
local RunService = game:GetService("RunService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local DayNight = require(Shared:WaitForChild("DayNight"))

local DayNightService = {}

local listeners = {} -- [n] = function(isNight: boolean)
local wasNight = nil -- nil until start() sets the initial state

-- In-game hours the clock advances per real second, derived from the
-- configured cycle length so DayNight.cycleLength is the only knob.
local HOURS_PER_SECOND = 24 / DayNight.cycleLength

function DayNightService.isNight()
	return DayNight.isNightAt(Lighting.ClockTime)
end

-- fn(isNight: boolean) — fires once immediately with the current state, then
-- again every time day flips to night or back. No unsubscribe yet, matching
-- the other one-shot hook registries in this codebase (e.g. onKilled).
function DayNightService.onChanged(fn)
	table.insert(listeners, fn)
	if wasNight ~= nil then
		fn(wasNight)
	end
end

local function fireIfChanged()
	local night = DayNightService.isNight()
	if night ~= wasNight then
		wasNight = night
		for _, fn in ipairs(listeners) do
			fn(night)
		end
	end
end

function DayNightService.start()
	Lighting.ClockTime = DayNight.dawn -- fresh server boots at sunrise, not pitch black
	wasNight = DayNightService.isNight()

	RunService.Heartbeat:Connect(function(dt)
		local newTime = Lighting.ClockTime + dt * HOURS_PER_SECOND
		if newTime >= 24 then
			newTime -= 24
		end
		Lighting.ClockTime = newTime
		fireIfChanged()
	end)
end

return DayNightService
