-- Small HUD readout of how much time is left on the current camp (yours or
-- your party's) — server/CampService.lua exposes this as GetCampTimer, a
-- RemoteFunction rather than a push, so this just polls it periodically and
-- extrapolates locally between polls (no client/server clock sync needed:
-- "remaining seconds as of the poll" is all that's ever trusted).

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Remotes = require(Shared:WaitForChild("Remotes"))
local Theme = require(script.Parent.Theme)
local UIKit = require(script.Parent.UIKit)

local player = Players.LocalPlayer

local CampTimerUI = {}

local POLL_INTERVAL = 8 -- seconds between authoritative refreshes

local getCampTimer -- RemoteFunction, resolved in start()
local label
local gui

local remainingAtPoll = 0
local polledAtLocal = 0
local active = false

local function formatTime(seconds)
	seconds = math.max(0, math.floor(seconds))
	local minutes = math.floor(seconds / 60)
	local secs = seconds % 60
	return string.format("%d:%02d", minutes, secs)
end

local function refresh()
	local ok, result = pcall(function()
		return getCampTimer:InvokeServer()
	end)
	if not ok or typeof(result) ~= "table" then
		return
	end
	active = result.active == true
	if active then
		remainingAtPoll = tonumber(result.remaining) or 0
		polledAtLocal = os.clock()
	end
end

local function currentRemaining()
	return remainingAtPoll - (os.clock() - polledAtLocal)
end

local function buildHud()
	gui = Instance.new("ScreenGui")
	gui.Name = "CampTimerUI"
	gui.ResetOnSpawn = false
	gui.Enabled = false
	gui.Parent = player:WaitForChild("PlayerGui")

	local pill = Instance.new("Frame")
	pill.Name = "Pill"
	pill.Size = UDim2.new(0, 150, 0, 34)
	pill.Position = UDim2.new(0.5, 0, 0, 12)
	pill.AnchorPoint = Vector2.new(0.5, 0)
	pill.Parent = gui
	UIKit.stylePanel(pill)
	UIKit.autoScale(pill)

	label = UIKit.label(pill, "Camp — 0:00", 16, Theme.Semantic.TextStrong)
	label.Size = UDim2.new(1, -12, 1, 0)
	label.Position = UDim2.new(0, 6, 0, 0)
	label.TextXAlignment = Enum.TextXAlignment.Center
	label.Parent = pill
end

function CampTimerUI.start()
	getCampTimer = Remotes.getFunction("GetCampTimer")
	buildHud()

	task.spawn(function()
		while true do
			refresh()
			task.wait(POLL_INTERVAL)
		end
	end)

	RunService.Heartbeat:Connect(function()
		if not active then
			gui.Enabled = false
			return
		end
		local remaining = currentRemaining()
		if remaining <= 0 then
			gui.Enabled = false
			active = false
			return
		end
		gui.Enabled = true
		label.Text = "Camp — " .. formatTime(remaining)
	end)
end

return CampTimerUI