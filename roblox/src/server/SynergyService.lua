-- Trait synergies (Phase A of the TFT-style equipment system — see
-- docs/TRAITS_AND_SPELLS.md). Watches each player's equipped paper doll,
-- sums trait points per shared/Traits (skipping INERT pieces: itemLevel
-- above the active class level), and feeds the combined stats into the
-- systems that own each mechanic via their hooks:
--   * Lynx Eye      → EnemyService crit-chance hook
--   * Agile Hands   → ToolService swing-cooldown hook
--   * Perseverance  → EffectService buff-duration hook
--   * Brawler       → HealthService max-HP mult + always-on bonus regen
--   * Bastion       → EnemyService damage-taken hook (armor/(armor+100))
--   * Evasion       → EnemyService dodge-chance hook
-- The per-player totals replicate as the `TraitPoints` attribute (JSON) so
-- the client tracker/inventory can render progress with no extra remotes.

local Players = game:GetService("Players")
local HttpService = game:GetService("HttpService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Traits = require(Shared:WaitForChild("Traits"))
local Spells = require(Shared:WaitForChild("Spells"))
local Config = require(Shared:WaitForChild("Config"))
local Classes = require(Shared:WaitForChild("Classes"))

local PlayerService = require(script.Parent.PlayerService)
local EnemyService = require(script.Parent.EnemyService)
local ToolService = require(script.Parent.ToolService)
local EffectService = require(script.Parent.EffectService)
local HealthService = require(script.Parent.HealthService)
local ClassService = require(script.Parent.ClassService)
local ManaService = require(script.Parent.ManaService)
local GatheringService = require(script.Parent.GatheringService)
local PartyService = require(script.Parent.PartyService)

local SynergyService = {}

local EMPTY = {}

-- [userId] = combined stat block from active tiers (see Traits.statsFor)
local statsCache = {}

-- [userId] = { [schoolId] = points } — the equipment-earned school points
-- SpellService derives knowns/passives/familiars from.
local schoolCache = {}

-- Fired (player) after every recompute; SpellService re-derives known spells.
local recomputedCallbacks = {}
function SynergyService.onRecomputed(fn)
	table.insert(recomputedCallbacks, fn)
end

local function statsFor(player)
	return statsCache[player.UserId] or EMPTY
end

function SynergyService.getStats(player)
	return statsFor(player)
end

local recompute -- forward-declared (getSchoolPoints computes lazily)

-- School point totals for a player; computes on first ask (e.g. the client's
-- RequestSpells racing the load-time inventory push).
function SynergyService.getSchoolPoints(player)
	local points = schoolCache[player.UserId]
	if not points then
		recompute(player)
		points = schoolCache[player.UserId]
	end
	return points or EMPTY
end

recompute = function(player)
	local profile = PlayerService.get(player)
	if not profile then
		return
	end
	-- One aggregation pass; school ids and trait ids split into their
	-- families here (Traits.statsFor already ignores school ids). The held
	-- item drives the hand rule: a doll hand slot (weapon/offhand) counts
	-- only while that piece is the wielded Tool; a wielded grid tool
	-- contributes its own lines instead.
	local totals = Traits.totalsFor(profile.inventory, profile.level, ToolService.getHeldItemId(player))
	local schoolPoints = {}
	for id, points in pairs(totals) do
		if Spells.schools[id] then
			schoolPoints[id] = points
		end
	end
	local stats = Traits.statsFor(totals)
	statsCache[player.UserId] = stats
	schoolCache[player.UserId] = schoolPoints
	player:SetAttribute("TraitPoints", HttpService:JSONEncode(totals))
	-- Max HP depends on the Brawler tier; re-derive it right away.
	HealthService.refreshMaxHealth(player)

	-- Derived read-only stats for CharacterUI: crit chance, HP regen/s and
	-- mana regen/s. These already drive real gameplay elsewhere (EnemyService
	-- crit rolls, HealthService/ManaService regen ticks) — this just exposes
	-- the same numbers as attributes so the Character window can show them
	-- without a remote, same pattern as Armor/AttackDamage/etc.
	local classDef = ClassService.getDef(player)
	local level = ClassService.getLevel(player)
	local classStats = Classes.statsAtLevel(classDef, level)

	local critChance = Config.Combat.critChance + classDef.critChanceBonus + (stats.crit or 0)
	player:SetAttribute("CritChance", math.clamp(critChance, 0, 1))

	player:SetAttribute("DodgeChance", math.clamp(stats.dodge or 0, 0, 1))

	-- Brawler's trickle applies even in combat, so it's always "live" —
	-- unlike the base regen, which only kicks in after regenDelay seconds
	-- out of combat (the Character window notes that distinction).
	local hpMult = 1 + (stats.hp or 0)
	local effectiveMaxHp = classStats.hp * hpMult
	local brawlerRegenPerSec = (stats.regen or 0) * effectiveMaxHp
	player:SetAttribute("HpRegenPerSec", Config.HP.regenAmount / Config.HP.regenInterval)
	player:SetAttribute("HpRegenAlwaysOnPerSec", brawlerRegenPerSec)

	player:SetAttribute(
		"ManaRegenPerSec",
		(Config.Mana.regenAmount * classDef.manaRegenMult * (1 + (stats.manaRegen or 0)))
			/ Config.Mana.regenInterval
	)

	for _, fn in ipairs(recomputedCallbacks) do
		task.spawn(fn, player)
	end
end

function SynergyService.start()
	-- ---- stat hooks ----------------------------------------------------------
	EnemyService.registerCritChanceBonus(function(player)
		return statsFor(player).crit or 0
	end)
	EnemyService.registerDodgeChance(function(player)
		return statsFor(player).dodge or 0
	end)
	EnemyService.registerDamageTakenMult(function(player)
		local armor = statsFor(player).armor or 0
		return armor > 0 and 100 / (100 + armor) or 1
	end)
	ToolService.registerSwingCooldownMult(function(player)
		return 1 / (1 + (statsFor(player).attackSpeed or 0))
	end)
	EffectService.registerDurationMult(function(player)
		return 1 + (statsFor(player).duration or 0)
	end)
	HealthService.registerMaxHealthMult(function(player)
		return 1 + (statsFor(player).hp or 0)
	end)
	HealthService.registerBonusRegen(function(player)
		local fraction = statsFor(player).regen or 0
		if fraction <= 0 then
			return 0
		end
		local character = player.Character
		local humanoid = character and character:FindFirstChildOfClass("Humanoid")
		return humanoid and fraction * humanoid.MaxHealth or 0
	end)
	-- Phase 2 traits (docs/TRAITS_CATALOG.md): damage %, crit damage,
	-- lifesteal, reflect, debuff duration, healing received, mana regen.
	EnemyService.registerDamageMult(function(player, kind)
		local stats = statsFor(player)
		if kind == "magic" then
			return 1 + (stats.magicDamage or 0)
		end
		-- "physical" (bow) and "melee" both count as physical damage.
		return 1 + (stats.physicalDamage or 0)
	end)
	EnemyService.registerCritDamageBonus(function(player)
		return statsFor(player).critDamage or 0
	end)
	EnemyService.registerLifesteal(function(player)
		return statsFor(player).lifesteal or 0
	end)
	EnemyService.registerReflect(function(player)
		return statsFor(player).reflect or 0
	end)
	EnemyService.registerDebuffDurationBonus(function(player)
		return statsFor(player).debuffDuration or 0
	end)
	HealthService.registerHealReceivedMult(function(player)
		return 1 + (statsFor(player).healReceived or 0)
	end)
	ManaService.registerRegenMult(function(player)
		return 1 + (statsFor(player).manaRegen or 0)
	end)
	-- Gathering gear traits (Prospector/Woodsman), keyed by the wielded
	-- tool's kind — the hand rule already means these stats only exist in
	-- the totals while the matching tool is out.
	local GATHER_KEYS = {
		pickaxe = { yield = "miningYield", double = "miningDouble", noDeplete = "miningNoDeplete" },
		axe = { yield = "loggingYield", double = "loggingDouble", noDeplete = "loggingNoDeplete" },
	}
	GatheringService.registerYieldBonus(function(player, toolType)
		local keys = GATHER_KEYS[toolType]
		return keys and (statsFor(player)[keys.yield] or 0) or 0
	end)
	GatheringService.registerDoubleChance(function(player, toolType)
		local keys = GATHER_KEYS[toolType]
		return keys and (statsFor(player)[keys.double] or 0) or 0
	end)
	GatheringService.registerNoDepleteChance(function(player, toolType)
		local keys = GATHER_KEYS[toolType]
		return keys and (statsFor(player)[keys.noDeplete] or 0) or 0
	end)

	-- Guardian (party protector — procs, never a button): when the guardian
	-- is hit, a chance to shield the most-wounded nearby party member (no
	-- proc solo); the aura armors nearby party members, guardian included.
	local GUARD_RADIUS = 20
	local GUARD_SHIELD_FRACTION = 0.15
	local GUARD_SHIELD_DURATION = 4
	EnemyService.onPlayerHit(function(_source, victim)
		local proc = statsFor(victim).guardianProc or 0
		if proc <= 0 or math.random() >= proc then
			return
		end
		local root = victim.Character and victim.Character:FindFirstChild("HumanoidRootPart")
		if not root then
			return
		end
		local best, bestFraction
		for _, ally in ipairs(PartyService.getNearbyPartyMembers(victim, root.Position, GUARD_RADIUS)) do
			if ally ~= victim then
				local humanoid = ally.Character and ally.Character:FindFirstChildOfClass("Humanoid")
				if humanoid and humanoid.Health > 0 then
					local fraction = humanoid.Health / humanoid.MaxHealth
					if not bestFraction or fraction < bestFraction then
						best, bestFraction = ally, fraction
					end
				end
			end
		end
		if not best then
			return
		end
		local humanoid = best.Character:FindFirstChildOfClass("Humanoid")
		HealthService.addShield(best, humanoid.MaxHealth * GUARD_SHIELD_FRACTION, GUARD_SHIELD_DURATION)
		local healFraction = statsFor(victim).guardianHeal or 0
		if healFraction > 0 then
			HealthService.heal(best, (humanoid.MaxHealth - humanoid.Health) * healFraction)
		end
	end)
	EnemyService.registerDamageTakenMult(function(player)
		local armor = statsFor(player).guardianAura or 0
		local root = player.Character and player.Character:FindFirstChild("HumanoidRootPart")
		if root then
			for _, member in ipairs(PartyService.getNearbyPartyMembers(player, root.Position, GUARD_RADIUS)) do
				if member ~= player then
					armor += statsFor(member).guardianAura or 0
				end
			end
		end
		return armor > 0 and 100 / (100 + armor) or 1
	end)

	-- ---- recompute triggers ----------------------------------------------------
	-- Equip/unequip (any inventory change), plus Level/Class changes — both
	-- move the inert gate, and Level can activate a piece that was too high.
	-- Wielding/stowing a Tool moves the hand rule (weapon <-> tool traits).
	PlayerService.onInventoryChanged(recompute)
	ToolService.onHeldChanged(recompute)

	local function watchPlayer(player)
		player:GetAttributeChangedSignal("Level"):Connect(function()
			recompute(player)
		end)
		player:GetAttributeChangedSignal("Class"):Connect(function()
			recompute(player)
		end)
	end

	Players.PlayerAdded:Connect(watchPlayer)
	-- Players who connected during server boot fired PlayerAdded before the
	-- connect above (same sweep as PlayerService) — without this their
	-- Level/Class changes never trigger a synergy recompute.
	for _, player in ipairs(Players:GetPlayers()) do
		watchPlayer(player)
	end

	Players.PlayerRemoving:Connect(function(player)
		statsCache[player.UserId] = nil
		schoolCache[player.UserId] = nil
	end)
end

return SynergyService