-- Mana: a live gameplay resource that powers ranged magic (the staff). Held in
-- Player attributes ("Mana" / "MaxMana") so it replicates to the owning client
-- automatically — the HUD orb reads them directly, no remote needed. Mana is
-- NOT persisted (it regenerates quickly and refills on spawn), mirroring how
-- other in-memory world state is deliberately transient.

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Config"))

local ManaService = {}

function ManaService.get(player)
	return player:GetAttribute("Mana") or 0
end

-- Spends `amount` mana if the player has it; returns true on success, false if
-- they're too low (caller should not perform the mana-gated action).
function ManaService.trySpend(player, amount)
	local current = player:GetAttribute("Mana") or 0
	if current < amount then
		return false
	end
	player:SetAttribute("Mana", current - amount)
	return true
end

local function refill(player)
	player:SetAttribute("MaxMana", Config.Mana.max)
	player:SetAttribute("Mana", Config.Mana.max)
end

-- registerRegenMult: fn(player) -> multiplier on the per-tick mana regen
-- (Clarity trait; class scaling stays in the ManaRegenAmount attribute).
local regenMultHooks = {}
function ManaService.registerRegenMult(fn)
	table.insert(regenMultHooks, fn)
end

local function hookedRegenMult(player)
	local mult = 1
	for _, fn in ipairs(regenMultHooks) do
		local ok, value = pcall(fn, player)
		if ok and typeof(value) == "number" then
			mult *= value
		end
	end
	return mult
end

function ManaService.start()
	Players.PlayerAdded:Connect(function(player)
		refill(player)
		-- Refill on each (re)spawn, mirroring HP restoring to full on respawn.
		player.CharacterAdded:Connect(function()
			refill(player)
		end)
	end)
	for _, player in ipairs(Players:GetPlayers()) do
		refill(player)
	end

	-- Steady out-of-nothing regen tick (no combat gating, unlike HP).
	local accumulator = 0
	RunService.Heartbeat:Connect(function(dt)
		accumulator += dt
		if accumulator < Config.Mana.regenInterval then
			return
		end
		accumulator = 0

		for _, player in ipairs(Players:GetPlayers()) do
			local current = player:GetAttribute("Mana")
			local max = player:GetAttribute("MaxMana") or Config.Mana.max
			-- ClassService overrides this per-class (Mage regens faster, etc).
			local regenAmount = player:GetAttribute("ManaRegenAmount") or Config.Mana.regenAmount
			if current and current < max then
				player:SetAttribute("Mana", math.min(max, current + regenAmount * hookedRegenMult(player)))
			end
		end
	end)
end

return ManaService
