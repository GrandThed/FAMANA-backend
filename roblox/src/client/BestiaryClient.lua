-- Read-only client cache of the local player's lifetime bestiary kill
-- counts. The server (PlayerService.bumpBestiaryKill) publishes the whole
-- { [lootSource] = count } map as JSON in the `BestiaryKills` attribute on
-- LocalPlayer — same "seed from an attribute, no remote round-trip" pattern
-- PlayerSettings.lua uses, except this is pure server->client (nothing ever
-- pushes back).
--
-- Consumers: EnemyInspectUI (gates the "Drops" section per lootSource) and
-- BestiaryUI (the full bestiary panel). See shared/Bestiary.lua for what a
-- kill count means (tierForKills) and docs/BESTIARY.md for the design.

local Players = game:GetService("Players")
local HttpService = game:GetService("HttpService")

local player = Players.LocalPlayer

local BestiaryClient = {}

local kills = {} -- [lootSource] = count
local changed = Instance.new("BindableEvent")

-- Fired (no arguments) whenever the server republishes an updated map —
-- e.g. right after a kill. Consumers just re-read BestiaryClient.kills.
BestiaryClient.changed = changed.Event

-- Lifetime kills against `lootSource` (0 if never killed).
function BestiaryClient.kills(lootSource)
	return kills[lootSource] or 0
end

local function apply(raw)
	if typeof(raw) ~= "string" or raw == "" then
		return
	end
	local ok, decoded = pcall(HttpService.JSONDecode, HttpService, raw)
	if not ok or typeof(decoded) ~= "table" then
		return
	end
	kills = decoded
	changed:Fire()
end

player:GetAttributeChangedSignal("BestiaryKills"):Connect(function()
	apply(player:GetAttribute("BestiaryKills"))
end)
apply(player:GetAttribute("BestiaryKills"))

return BestiaryClient
