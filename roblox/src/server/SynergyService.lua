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
	-- families here (Traits.statsFor already ignores school ids).
	local totals = Traits.totalsFor(profile.inventory, profile.level)
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
		(Config.Mana.regenAmount * classDef.manaRegenMult) / Config.Mana.regenInterval
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

	-- ---- recompute triggers ----------------------------------------------------
	-- Equip/unequip (any inventory change), plus Level/Class changes — both
	-- move the inert gate, and Level can activate a piece that was too high.
	PlayerService.onInventoryChanged(recompute)

	Players.PlayerAdded:Connect(function(player)
		player:GetAttributeChangedSignal("Level"):Connect(function()
			recompute(player)
		end)
		player:GetAttributeChangedSignal("Class"):Connect(function()
			recompute(player)
		end)
	end)

	Players.PlayerRemoving:Connect(function(player)
		statsCache[player.UserId] = nil
		schoolCache[player.UserId] = nil
	end)
end

return SynergyService