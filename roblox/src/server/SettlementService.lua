-- Territory: ties together EnemyService (guardian kills), the backend
-- (ownership persistence), and GuildService (who to credit/notify).
--
-- Flow: EnemyService fires onKilled with a settlementId + per-player damage
-- map whenever a settlement guardian/challenger dies. This service picks the
-- top-damage player, resolves their guild (via the backend — works even if
-- that exact player has since left, unlike reading a live Player attribute),
-- and reports the capture. On success it updates the local ownership cache
-- (used for the resource buff and the world banner) and schedules the next
-- challenger's appearance after `challengerRespawn`.
--
-- Ownership itself is NOT re-derived from a live poll on every check — the
-- backend is authoritative, but this service's local cache is what
-- GatheringService's yield-bonus hook reads every single harvest, so it has
-- to be cheap. The cache is seeded from the backend on start() and kept in
-- sync by every capture this server handles; RECONCILE_INTERVAL below
-- guards against drift (e.g. a guild disbanding, which changes ownership
-- without any kill happening on this server).

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local GridConfig = require(Shared:WaitForChild("GridConfig"))
local Settlements = require(Shared:WaitForChild("Settlements"))
local Remotes = require(Shared:WaitForChild("Remotes"))

local BackendService = require(script.Parent.BackendService)
local GuildService = require(script.Parent.GuildService)
local EnemyService = require(script.Parent.EnemyService)
local GatheringService = require(script.Parent.GatheringService)

local SettlementService = {}

-- How long a neutral guardian waits to reappear when nobody could be
-- credited for the kill (killer not in a guild, or a backend hiccup) —
-- short on purpose so a guildless kill doesn't lock the settlement out for
-- the full challengerRespawn window.
local NEUTRAL_RETRY = 60

local RECONCILE_INTERVAL = 300 -- 5 min: re-poll the backend to catch drift (e.g. a guild disbanding)

local notifyRemote -- resolved in start()

-- Settlement defs that belong to this server's cell, keyed by id — the only
-- ones this service (or EnemyService) actually spawns/tracks.
local localDefs = {}

-- [settlementId] = { guildId (string?), guildTag (string?), guildName (string?) }
-- guildId == nil means neutral.
local ownership = {}

-- [settlementId] = { anchor = Part, label = TextLabel }
local banners = {}

local function notify(player, message)
	if player and notifyRemote then
		notifyRemote:FireClient(player, message)
	end
end

local function distance2D(a, b)
	return (Vector3.new(a.X, 0, a.Z) - Vector3.new(b.X, 0, b.Z)).Magnitude
end

-- ---- world banner -----------------------------------------------------

local function buildBanner(settlementId, def)
	local anchor = Instance.new("Part")
	anchor.Name = "SettlementBanner_" .. settlementId
	anchor.Anchored = true
	anchor.CanCollide = false
	anchor.Transparency = 1
	anchor.Size = Vector3.new(1, 1, 1)
	anchor.Position = def.position + Vector3.new(0, 14, 0)
	anchor.Parent = Workspace

	local billboard = Instance.new("BillboardGui")
	billboard.Size = UDim2.new(0, 260, 0, 70)
	billboard.AlwaysOnTop = true
	billboard.MaxDistance = 300
	billboard.Parent = anchor

	local nameLabel = Instance.new("TextLabel")
	nameLabel.Name = "Name"
	nameLabel.Size = UDim2.new(1, 0, 0.5, 0)
	nameLabel.BackgroundTransparency = 1
	nameLabel.Font = Enum.Font.GothamBlack
	nameLabel.TextScaled = true
	nameLabel.TextColor3 = Color3.new(1, 1, 1)
	nameLabel.TextStrokeTransparency = 0.3
	nameLabel.Text = def.name
	nameLabel.Parent = billboard

	local ownerLabel = Instance.new("TextLabel")
	ownerLabel.Name = "Owner"
	ownerLabel.Size = UDim2.new(1, 0, 0.5, 0)
	ownerLabel.Position = UDim2.new(0, 0, 0.5, 0)
	ownerLabel.BackgroundTransparency = 1
	ownerLabel.Font = Enum.Font.GothamBold
	ownerLabel.TextScaled = true
	ownerLabel.TextStrokeTransparency = 0.4
	ownerLabel.Text = "Neutral"
	ownerLabel.TextColor3 = Color3.fromRGB(200, 200, 200)
	ownerLabel.Parent = billboard

	banners[settlementId] = { anchor = anchor, ownerLabel = ownerLabel }
end

local function refreshBanner(settlementId)
	local banner = banners[settlementId]
	if not banner then
		return
	end
	local owner = ownership[settlementId]
	if owner and owner.guildId then
		banner.ownerLabel.Text = string.format("[%s] %s", owner.guildTag or "?", owner.guildName or "")
		banner.ownerLabel.TextColor3 = Color3.fromRGB(255, 210, 90)
	else
		banner.ownerLabel.Text = "Neutral"
		banner.ownerLabel.TextColor3 = Color3.fromRGB(200, 200, 200)
	end
end

-- ---- ownership cache ----------------------------------------------------

local function setOwnership(settlementId, guildId, guildTag, guildName)
	if guildId then
		ownership[settlementId] = { guildId = tostring(guildId), guildTag = guildTag, guildName = guildName }
	else
		ownership[settlementId] = nil
	end
	refreshBanner(settlementId)
end

-- Re-derives guildTag/guildName for a claim we only got a bare guildId for
-- (e.g. from listSettlementClaims, which doesn't include guild details).
local function applyClaim(settlementId, claim)
	if not claim or not claim.guildId then
		setOwnership(settlementId, nil)
		return
	end
	local guild = BackendService.getGuildById(claim.guildId)
	setOwnership(settlementId, claim.guildId, guild and guild.tag, guild and guild.name)
end

-- ---- capture flow ---------------------------------------------------------

local function topDamagePlayer(damageBy)
	if not damageBy then
		return nil
	end
	local topUserId, topDamage
	for userId, dmg in pairs(damageBy) do
		if not topDamage or dmg > topDamage then
			topUserId, topDamage = userId, dmg
		end
	end
	return topUserId
end

local function scheduleChallenger(settlementId, delaySeconds)
	task.delay(delaySeconds, function()
		EnemyService.respawnSettlementGuardian(settlementId)
	end)
end

local function handleGuardianKilled(settlementId, damageBy)
	local def = localDefs[settlementId]
	if not def then
		return
	end

	local topUserId = topDamagePlayer(damageBy)
	if not topUserId then
		scheduleChallenger(settlementId, NEUTRAL_RETRY)
		return
	end

	-- Works whether the top-damage player is still around or already left —
	-- guild membership is a backend read either way, not a live attribute.
	-- `failed` (transport/decode failure) is distinct from "no guild": don't
	-- tell someone they need a guild when the real problem is the backend
	-- being unreachable.
	local guild, failed = BackendService.getGuildForPlayer(topUserId)
	if not guild then
		if not failed then
			notify(Players:GetPlayerByUserId(topUserId), "Necesitás estar en un gremio para reclamar un asentamiento.")
		end
		scheduleChallenger(settlementId, NEUTRAL_RETRY)
		return
	end

	local previousOwner = ownership[settlementId]
	local claim, err = BackendService.claimSettlement(settlementId, guild.id, topUserId, def.graceSeconds)
	if not claim then
		warn(string.format("[SettlementService] claim failed for %s: %s", settlementId, tostring(err)))
		scheduleChallenger(settlementId, NEUTRAL_RETRY)
		return
	end

	setOwnership(settlementId, guild.id, guild.tag, guild.name)

	local topPlayer = Players:GetPlayerByUserId(topUserId)
	GuildService.notifyGuild(tonumber(guild.id), string.format("¡Tu gremio capturó %s!", def.name))
	if topPlayer then
		notify(topPlayer, string.format("Capturaste %s para [%s] %s.", def.name, guild.tag, guild.name))
	end
	if previousOwner and previousOwner.guildId ~= tostring(guild.id) then
		GuildService.notifyGuild(tonumber(previousOwner.guildId), string.format("Perdiste %s.", def.name))
	end

	scheduleChallenger(settlementId, def.challengerRespawn)
end

-- ---- public API -----------------------------------------------------------

-- Fraction of extra gather yield for `player` right now, from any owned
-- settlement they're standing inside — plugged into
-- GatheringService.registerYieldBonus. Returns 0 outside any territory or
-- for a guildless player; sums if (unusually) inside overlapping claims.
function SettlementService.resourceBonusFor(player)
	local guildId = GuildService.getGuildId(player)
	if not guildId then
		return 0
	end
	local character = player.Character
	local root = character and character:FindFirstChild("HumanoidRootPart")
	if not root then
		return 0
	end

	local bonus = 0
	for settlementId, def in pairs(localDefs) do
		local owner = ownership[settlementId]
		if owner and owner.guildId == tostring(guildId) then
			if distance2D(root.Position, def.position) <= def.radius then
				bonus += (def.buff.resourceMult or 0)
			end
		end
	end
	return bonus
end

function SettlementService.start()
	notifyRemote = Remotes.get("Notify")

	local currentCell = GridConfig.currentCell()
	for settlementId, def in pairs(Settlements.defs) do
		if def.cell == currentCell then
			localDefs[settlementId] = def
			buildBanner(settlementId, def)
		end
	end

	-- Seed ownership from the backend (survives this server restarting).
	local claims = BackendService.listSettlementClaims()
	if claims then
		for _, claim in ipairs(claims) do
			if localDefs[claim.settlementId] then
				applyClaim(claim.settlementId, claim)
			end
		end
	end

	EnemyService.onKilled(function(_lootSource, _position, _killer, _level, settlementId, damageBy)
		if settlementId and localDefs[settlementId] then
			handleGuardianKilled(settlementId, damageBy)
		end
	end)

	GatheringService.registerYieldBonus(function(player, _toolType)
		return SettlementService.resourceBonusFor(player)
	end)

	-- Periodic reconcile: catches ownership changes this server didn't
	-- cause itself (a guild disbanding elsewhere sets guild_id to NULL
	-- backend-side with no kill event to tell us about it).
	task.spawn(function()
		while true do
			task.wait(RECONCILE_INTERVAL)
			local refreshed = BackendService.listSettlementClaims()
			if refreshed then
				local claimed = {}
				for _, claim in ipairs(refreshed) do
					if localDefs[claim.settlementId] then
						claimed[claim.settlementId] = true
						applyClaim(claim.settlementId, claim)
					end
				end
				for settlementId in pairs(localDefs) do
					if not claimed[settlementId] and ownership[settlementId] then
						setOwnership(settlementId, nil)
					end
				end
			end
		end
	end)
end

return SettlementService
