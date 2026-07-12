-- "Rested" — the reworked version of camp coziness (docs/CAMP_TIERS.md §3).
--
-- Used to grant extra HP regen scaled by decoration, straight from
-- CampFurnitureService. Reworked because HP regen already has too many
-- hands in the pot (Cleric's Devotion passive, Brawler's synergy bonus, the
-- generic `regen` trait stat — all feed the same
-- HealthService.registerBonusRegen hook), so a decoration-scaled regen
-- bonus mostly rewarded whoever already stacked regen the hardest, not
-- "did you bother decorating your camp."
--
-- New shape: while a player stands in a safe camp zone at night, they bank
-- rest time (faster the cozier that camp is — see
-- CampFurnitureService.cozinessRatio). Leaving the zone (or day breaking)
-- doesn't drain the bank instantly — restedUntil just stops being extended,
-- so it counts down in real time on its own. While restedUntil hasn't
-- passed yet, GatheringService's yield-bonus hook (registered below) grants
-- a flat bonus, same mechanism as the night gathering bonus.
--
-- This is the real choice the player makes: park it at a cozy camp all
-- night banking a long Rested buff, or go fight the (tougher, night-
-- boosted) mobs / gather the (better-yielding) nodes right now instead.

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared:WaitForChild("Config"))

local CampService = require(script.Parent.CampService)
local CampFurnitureService = require(script.Parent.CampFurnitureService)
local DayNightService = require(script.Parent.DayNightService)

local RestedService = {}

local RESTED = Config.Camp.rested

-- [userId] = os.clock() timestamp the Rested buff expires at. Absent/past
-- means not resting. In-memory only, same as the rest of camp state — a
-- server restart just means you're not Rested anymore, no big loss.
local restedUntil = {}

-- Recomputing this every frame for every player is pointless — resting is a
-- multi-minute action, a slow tick is imperceptible and cheap.
local TICK_INTERVAL = 1

function RestedService.isRested(player)
	local until_ = restedUntil[player.UserId]
	return until_ ~= nil and os.clock() < until_
end

local function tick(dt)
	local night = DayNightService.isNight()

	for _, player in ipairs(Players:GetPlayers()) do
		local character = player.Character
		local root = character and character:FindFirstChild("HumanoidRootPart")
		if night and root and CampService.isPositionSafeForPlayer(player, root.Position) then
			local camp = CampService.campFor(player)
			if camp then
				local coziness = CampFurnitureService.cozinessRatio(camp.ownerUserId)
				local accrualRate = RESTED.baseAccrualPerSecond * (1 + coziness * (RESTED.accrualMultAtMaxCoziness - 1))

				local now = os.clock()
				local current = math.max(restedUntil[player.UserId] or now, now)
				local cap = now + RESTED.chargeCapSeconds
				restedUntil[player.UserId] = math.min(current + dt * accrualRate, cap)
			end
		end
		-- Not resting right now (out of the zone, or it's day): just don't
		-- extend restedUntil. It keeps counting down toward "not Rested"
		-- entirely on its own — nothing to do here.
	end
end

function RestedService.start()
	local accumulator = 0
	RunService.Heartbeat:Connect(function(dt)
		accumulator += dt
		if accumulator < TICK_INTERVAL then
			return
		end
		local elapsed = accumulator
		accumulator = 0
		tick(elapsed)
	end)
end

return RestedService
