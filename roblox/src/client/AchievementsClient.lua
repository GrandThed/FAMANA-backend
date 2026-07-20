-- Read-only client mirror of the local player's achievement-relevant
-- stats + unlocked set, built from three attributes PlayerService
-- publishes (PlayerStats, AchievementsUnlocked, MaxClassLevel) plus
-- BestiaryClient's own kill counts — same "seed from attributes, no remote"
-- pattern as BestiaryClient. Consumer: AchievementsUI.

local Players = game:GetService("Players")
local HttpService = game:GetService("HttpService")

local BestiaryClient = require(script.Parent.BestiaryClient)

local player = Players.LocalPlayer

local AchievementsClient = {}

local playerStats = { gathered = {}, crafted = 0, questsCompleted = 0 }
local unlocked = {} -- [achievementId] = true
local changed = Instance.new("BindableEvent")

-- Fired (no arguments) whenever any of the mirrored attributes update.
AchievementsClient.changed = changed.Event

-- A stats table shaped exactly like shared/Achievements.progress expects.
function AchievementsClient.stats()
	return {
		bestiaryKills = BestiaryClient.allKills(),
		gathered = playerStats.gathered,
		crafted = playerStats.crafted,
		maxClassLevel = player:GetAttribute("MaxClassLevel") or 0,
		questsCompleted = playerStats.questsCompleted,
	}
end

-- true if the local player has unlocked `achievementId`.
function AchievementsClient.isUnlocked(achievementId)
	return unlocked[achievementId] == true
end

local function applyStats(raw)
	if typeof(raw) ~= "string" or raw == "" then
		return
	end
	local ok, decoded = pcall(HttpService.JSONDecode, HttpService, raw)
	if not ok or typeof(decoded) ~= "table" then
		return
	end
	playerStats.gathered = decoded.gathered or {}
	playerStats.crafted = decoded.crafted or 0
	playerStats.questsCompleted = decoded.questsCompleted or 0
	changed:Fire()
end

local function applyUnlocked(raw)
	if typeof(raw) ~= "string" or raw == "" then
		return
	end
	local ok, decoded = pcall(HttpService.JSONDecode, HttpService, raw)
	if not ok or typeof(decoded) ~= "table" then
		return
	end
	unlocked = decoded
	changed:Fire()
end

player:GetAttributeChangedSignal("PlayerStats"):Connect(function()
	applyStats(player:GetAttribute("PlayerStats"))
end)
applyStats(player:GetAttribute("PlayerStats"))

player:GetAttributeChangedSignal("AchievementsUnlocked"):Connect(function()
	applyUnlocked(player:GetAttribute("AchievementsUnlocked"))
end)
applyUnlocked(player:GetAttribute("AchievementsUnlocked"))

player:GetAttributeChangedSignal("MaxClassLevel"):Connect(function()
	changed:Fire()
end)

-- Bestiary kills feed the "kills"/"kills_total" metrics too — re-fire our
-- own signal so AchievementsUI doesn't need to also listen to
-- BestiaryClient directly.
BestiaryClient.changed:Connect(function()
	changed:Fire()
end)

return AchievementsClient
