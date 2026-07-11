-- Day/night cycle constants + pure helpers. Shared client/server so both
-- sides can independently derive "is it night" from Lighting.ClockTime
-- without a remote round-trip — Lighting properties already replicate to
-- clients on their own, DayNightService (server) is the only thing that
-- actually ticks the clock forward.
--
-- Numbers here are first-pass placeholders, tune freely once we can playtest
-- the feel (see DayNightService.lua for how they're consumed).

local DayNight = {}

-- One full day/night cycle, in real seconds.
DayNight.cycleLength = 20 * 60 -- 20 minutes

-- Lighting.ClockTime boundaries (0-24). Night = [nightStart, 24) U [0, dawn).
-- `dusk` isn't used for the isNight check (kept soft) — it's there for later
-- UI/ambience that wants to react to the transition starting, not just the
-- hard cutover.
DayNight.dawn = 6 -- sun fully up; server also boots at this time
DayNight.dusk = 18 -- sun starts going down
DayNight.nightStart = 20 -- fully dark

-- Flat fraction bonus applied to gathering yield while it's night (see
-- GatheringService, which registers this as a normal registerYieldBonus
-- hook — same extensibility point traits/passives use). Placeholder value,
-- calibrate once it's playtested.
DayNight.nightGatherYieldBonus = 0.25 -- +25% wood/stone/etc per swing at night

-- Single source of truth for "is it night right now" — every system that
-- cares (EnemyService night spawns, future camp/lighting hooks, etc.) should
-- go through this instead of re-deriving its own ClockTime check, so nothing
-- drifts out of sync.
function DayNight.isNightAt(clockTime)
	return clockTime >= DayNight.nightStart or clockTime < DayNight.dawn
end

return DayNight
