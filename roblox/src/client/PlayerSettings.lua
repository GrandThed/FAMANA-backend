-- Client-side player preferences (the options menu). Same lifecycle as
-- HotbarBinds: the server publishes the saved map in the `PlayerSettings`
-- attribute (JSON) when the profile loads, and every local change is pushed
-- back through the SetPlayerSettings remote (whitelisted server-side in
-- PlayerService, persisted with the profile).
--
-- Keys and their values:
--   traitTracker — "minimal" (icon-only column, the default) | "compact"
--                  (icon + name + count rows); read by SpellTrackerUI.

local Players = game:GetService("Players")
local HttpService = game:GetService("HttpService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Remotes = require(Shared:WaitForChild("Remotes"))

local player = Players.LocalPlayer

local PlayerSettings = {}

local DEFAULTS = {
	traitTracker = "minimal",
}

local values = table.clone(DEFAULTS)
local changed = Instance.new("BindableEvent")

-- Fired with the key that changed (both local sets and the server seed).
PlayerSettings.changed = changed.Event

local setSettingsRemote -- resolved async below

local function push()
	if setSettingsRemote then
		setSettingsRemote:FireServer(values)
	end
end

function PlayerSettings.get(key)
	return values[key]
end

function PlayerSettings.set(key, value)
	if DEFAULTS[key] == nil or values[key] == value then
		return
	end
	values[key] = value
	push()
	changed:Fire(key)
end

-- Seed from the saved map once the server publishes it (no push back: this
-- is the server's own state). Unknown keys are ignored; missing ones keep
-- their defaults.
local function apply(raw)
	if typeof(raw) ~= "string" or raw == "" then
		return
	end
	local ok, decoded = pcall(HttpService.JSONDecode, HttpService, raw)
	if not ok or typeof(decoded) ~= "table" then
		return
	end
	for key in pairs(DEFAULTS) do
		local value = decoded[key]
		if typeof(value) == "string" and value ~= values[key] then
			values[key] = value
			changed:Fire(key)
		end
	end
end

task.spawn(function()
	setSettingsRemote = Remotes.get("SetPlayerSettings")
end)

player:GetAttributeChangedSignal("PlayerSettings"):Connect(function()
	apply(player:GetAttribute("PlayerSettings"))
end)
apply(player:GetAttribute("PlayerSettings"))

return PlayerSettings
