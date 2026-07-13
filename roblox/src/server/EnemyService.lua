-- Enemies: spawn at fixed points, chase + melee the nearest player, take damage
-- from weapon swings, die, and respawn. On death, fires kill handlers (the drop
-- system hooks in here). Enemy types are data-driven (ENEMY_DEFS), so adding a
-- new enemy is just a new entry. In-memory per server.

local Players = game:GetService("Players")
local Workspace = game:GetService("Workspace")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local HealthService = require(script.Parent.HealthService)
local ManaService = require(script.Parent.ManaService)
local MeshAssetService = require(script.Parent.MeshAssetService)
local ToolService = require(script.Parent.ToolService)
local TargetService = require(script.Parent.TargetService)
local PlayerService = require(script.Parent.PlayerService)
local ClassService = require(script.Parent.ClassService)
local PartyService = require(script.Parent.PartyService)
local DayNightService = require(script.Parent.DayNightService)
local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared:WaitForChild("Config"))
local MapMarkers = require(Shared:WaitForChild("MapMarkers"))
local Remotes = require(Shared:WaitForChild("Remotes"))
local ArtKit = require(Shared:WaitForChild("ArtKit"))
local Classes = require(Shared:WaitForChild("Classes"))
local Items = require(Shared:WaitForChild("Items"))

local V = Vector3.new

local EnemyService = {}

local DEFAULT_REACH = Config.defaultReach -- fallback when a weapon def omits `reach`
-- Damage aggro: getting hit locks the enemy onto its attacker (see dealDamage),
-- even when they're beyond aggroRange (bow/spell openers), with a generous
-- leash before it gives up the chase.
local AGGRO_DURATION = 10 -- seconds the lock lasts after the last hit
local AGGRO_LEASH_MULT = 3 -- × aggroRange chase leash while damage-aggroed
local MISSILE_SPEED = 90 -- studs/second the magic missile travels
local CRIT_CHANCE = Config.Combat.critChance
local CRIT_MULTIPLIER = Config.Combat.critMultiplier
local HP_PER_LEVEL = Config.Combat.mobLevel.hpPerLevel
local DAMAGE_PER_LEVEL = Config.Combat.mobLevel.damagePerLevel or 0.10
local AD_PER_LEVEL = Config.Combat.mobLevel.adPerLevel or DAMAGE_PER_LEVEL
local AP_PER_LEVEL = Config.Combat.mobLevel.apPerLevel or DAMAGE_PER_LEVEL
local ARMOR_PER_LEVEL = Config.Combat.mobLevel.armorPerLevel
local MR_PER_LEVEL = Config.Combat.mobLevel.magicResistPerLevel
local XP_PER_LEVEL = Config.Combat.mobLevel.xpPerLevel
local XP_SHARE_RADIUS = Config.Party.xpShareRadius

-- Level label color bands: low levels are calm white, higher levels ramp
-- through yellow into a dangerous red so players can eyeball threat at a
-- glance.
local LEVEL_COLOR_BANDS = {
	{ maxLevel = 2, color = Color3.fromRGB(235, 235, 235) },
	{ maxLevel = 4, color = Color3.fromRGB(255, 221, 51) },
	{ maxLevel = math.huge, color = Color3.fromRGB(255, 90, 60) },
}

local function levelColor(level)
	for _, band in ipairs(LEVEL_COLOR_BANDS) do
		if level <= band.maxLevel then
			return band.color
		end
	end
	return LEVEL_COLOR_BANDS[#LEVEL_COLOR_BANDS].color
end

local damageIndicatorRemote -- RemoteEvent, resolved in start()
local enemyDiedRemote -- RemoteEvent, resolved in start() — client death SFX (CombatSfx.lua), keyed by lootSource

local notifyRemote -- RemoteEvent, resolved in start()

-- Rate-limit the "not enough mana" toast so staff-spamming doesn't spam it.
local lastManaWarn = {} -- [userId] = os.clock()
local MANA_WARN_COOLDOWN = 1.5

-- Data-driven enemy types.
local ENEMY_DEFS = {
	slime = {
		name = "Slime",
		hp = 30,
		ad = 5,
		ap = 0,
		damageKind = "physical",
		armor = 5, -- squishy against weapons
		magicResist = 15, -- but its gooey body shrugs off magic
		minLevel = 1,
		maxLevel = 3,
		nightLevelBonus = 1, -- placeholder; added to the rolled level while it's night (see DayNightService)
		xpReward = 15,
		attackCooldown = 1.5,
		aggroRange = 30,
		attackRange = 6,
		respawn = 15,
		lootSource = "slime",
		size = Vector3.new(3, 3, 3),
		color = ArtKit.Palette.slime,
		material = Enum.Material.SmoothPlastic,
		transparency = 0.2,
		-- Slimes only move by hopping (parabolic jumps with squash & stretch).
		movement = "hop",
		hop = { distance = 6, height = 2.5, time = 0.5, pause = 0.35 },
		-- No meshAsset on purpose: the classic translucent squash-and-stretch
		-- cube IS the slime's look (the mesh version was tried and reverted).
		-- Welded onto the body part; offsets from its center, front is -Z.
		details = {
			{ name = "Core", shape = "Ball", size = V(1.5, 1.5, 1.5), offset = V(0, -0.3, 0), color = "slime" },
			{ name = "EyeL", size = V(0.35, 0.5, 0.3), offset = V(-0.55, 0.5, -1.5), color = "ink" },
			{ name = "EyeR", size = V(0.35, 0.5, 0.3), offset = V(0.55, 0.5, -1.5), color = "ink" },
			{ name = "Mouth", size = V(0.7, 0.18, 0.3), offset = V(0, -0.1, -1.5), color = "ink" },
		},
		spots = {
			Vector3.new(-20, 0, 12),
			Vector3.new(-28, 0, 20),
			Vector3.new(-15, 0, 26),
		},
	},
	goblin = {
		name = "Goblin",
		hp = 60,
		ad = 10,
		ap = 0,
		damageKind = "physical",
		armor = 15, -- wears scraps of armor, tougher against weapons
		magicResist = 5, -- has no answer for magic
		minLevel = 2,
		maxLevel = 5,
		nightLevelBonus = 2, -- placeholder; goblins get meaner faster at night than slimes
		xpReward = 35,
		attackCooldown = 1.2,
		walkSpeed = 12,
		aggroRange = 35,
		attackRange = 6,
		respawn = 20,
		lootSource = "goblin",
		size = Vector3.new(2.5, 4, 2.5),
		color = ArtKit.Palette.goblin,
		material = Enum.Material.SmoothPlastic,
		meshAsset = "goblin",
		details = {
			{ name = "EyeL", size = V(0.32, 0.32, 0.25), offset = V(-0.5, 1.3, -1.3), color = "ink" },
			{ name = "EyeR", size = V(0.32, 0.32, 0.25), offset = V(0.5, 1.3, -1.3), color = "ink" },
			{ name = "Nose", size = V(0.3, 0.5, 0.45), offset = V(0, 0.95, -1.35), color = "goblinDark" },
			{ name = "Mouth", size = V(0.9, 0.16, 0.25), offset = V(0, 0.55, -1.3), color = "ink" },
			{ name = "EarL", size = V(0.25, 0.8, 0.55), offset = V(-1.4, 1.45, 0), rot = V(0, 0, 25), color = "goblin" },
			{ name = "EarR", size = V(0.25, 0.8, 0.55), offset = V(1.4, 1.45, 0), rot = V(0, 0, -25), color = "goblin" },
			{ name = "Belt", size = V(2.7, 0.5, 2.7), offset = V(0, -0.6, 0), color = "trunkDark" },
			{ name = "Cloth", size = V(1.0, 1.2, 0.22), offset = V(0, -1.35, -1.3), color = "dirt" },
		},
		spots = {
			Vector3.new(-34, 0, -8),
			Vector3.new(-40, 0, -18),
		},
	},
}

local spawns = {} -- { def, pos, enemy = { part, fill, hp, lastAttack, dead, def } | nil }
local enemyFolder

-- [n] = function(lootSource, position, killer)  registered by the drop system.
EnemyService.killedHandlers = {}
function EnemyService.onKilled(fn)
	table.insert(EnemyService.killedHandlers, fn)
end

-- [n] = function(lootSource, player)  fired when an enemy lands a melee hit
-- on a player (the effect system hooks in here, e.g. slime slowness).
EnemyService.playerHitHandlers = {}
function EnemyService.onPlayerHit(fn)
	table.insert(EnemyService.playerHitHandlers, fn)
end

-- Damage-pipeline hooks, so buffs (EffectService) and subclass passives
-- (SpellService) can scale combat without EnemyService knowing about them.
-- registerDamageMult: fn(player, damageKind) -> mult on the player's outgoing
-- damage. registerDamageTakenMult: fn(player) -> mult on damage they receive.
local damageMultHooks = {}
function EnemyService.registerDamageMult(fn)
	table.insert(damageMultHooks, fn)
end

local damageTakenMultHooks = {}
function EnemyService.registerDamageTakenMult(fn)
	table.insert(damageTakenMultHooks, fn)
end

local function hookedDamageMult(player, damageKind)
	local mult = 1
	for _, fn in ipairs(damageMultHooks) do
		local ok, value = pcall(fn, player, damageKind)
		if ok and typeof(value) == "number" then
			mult *= value
		end
	end
	return mult
end

local function hookedDamageTakenMult(player)
	local mult = 1
	for _, fn in ipairs(damageTakenMultHooks) do
		local ok, value = pcall(fn, player)
		if ok and typeof(value) == "number" then
			mult *= value
		end
	end
	return mult
end

-- registerCritChanceBonus: fn(player) -> additive crit chance (Lynx Eye).
local critChanceHooks = {}
function EnemyService.registerCritChanceBonus(fn)
	table.insert(critChanceHooks, fn)
end

local function hookedCritBonus(player)
	local bonus = 0
	for _, fn in ipairs(critChanceHooks) do
		local ok, value = pcall(fn, player)
		if ok and typeof(value) == "number" then
			bonus += value
		end
	end
	return bonus
end

-- registerDodgeChance: fn(player) -> chance to fully evade an enemy hit
-- (Evasion trait). Summed across hooks, capped so a hit always CAN land.
local dodgeChanceHooks = {}
function EnemyService.registerDodgeChance(fn)
	table.insert(dodgeChanceHooks, fn)
end

local function hookedDodgeChance(player)
	local chance = 0
	for _, fn in ipairs(dodgeChanceHooks) do
		local ok, value = pcall(fn, player)
		if ok and typeof(value) == "number" then
			chance += value
		end
	end
	return math.min(chance, 0.9)
end

-- Additive fn(player) -> number hooks, all following the crit-bonus pattern:
--   registerCritDamageBonus — added to the crit MULTIPLIER (Executioner:
--     +0.40 makes crits hit x2.4 instead of x2).
--   registerLifesteal — fraction of WEAPON damage healed back (Leech; spells
--     deliberately excluded).
--   registerReflect — fraction of melee damage taken reflected back at the
--     attacking enemy (Retribution).
--   registerDebuffDurationBonus — bonus on stun/slow durations the player
--     inflicts (Inferno).
--   registerSlowPotency — the player's slows are this much STRONGER
--     (Trapper's control passive): a 50% slow at +0.4 becomes 70%.
local function additiveHook()
	local hooks = {}
	local register = function(fn)
		table.insert(hooks, fn)
	end
	local total = function(player)
		local sum = 0
		for _, fn in ipairs(hooks) do
			local ok, value = pcall(fn, player)
			if ok and typeof(value) == "number" then
				sum += value
			end
		end
		return sum
	end
	return register, total
end

local hookedCritDamageBonus, hookedLifesteal, hookedReflect, hookedDebuffDurationBonus, hookedSlowPotency
EnemyService.registerCritDamageBonus, hookedCritDamageBonus = additiveHook()
EnemyService.registerLifesteal, hookedLifesteal = additiveHook()
EnemyService.registerReflect, hookedReflect = additiveHook()
EnemyService.registerDebuffDurationBonus, hookedDebuffDurationBonus = additiveHook()
EnemyService.registerSlowPotency, hookedSlowPotency = additiveHook()

-- registerExtraRangedShot: fn(player) -> true to echo a successful bow shot
-- with one extra arrow (Double Nock's primed charge — the hook CONSUMES it,
-- so it's asked once per swing, only after a shot actually fired).
local extraShotHooks = {}
function EnemyService.registerExtraRangedShot(fn)
	table.insert(extraShotHooks, fn)
end

-- Iframes (Iron Roll & friends): a brief window where enemy hits fully
-- miss — checked before the dodge roll, popping the same "Dodge!" feedback.
local iframes = {} -- [userId] = os.clock() expiry
function EnemyService.grantIframes(player, duration)
	local expires = os.clock() + duration
	if (iframes[player.UserId] or 0) < expires then
		iframes[player.UserId] = expires
	end
end

-- Floating "Dodge!" popup over a player who just evaded a hit.
local function dodgePopup(character)
	local root = character and character:FindFirstChild("HumanoidRootPart")
	if not root then
		return
	end
	local gui = Instance.new("BillboardGui")
	gui.Size = UDim2.new(0, 90, 0, 24)
	gui.StudsOffset = Vector3.new(0, 3.2, 0)
	gui.AlwaysOnTop = true
	gui.Parent = root

	local label = Instance.new("TextLabel")
	label.Size = UDim2.new(1, 0, 1, 0)
	label.BackgroundTransparency = 1
	label.Font = Enum.Font.GothamBold
	label.TextSize = 18
	label.TextColor3 = Color3.fromRGB(130, 210, 140)
	label.TextStrokeTransparency = 0.4
	label.Text = "Dodge!"
	label.Parent = gui

	TweenService:Create(gui, TweenInfo.new(0.6, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
		StudsOffset = Vector3.new(0, 4.6, 0),
	}):Play()
	TweenService:Create(label, TweenInfo.new(0.6), { TextTransparency = 1, TextStrokeTransparency = 1 }):Play()
	task.delay(0.7, function()
		gui:Destroy()
	end)
end

-- The full outgoing-damage roll for a player: AD/AP (from class + level, see
-- shared/Classes.lua), hook multipliers (effects + passives), then the crit
-- roll. Used by weapon swings here and by SpellService for spell damage.
-- Returns (damage, isCrit).
--
-- `baseDamage` (a weapon/spell def's own flat damage) is intentionally
-- IGNORED: AD (melee + physical/bow) and AP (magic) alone determine
-- outgoing damage now — the plan is for equipment to eventually carry no
-- stats of its own. The param is kept so existing call sites (which still
-- pass def.damage) don't need to change. Spells that hit harder or softer
-- than a plain swing say so via opts.baseMult (a spell def's `powerMult`
-- — Meteor's "400% magic" is baseMult 4); opts.critBonus adds to the crit
-- MULTIPLIER on top of Executioner (One Shot, One Kill's +100%).
function EnemyService.computePlayerDamage(player, baseDamage, damageKind, opts)
	local stat = damageKind == "magic" and ClassService.getAP(player) or ClassService.getAD(player)
	local damage = stat * (opts and opts.baseMult or 1) * hookedDamageMult(player, damageKind)

	local isCrit = false
	if opts and opts.forceCrit then
		-- Guaranteed crits (True Shot on wounded prey) skip the roll but
		-- still enjoy Executioner's multiplier.
		isCrit = true
		damage *= CRIT_MULTIPLIER + hookedCritDamageBonus(player) + (opts.critBonus or 0)
	elseif not (opts and opts.noCrit) then
		local critChance = CRIT_CHANCE + ClassService.getCritBonus(player) + hookedCritBonus(player)
		isCrit = math.random() < critChance
		if isCrit then
			-- Executioner's bonus rides the multiplier itself (x2 -> x2.4...).
			damage *= CRIT_MULTIPLIER + hookedCritDamageBonus(player) + (opts and opts.critBonus or 0)
		end
	end
	return math.max(1, math.floor(damage + 0.5)), isCrit
end

local function groundY(x, z)
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	params.FilterDescendantsInstances = { enemyFolder }
	local result = Workspace:Raycast(Vector3.new(x, 200, z), Vector3.new(0, -1000, 0), params)
	return result and result.Position.Y or 0
end

-- Colors mirror client/Theme.lua's Orb ramp (HpTop/HpBottom/HpRing) so the
-- overhead bar reads as the same "liquid HP" chrome as the player's health
-- orb. Hardcoded rather than required: Theme lives under StarterPlayerScripts
-- (client-only by convention) and this is server code. Keep these in sync by
-- hand if the Orb ramp in Theme.lua ever changes.
local BAR_INK = Color3.fromRGB(8, 5, 5) -- Theme.Color.Ink900
local BAR_BORDER = Color3.fromRGB(61, 42, 34) -- Theme.Semantic.BorderPanel (Stone600)
local BAR_HP_TOP = Color3.fromRGB(214, 74, 58) -- Theme.Orb.HpTop
local BAR_HP_BOTTOM = Color3.fromRGB(122, 24, 16) -- Theme.Orb.HpBottom
local BAR_GHOST = Color3.fromRGB(232, 206, 172) -- Theme.Color.Gold300, the "damage taken" afterimage

local FILL_TWEEN = TweenInfo.new(0.15, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
local GHOST_DELAY = 0.25
local GHOST_TWEEN = TweenInfo.new(0.35, Enum.EasingStyle.Quad, Enum.EasingDirection.In)

local function updateHealthBar(enemy)
	local frac = math.clamp(enemy.hp / enemy.maxHp, 0, 1)
	TweenService:Create(enemy.fill, FILL_TWEEN, { Size = UDim2.new(frac, 0, 1, 0) }):Play()

	-- Ghost bar: a pale afterimage that lags behind on damage and catches
	-- down to the real value a beat later, so a hit reads as "chipping into"
	-- the bar instead of the whole thing just snapping smaller.
	enemy.ghostToken = (enemy.ghostToken or 0) + 1
	local token = enemy.ghostToken
	task.delay(GHOST_DELAY, function()
		if enemy.dead or enemy.ghostToken ~= token then
			return -- a newer hit landed before this catch-down fired; let it win
		end
		TweenService:Create(enemy.ghost, GHOST_TWEEN, { Size = UDim2.new(frac, 0, 1, 0) }):Play()
	end)
end

local function buildEnemy(pos, def)
	local y = groundY(pos.X, pos.Z)

	local level = math.random(def.minLevel or 1, def.maxLevel or 1)
	if DayNightService.isNight() then
		-- Flat bump on top of the roll, not a wider range: keeps day spawns
		-- exactly as they are today and makes the night difference legible
		-- (same enemy, visibly higher level tag) rather than folding it into
		-- the min/max roll where it'd be invisible.
		level += def.nightLevelBonus or 0
	end
	local maxHp = math.floor(def.hp * (1 + (level - 1) * HP_PER_LEVEL) + 0.5)
	local ad = math.floor((def.ad or def.damage or 0) * (1 + (level - 1) * AD_PER_LEVEL) + 0.5)
	local ap = math.floor((def.ap or 0) * (1 + (level - 1) * AP_PER_LEVEL) + 0.5)
	local armor = math.floor((def.armor or 0) * (1 + (level - 1) * ARMOR_PER_LEVEL) + 0.5)
	local magicResist = math.floor((def.magicResist or 0) * (1 + (level - 1) * MR_PER_LEVEL) + 0.5)

	local part = Instance.new("Part")
	part.Name = def.name
	part.Anchored = true
	part.Size = def.size
	part.Color = def.color
	part.Material = def.material
	part.Transparency = def.transparency or 0
	part.Position = Vector3.new(pos.X, y + def.size.Y / 2, pos.Z)
	-- Exposed so clients can color the level label relative to their OWN
	-- level (see client/EnemyLevelUI.lua), instead of everyone seeing the
	-- same absolute-level color this file paints below as a placeholder.
	part:SetAttribute("Level", level)
	-- Exposed for EnemyInspectUI's click-to-inspect stat card — read-only
	-- flavor info for the client, no gameplay logic depends on these being
	-- attributes (the server always uses its own `enemy` table).
	part:SetAttribute("MaxHp", maxHp)
	part:SetAttribute("AttackDamage", ad)
	part:SetAttribute("AbilityPower", ap)
	part:SetAttribute("Damage", ad > ap and ad or ap)
	part:SetAttribute("Armor", armor)
	part:SetAttribute("MagicResist", magicResist)

	-- Style-A mesh visual when its template loaded: the body part stays the
	-- physics/targeting object and goes invisible underneath it. Otherwise
	-- the ArtKit face/body details ride along via welds, as before.
	local visual = def.meshAsset and MeshAssetService.weldVisual(part, def.meshAsset, def.size.Y)
	if visual then
		part.Transparency = 1
	elseif def.details then
		ArtKit.weld(part, def.details)
	end

	-- Name + level label, sits just above the health bar.
	local nameTag = Instance.new("BillboardGui")
	nameTag.Name = "NameTag"
	nameTag.Size = UDim2.new(0, 140, 0, 20)
	nameTag.StudsOffsetWorldSpace = Vector3.new(0, def.size.Y / 2 + 1.9, 0)
	nameTag.AlwaysOnTop = true
	-- Only readable up close; otherwise players could scout an enemy's
	-- name/level from across the map before deciding whether to engage.
	nameTag.MaxDistance = 30
	nameTag.Parent = part

	local nameLabel = Instance.new("TextLabel")
	nameLabel.Size = UDim2.new(1, 0, 1, 0)
	nameLabel.BackgroundTransparency = 1
	nameLabel.Font = Enum.Font.GothamBold
	nameLabel.TextSize = 15
	nameLabel.TextColor3 = Color3.fromRGB(255, 255, 255)
	nameLabel.TextStrokeTransparency = 0.4
	nameLabel.Text = def.name
	nameLabel.Parent = nameTag

	local levelLabel = Instance.new("TextLabel")
	levelLabel.Name = "LevelLabel"
	levelLabel.Size = UDim2.new(1, 0, 1, 0)
	levelLabel.BackgroundTransparency = 1
	levelLabel.Font = Enum.Font.GothamBlack
	levelLabel.TextSize = 15
	levelLabel.TextColor3 = levelColor(level)
	levelLabel.TextStrokeTransparency = 0.2
	levelLabel.Text = string.format("Lv.%d", level)
	levelLabel.Parent = nameTag

	-- Name on the left half, level on the right half of the same tag.
	nameLabel.Size = UDim2.new(0.62, 0, 1, 0)
	nameLabel.TextXAlignment = Enum.TextXAlignment.Right
	levelLabel.Size = UDim2.new(0.38, 0, 1, 0)
	levelLabel.Position = UDim2.new(0.62, 4, 0, 0)
	levelLabel.TextXAlignment = Enum.TextXAlignment.Left

	local billboard = Instance.new("BillboardGui")
	billboard.Name = "HealthBar"
	billboard.Size = UDim2.new(0, 64, 0, 10)
	billboard.StudsOffsetWorldSpace = Vector3.new(0, def.size.Y / 2 + 1, 0)
	billboard.AlwaysOnTop = true
	-- Only visible up close, matching the name tag limit.
	billboard.MaxDistance = 30
	billboard.Parent = part

	local bg = Instance.new("Frame")
	bg.Size = UDim2.new(1, 0, 1, 0)
	bg.BackgroundColor3 = BAR_INK
	bg.BorderSizePixel = 0
	bg.ClipsDescendants = true
	bg.Parent = billboard

	local bgCorner = Instance.new("UICorner")
	bgCorner.CornerRadius = UDim.new(0, 2)
	bgCorner.Parent = bg

	local border = Instance.new("UIStroke")
	border.Thickness = 1
	border.Color = BAR_BORDER
	border.Parent = bg

	-- Ghost afterimage sits BELOW the real fill and only shows through the
	-- sliver the real fill just vacated, then eases down to match it.
	local ghost = Instance.new("Frame")
	ghost.Name = "Ghost"
	ghost.Size = UDim2.new(1, 0, 1, 0)
	ghost.BackgroundColor3 = BAR_GHOST
	ghost.BorderSizePixel = 0
	ghost.ZIndex = bg.ZIndex + 1
	ghost.Parent = bg

	local fill = Instance.new("Frame")
	fill.Name = "Fill"
	fill.Size = UDim2.new(1, 0, 1, 0)
	fill.BackgroundColor3 = BAR_HP_TOP
	fill.BorderSizePixel = 0
	fill.ZIndex = ghost.ZIndex + 1
	fill.Parent = bg

	local gradient = Instance.new("UIGradient")
	gradient.Rotation = 90
	gradient.Color = ColorSequence.new(BAR_HP_TOP, BAR_HP_BOTTOM)
	gradient.Parent = fill

	part.Parent = enemyFolder

	return {
		part = part,
		fill = fill,
		ghost = ghost,
		hp = maxHp,
		maxHp = maxHp,
		ad = ad,
		ap = ap,
		damage = ad, -- legacy fallback
		armor = armor,
		magicResist = magicResist,
		level = level,
		lastAttack = 0,
		dead = false,
		def = def,
	}
end

local function spawnAt(entry)
	entry.enemy = buildEnemy(entry.pos, entry.def)
end

local function nearestPlayer(position, range)
	local closest, closestDist
	for _, player in ipairs(Players:GetPlayers()) do
		local character = player.Character
		local root = character and character:FindFirstChild("HumanoidRootPart")
		local humanoid = character and character:FindFirstChildOfClass("Humanoid")
		-- Downed players sit at 1 HP waiting for a revive; they're out of the
		-- fight, so enemies drop them and look for someone else.
		if root and humanoid and humanoid.Health > 0 and not HealthService.isDowned(player) then
			local dist = (root.Position - position).Magnitude
			if dist <= range and (not closestDist or dist < closestDist) then
				closest, closestDist = player, dist
			end
		end
	end
	return closest
end

-- Squash/stretch the body around its bottom (feet stay planted). stretch > 1
-- elongates for the air phase, < 1 flattens for the landing. Volume is
-- roughly preserved by widening as it flattens.
local function setSquash(enemy, stretch)
	local part = enemy.part
	local base = enemy.def.size
	local widen = 1 / math.sqrt(stretch)
	local bottom = part.Position.Y - part.Size.Y / 2
	local size = Vector3.new(base.X * widen, base.Y * stretch, base.Z * widen)
	local pos = Vector3.new(part.Position.X, bottom + size.Y / 2, part.Position.Z)
	part.Size = size
	part.CFrame = (part.CFrame - part.CFrame.Position) + pos
end

local HOP_SQUASH_TIME = 0.12 -- how long the landing squash holds

-- Hop locomotion: parabolic jumps toward the player with squash & stretch.
-- A hop in flight always finishes, even if the target left aggro range.
-- `speedMult` < 1 (slow debuff) stretches the pause between hops.
local function updateHop(enemy, dt, root, def, speedMult)
	local hop = def.hop
	local part = enemy.part
	enemy.hopT = (enemy.hopT or 0) + dt
	local state = enemy.hopState or "wait"

	if state == "air" then
		local a = math.min(enemy.hopT / hop.time, 1)
		local pos = enemy.hopFrom:Lerp(enemy.hopTo, a)
			+ Vector3.new(0, math.sin(a * math.pi) * hop.height, 0)
		local look = Vector3.new(enemy.hopTo.X - enemy.hopFrom.X, 0, enemy.hopTo.Z - enemy.hopFrom.Z)
		if look.Magnitude > 0.05 then
			part.CFrame = CFrame.lookAt(pos, pos + look)
		else
			part.CFrame = (part.CFrame - part.CFrame.Position) + pos
		end
		setSquash(enemy, 1 + 0.25 * math.sin(a * math.pi))
		if a >= 1 then
			enemy.hopState = "squash"
			enemy.hopT = 0
			setSquash(enemy, 0.7)
		end
	elseif state == "squash" then
		if enemy.hopT >= HOP_SQUASH_TIME then
			setSquash(enemy, 1)
			enemy.hopState = "wait"
			enemy.hopT = 0
		end
	elseif root then -- "wait": grounded; face the player and wind up the next hop
		local from = part.Position
		local flatTarget = Vector3.new(root.Position.X, from.Y, root.Position.Z)
		local toTarget = flatTarget - from
		local planarDist = toTarget.Magnitude
		if planarDist > 0.05 then
			part.CFrame = CFrame.lookAt(from, flatTarget)
		end
		if planarDist > def.attackRange and enemy.hopT >= hop.pause / (speedMult or 1) then
			local to = from + toTarget.Unit * math.min(hop.distance, planarDist)
			enemy.hopFrom = from
			enemy.hopTo = Vector3.new(to.X, groundY(to.X, to.Z) + def.size.Y / 2, to.Z)
			enemy.hopState = "air"
			enemy.hopT = 0
		end
	end
end

-- Floating status marks over an enemy (stun stars, slow snail, attack
-- telegraph) so CC + incoming-attack state reads at a glance, each with a
-- bar draining down the remaining duration. Server-side BillboardGuis, same
-- as the name tag / health bar — deliberately NOT a client Highlight: those
-- render unreliably on parts that already have their own Transparency > 0
-- (slimes are the only enemy built that way), so anything meant to show on
-- every enemy type goes through this proven mechanism instead.
local STATUS_MARKS = {
	stun = { text = "💫", offsetX = -0.9, offsetY = 3, spin = true, barColor = Color3.fromRGB(255, 220, 120) },
	slow = { text = "🐌", offsetX = 0.9, offsetY = 3, spin = false, barColor = Color3.fromRGB(120, 190, 255) },
	-- Sits in its own row above stun/slow so it doesn't overlap when an
	-- enemy is both winding up an attack AND slowed/stunned at once.
	telegraph = { text = "❗", offsetX = 0, offsetY = 3.7, spin = false, barColor = Color3.fromRGB(255, 70, 50) },
	-- Arrow damage-over-time (see applyArrowEffect below). Own row so it
	-- doesn't collide with stun/slow or the attack telegraph.
	burn = { text = "🔥", offsetX = -0.9, offsetY = 4.4, spin = false, barColor = Color3.fromRGB(255, 130, 60) },
	poison = { text = "☠️", offsetX = 0.9, offsetY = 4.4, spin = false, barColor = Color3.fromRGB(120, 200, 90) },
}

local function setStatusMark(enemy, kind, active)
	enemy.marks = enemy.marks or {}
	local existing = enemy.marks[kind]
	if active and not existing then
		local look = STATUS_MARKS[kind]
		local gui = Instance.new("BillboardGui")
		gui.Name = "Mark_" .. kind
		gui.Size = UDim2.new(0, 26, 0, 32)
		gui.StudsOffsetWorldSpace = Vector3.new(look.offsetX, enemy.def.size.Y / 2 + (look.offsetY or 3), 0)
		gui.AlwaysOnTop = true
		gui.Parent = enemy.part

		local label = Instance.new("TextLabel")
		label.Size = UDim2.new(1, 0, 1, -6)
		label.BackgroundTransparency = 1
		label.Font = Enum.Font.GothamBold
		label.TextSize = 20
		label.Text = look.text
		label.Parent = gui

		local barBg = Instance.new("Frame")
		barBg.Size = UDim2.new(1, -4, 0, 3)
		barBg.Position = UDim2.new(0, 2, 1, -4)
		barBg.BackgroundColor3 = Color3.fromRGB(25, 25, 30)
		barBg.BorderSizePixel = 0
		barBg.Parent = gui

		local fill = Instance.new("Frame")
		fill.Size = UDim2.new(1, 0, 1, 0)
		fill.BackgroundColor3 = look.barColor
		fill.BorderSizePixel = 0
		fill.Parent = barBg

		if look.spin then
			local spin = TweenService:Create(
				label,
				TweenInfo.new(1.2, Enum.EasingStyle.Linear, Enum.EasingDirection.Out, -1),
				{ Rotation = 360 }
			)
			spin:Play()
		end
		enemy.marks[kind] = { gui = gui, fill = fill }
	elseif not active and existing then
		existing.gui:Destroy()
		enemy.marks[kind] = nil
	end
end

local function updateMarkBar(enemy, kind, remaining, total)
	local mark = enemy.marks and enemy.marks[kind]
	if mark and total and total > 0 then
		mark.fill.Size = UDim2.new(math.clamp(remaining / total, 0, 1), 0, 1, 0)
	end
end

-- Whether a player is a valid live chase target within `range` of `position`
-- (downed players don't count — see nearestPlayer).
local function playerInRange(player, position, range)
	if not player or player.Parent == nil then
		return false
	end
	local character = player.Character
	local root = character and character:FindFirstChild("HumanoidRootPart")
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	return root ~= nil
		and humanoid ~= nil
		and humanoid.Health > 0
		and not HealthService.isDowned(player)
		and (root.Position - position).Magnitude <= range
end

local dealDamage -- forward-declared: updateEnemy's reflect path needs it

local function updateEnemy(entry, dt)
	local enemy = entry.enemy
	if not enemy or enemy.dead then
		return
	end
	local def = enemy.def
	local now = os.clock()

	-- A taunt (Provocar) forces the enemy onto the taunter — with a generous
	-- leash so walking backwards doesn't instantly break it.
	local target
	if enemy.tauntedUntil and now < enemy.tauntedUntil then
		if playerInRange(enemy.tauntedBy, enemy.part.Position, def.aggroRange * 2) then
			target = enemy.tauntedBy
		end
	else
		enemy.tauntedBy, enemy.tauntedUntil = nil, nil
	end
	-- Damage aggro: chase whoever hit us last (set in dealDamage), even if
	-- they're outside aggroRange.
	if not target then
		if enemy.aggroUntil and now < enemy.aggroUntil then
			if playerInRange(enemy.aggroBy, enemy.part.Position, def.aggroRange * AGGRO_LEASH_MULT) then
				target = enemy.aggroBy
			end
		else
			enemy.aggroBy, enemy.aggroUntil = nil, nil
		end
	end
	target = target or nearestPlayer(enemy.part.Position, def.aggroRange)

	local root
	if target then
		root = target.Character:FindFirstChild("HumanoidRootPart")
	end

	-- CC state: expire + surface both as floating marks with drain bars.
	local stunned = enemy.stunnedUntil ~= nil and now < enemy.stunnedUntil
	if not stunned then
		enemy.stunnedUntil, enemy.stunTotal = nil, nil
	end
	local slowed = enemy.slowedUntil ~= nil and now < enemy.slowedUntil
	if not slowed then
		enemy.slowedUntil, enemy.slowMult, enemy.slowTotal = nil, nil, nil
	end
	setStatusMark(enemy, "stun", stunned)
	setStatusMark(enemy, "slow", slowed)
	if stunned then
		updateMarkBar(enemy, "stun", enemy.stunnedUntil - now, enemy.stunTotal)
	end
	if slowed then
		updateMarkBar(enemy, "slow", enemy.slowedUntil - now, enemy.slowTotal)
	end

	-- Arrow damage-over-time (burn/poison from special arrows — see
	-- applyArrowEffect). Ticks regardless of stun/movement state, same as a
	-- real DoT should. A tick can kill the enemy mid-loop (dealDamage ->
	-- killEnemy destroys enemy.part), so bail out immediately after that
	-- happens instead of touching the now-dead enemy's marks again.
	if enemy.dots then
		for kind, dot in pairs(enemy.dots) do
			if enemy.dead then
				break
			end
			if now >= dot.untilTime then
				enemy.dots[kind] = nil
				setStatusMark(enemy, kind, false)
			else
				setStatusMark(enemy, kind, true)
				updateMarkBar(enemy, kind, dot.untilTime - now, dot.totalDuration)
				if now >= dot.nextTick then
					dot.nextTick = now + dot.interval
					dealDamage(entry, enemy, dot.baseDmg * (dot.stacks or 1), dot.source, false, "physical")
				end
			end
		end
	end
	if enemy.dead then
		return
	end
	if enemy.windingUp then
		updateMarkBar(enemy, "telegraph", math.max(0, enemy.windupEndsAt - now), enemy.windupTotal)
	end
	local speedMult = slowed and (enemy.slowMult or 0.5) or 1

	-- Stunned: no chasing, no winding up new hops, no attacking. A hop already
	-- in flight still lands (freezing mid-air reads as a bug, not a stun).
	-- A committed attack windup, though, gets cancelled — getting stunned
	-- mid-swing interrupting the hit reads as fair, not a bug.
	if stunned then
		if enemy.windingUp then
			enemy.windingUp = false
			enemy.windupTarget = nil
			setStatusMark(enemy, "telegraph", false)
		end
		if def.movement == "hop" then
			updateHop(enemy, dt, nil, def, speedMult)
		end
		return
	end

	if def.movement == "hop" then
		updateHop(enemy, dt, root, def, speedMult)
	elseif root then
		-- Walk toward the player along the ground plane, facing the way we move.
		local from = enemy.part.Position
		local flatTarget = Vector3.new(root.Position.X, from.Y, root.Position.Z)
		local toTarget = flatTarget - from
		local planarDist = toTarget.Magnitude
		if planarDist > def.attackRange then
			local pos = from + toTarget.Unit * math.min(def.walkSpeed * speedMult * dt, planarDist)
			enemy.part.CFrame = CFrame.lookAt(pos, Vector3.new(flatTarget.X, pos.Y, flatTarget.Z))
		elseif planarDist > 0.05 then
			enemy.part.CFrame = CFrame.lookAt(from, flatTarget)
		end
	end

	-- Resolve a pending windup first (independent of the current range
	-- check below) — the swing already committed and the client is showing
	-- the telegraph, so it lands on schedule. "Dodging" a committed swing
	-- means being gone entirely (dead/downed/evasion roll), not stepping
	-- one stud back over the attackRange line.
	if enemy.windingUp and now >= enemy.windupEndsAt then
		enemy.windingUp = false
		setStatusMark(enemy, "telegraph", false)
		local swingTarget = enemy.windupTarget
		enemy.windupTarget = nil
		local humanoid = swingTarget and swingTarget.Character and swingTarget.Character:FindFirstChildOfClass("Humanoid")
		if swingTarget and humanoid and humanoid.Health > 0 and not HealthService.isDowned(swingTarget) then
			-- Evasion: a dodged hit deals nothing and applies no on-hit
			-- effects (the enemy still spent its attack).
			if (iframes[swingTarget.UserId] or 0) > now or math.random() < hookedDodgeChance(swingTarget) then
				dodgePopup(swingTarget.Character)
			else
				local isMagic = def.damageKind == "magic"
				local baseDmg = isMagic and enemy.ap or enemy.ad
				local mitigation = Classes.mitigation(isMagic and ClassService.getMR(swingTarget) or ClassService.getArmor(swingTarget))
				local taken = baseDmg * (1 - mitigation) * hookedDamageTakenMult(swingTarget)
				HealthService.damagePlayer(swingTarget, taken)
				HealthService.registerDamage(swingTarget) -- pause the player's regen
				-- Retribution: melee attackers eat a share of what they
				-- dealt (post-mitigation — what actually landed).
				local reflect = hookedReflect(swingTarget)
				if reflect > 0 then
					dealDamage(entry, enemy, math.max(1, math.floor(taken * reflect + 0.5)), swingTarget, false)
				end
				for _, fn in ipairs(EnemyService.playerHitHandlers) do
					task.spawn(fn, def.lootSource, swingTarget)
				end
			end
		end
	end

	-- Start a new windup if in range and off cooldown (and not already mid-
	-- swing). lastAttack advances here, at the START of the wind-up, so the
	-- overall attack cadence (attackCooldown) is unchanged from before —
	-- the windup eats into the existing gap between hits, it doesn't add on
	-- top of it.
	if not enemy.windingUp and root and (root.Position - enemy.part.Position).Magnitude <= def.attackRange then
		if now - enemy.lastAttack >= def.attackCooldown then
			enemy.lastAttack = now
			local windup = math.clamp(
				def.attackCooldown * Config.Combat.attackWindupFraction,
				Config.Combat.attackWindupMin,
				Config.Combat.attackWindupMax
			)
			enemy.windingUp = true
			enemy.windupTarget = target
			enemy.windupTotal = windup
			enemy.windupEndsAt = now + windup
			setStatusMark(enemy, "telegraph", true)
		end
	end
end

local function killEnemy(entry, enemy, killer)
	if enemy.dead then
		return
	end
	enemy.dead = true
	local position = enemy.part.Position
	local lootSource = enemy.def.lootSource
	local respawn = enemy.def.respawn
	local level = enemy.level
	enemy.part:Destroy()
	entry.enemy = nil

	-- Antes solo lo escuchaba el killer. Ahora, como el resto del audio de
	-- combate (swing, hit/crit — ver ToolService/EnemyService abajo), llega
	-- a cualquier jugador dentro de Config.CombatSfxHearRadius, aunque no
	-- haya sido quien remató al enemigo.
	if enemyDiedRemote then
		Remotes.fireNearby("EnemyDied", position, Config.CombatSfxHearRadius, lootSource)
	end

	if killer and enemy.def.xpReward then
		local xp = math.floor(enemy.def.xpReward * (1 + (level - 1) * XP_PER_LEVEL) + 0.5)
		PlayerService.addXp(killer, xp)
		-- Nearby party members get the same full reward (not split) so
		-- grouping up to fight never nets less xp per kill than soloing.
		for _, member in ipairs(PartyService.getNearbyPartyMembers(killer, position, XP_SHARE_RADIUS)) do
			PlayerService.addXp(member, xp)
		end
	end

	-- lootSource/position/killer stay first for backward compatibility;
	-- level is appended for handlers that want to scale on it (e.g. future
	-- quest tracking) — existing handlers can simply ignore the extra arg.
	for _, fn in ipairs(EnemyService.killedHandlers) do
		task.spawn(fn, lootSource, position, killer, level)
	end

	task.delay(respawn, function()
		spawnAt(entry)
	end)
end

-- Finds the enemy entry backed by a given part (the client's focused target).
local function entryForPart(part)
	for _, entry in ipairs(spawns) do
		if entry.enemy and not entry.enemy.dead and entry.enemy.part == part then
			return entry
		end
	end
	return nil
end

-- Picks the enemy a weapon should hit: the player's focused target if it's a
-- valid enemy within reach, otherwise the nearest enemy in range.
local function targetFor(player, root, reach)
	local focused = entryForPart(TargetService.get(player))
	if focused and (focused.enemy.part.Position - root.Position).Magnitude <= reach then
		return focused, focused.enemy
	end

	local hitEntry, hitEnemy, hitDist
	for _, entry in ipairs(spawns) do
		local enemy = entry.enemy
		if enemy and not enemy.dead then
			local dist = (enemy.part.Position - root.Position).Magnitude
			if dist <= reach and (not hitDist or dist < hitDist) then
				hitEntry, hitEnemy, hitDist = entry, enemy, dist
			end
		end
	end
	return hitEntry, hitEnemy
end

-- damageKind ("melee" | "physical" | "magic"), when provided, picks which of
-- the enemy's resist stats mitigates this hit — armor for melee/physical,
-- magicResist for magic — using the same MOBA-style curve as player armor/MR
-- (Classes.mitigation). Omitted (nil) for hits that intentionally bypass
-- resistances (e.g. Retribution's reflect damage).
dealDamage = function(entry, enemy, damage, killer, isCrit, damageKind)
	if not enemy or enemy.dead then
		return
	end
	-- Every hit (re)locks the enemy onto the attacker — see updateEnemy.
	if killer then
		enemy.aggroBy = killer
		enemy.aggroUntil = os.clock() + AGGRO_DURATION
	end
	if damageKind then
		local resist = damageKind == "magic" and enemy.magicResist or enemy.armor
		if resist and resist > 0 then
			damage = math.max(1, math.floor(damage * (1 - Classes.mitigation(resist)) + 0.5))
		end
	end
	-- Hunter's Mark: amplified damage from everyone while it lasts.
	if enemy.markedUntil then
		if os.clock() < enemy.markedUntil then
			damage = math.floor(damage * (1 + (enemy.markAmp or 0)) + 0.5)
		else
			enemy.markedUntil, enemy.markAmp = nil, nil
		end
	end
	enemy.hp -= damage
	updateHealthBar(enemy)
	if killer and damageIndicatorRemote then
		damageIndicatorRemote:FireClient(killer, damage, isCrit, enemy.part.Position)
	end
	if enemy.hp <= 0 then
		killEnemy(entry, enemy, killer)
	end
end

-- ---- public combat API (used by SpellService) -------------------------------
-- Spell code sees enemies as opaque refs: { entry, enemy, part }. `part` is
-- the enemy's body part (for missile flight / splash centers); everything
-- else stays internal to this file.

local function makeRef(entry)
	if entry and entry.enemy and not entry.enemy.dead then
		return { entry = entry, enemy = entry.enemy, part = entry.enemy.part }
	end
	return nil
end

-- The player's focused (RMB-locked) enemy if it's within `maxRange`, or nil.
function EnemyService.focusedTarget(player, maxRange)
	local character = player.Character
	local root = character and character:FindFirstChild("HumanoidRootPart")
	if not root then
		return nil
	end
	local focused = entryForPart(TargetService.get(player))
	if focused and (focused.enemy.part.Position - root.Position).Magnitude <= maxRange then
		return makeRef(focused)
	end
	return nil
end

function EnemyService.nearestTarget(position, range)
	local best, bestDist
	for _, entry in ipairs(spawns) do
		local enemy = entry.enemy
		if enemy and not enemy.dead then
			local dist = (enemy.part.Position - position).Magnitude
			if dist <= range and (not bestDist or dist < bestDist) then
				best, bestDist = entry, dist
			end
		end
	end
	return makeRef(best)
end

function EnemyService.enemiesNear(position, radius)
	local refs = {}
	for _, entry in ipairs(spawns) do
		local enemy = entry.enemy
		if enemy and not enemy.dead and (enemy.part.Position - position).Magnitude <= radius then
			table.insert(refs, makeRef(entry))
		end
	end
	return refs
end

-- Applies already-rolled damage (see computePlayerDamage) to a ref.
-- damageKind ("melee" | "physical" | "magic") picks the enemy's mitigating
-- resist stat, same as dealDamage — pass the spell/weapon's own damageKind
-- (def.damageKind) so zone/AoE hits mitigate correctly per-target even when
-- the raw damage number was rolled once and applied to several enemies.
function EnemyService.dealSpellDamage(ref, damage, player, isCrit, damageKind)
	if ref and ref.enemy then
		dealDamage(ref.entry, ref.enemy, damage, player, isCrit == true, damageKind)
	end
end

-- Enemy-side diminishing returns, mirroring the player-side EffectService
-- rule: the same CC kind reapplied within 8s lands at 100/50/25% duration
-- (the math.max in stun/slow means an active timer is never CUT). This is
-- the guard that lets Inferno/control scale without party permastun.
local DR_WINDOW = 8
local DR_STEPS = { 1, 0.5, 0.25 }

local function diminishedDuration(enemy, kind, duration)
	local now = os.clock()
	local dr = enemy.dr
	if not dr then
		dr = {}
		enemy.dr = dr
	end
	local state = dr[kind]
	if state and now < state.windowUntil then
		state.count = math.min(state.count + 1, #DR_STEPS)
	else
		state = { count = 1 }
		dr[kind] = state
	end
	state.windowUntil = now + DR_WINDOW
	return duration * DR_STEPS[state.count]
end

-- `player` (optional) is the caster: their debuff-duration bonus (Inferno)
-- scales the stun before diminishing returns apply.
function EnemyService.stun(ref, duration, player)
	if ref and ref.enemy and not ref.enemy.dead then
		local enemy = ref.enemy
		if player then
			duration *= 1 + hookedDebuffDurationBonus(player)
		end
		duration = diminishedDuration(enemy, "stun", duration)
		enemy.stunnedUntil = math.max(enemy.stunnedUntil or 0, os.clock() + duration)
		enemy.stunTotal = enemy.stunnedUntil - os.clock() -- drain bar refills on refresh
	end
end

-- Slows the enemy's movement to `mult` (default 0.5) for `duration` seconds.
-- Reapplying refreshes the timer; the strongest (lowest) mult wins.
-- `player` (optional) is the caster: Inferno lengthens the slow and the
-- control passive (Trapper) deepens it — a 50% slow at +40% control becomes
-- a 70% slow, floored so enemies always keep a crawl.
function EnemyService.slow(ref, duration, mult, player)
	if ref and ref.enemy and not ref.enemy.dead then
		local enemy = ref.enemy
		mult = mult or 0.5
		if player then
			duration *= 1 + hookedDebuffDurationBonus(player)
			local potency = hookedSlowPotency(player)
			if potency > 0 then
				mult = math.max(0.05, 1 - (1 - mult) * (1 + potency))
			end
		end
		duration = diminishedDuration(enemy, "slow", duration)
		enemy.slowedUntil = math.max(enemy.slowedUntil or 0, os.clock() + duration)
		enemy.slowMult = math.min(enemy.slowMult or 1, mult)
		enemy.slowTotal = enemy.slowedUntil - os.clock()
	end
end

function EnemyService.taunt(ref, player, duration)
	if ref and ref.enemy and not ref.enemy.dead then
		ref.enemy.tauntedBy = player
		ref.enemy.tauntedUntil = os.clock() + duration
	end
end

-- Hunter's Mark: while marked, the enemy takes `amp` extra damage from ALL
-- sources (applied in dealDamage). Duration scales with the marker's
-- debuff-duration bonus (Inferno) and rides the same enemy-side DR.
function EnemyService.mark(ref, amp, duration, player)
	if ref and ref.enemy and not ref.enemy.dead then
		local enemy = ref.enemy
		if player then
			duration *= 1 + hookedDebuffDurationBonus(player)
		end
		duration = diminishedDuration(enemy, "mark", duration)
		enemy.markedUntil = math.max(enemy.markedUntil or 0, os.clock() + duration)
		enemy.markAmp = math.max(enemy.markAmp or 0, amp)
	end
end

-- Yanks the enemy to ~2 studs from `position` (Singularity's pull), ground-
-- snapped and facing the center. A hop mid-flight is cancelled into its
-- landing squash so the move sticks instead of the hop lerp fighting it.
function EnemyService.pullTo(ref, position)
	if not (ref and ref.enemy) or ref.enemy.dead then
		return
	end
	local enemy = ref.enemy
	local from = enemy.part.Position
	local flat = Vector3.new(from.X - position.X, 0, from.Z - position.Z)
	local offset = flat.Magnitude > 0.05 and flat.Unit * 2 or Vector3.new(2, 0, 0)
	local target = position + offset
	local y = groundY(target.X, target.Z) + enemy.def.size.Y / 2
	enemy.part.CFrame = CFrame.lookAt(Vector3.new(target.X, y, target.Z), Vector3.new(position.X, y, position.Z))
	if enemy.def.movement == "hop" then
		enemy.hopFrom, enemy.hopTo = nil, nil
		enemy.hopState = "squash"
		enemy.hopT = 0
		setSquash(enemy, 0.7)
	end
end

-- Spawns a glowing magic missile that flies from `fromPos` to the target part,
-- then runs `onArrive`. Anchored + non-colliding so it just replicates as a
-- cosmetic projectile to every client.
-- Visuals per damage kind: magic keeps the glowing orb, a physical bow shot
-- reads as a plain wooden arrow instead.
local PROJECTILE_VISUALS = {
	magic = { name = "MagicMissile", shape = Enum.PartType.Ball, size = Vector3.new(1.2, 1.2, 1.2), color = Color3.fromRGB(150, 90, 255), material = Enum.Material.Neon, glow = true },
	physical = { name = "Arrow", shape = Enum.PartType.Cylinder, size = Vector3.new(0.15, 0.15, 3), color = Color3.fromRGB(120, 85, 45), material = Enum.Material.Wood, glow = false },
}

local function fireMissile(fromPos, targetPart, onArrive, damageKind, colorOverride)
	local visual = PROJECTILE_VISUALS[damageKind] or PROJECTILE_VISUALS.magic

	local missile = Instance.new("Part")
	missile.Name = visual.name
	missile.Shape = visual.shape
	missile.Size = visual.size
	missile.Color = colorOverride or visual.color
	missile.Material = visual.material
	missile.Anchored = true
	missile.CanCollide = false
	missile.CanQuery = false
	missile.Position = fromPos

	if visual.glow or colorOverride then
		local light = Instance.new("PointLight")
		light.Color = missile.Color
		light.Range = 8
		light.Brightness = 3
		light.Parent = missile
	end

	-- NOT in enemyFolder: the client targets every part in there, and a
	-- projectile must never steal focus from the enemy it flies at.
	missile.Parent = Workspace

	local destination = targetPart.Position
	local travel = math.clamp((destination - fromPos).Magnitude / MISSILE_SPEED, 0.05, 1)
	local tween = TweenService:Create(missile, TweenInfo.new(travel, Enum.EasingStyle.Linear), { Position = destination })
	tween.Completed:Connect(function()
		missile:Destroy()
		onArrive()
	end)
	tween:Play()
end

-- ---- Arrow ammo (bows only — def.usesArrows; see shared/Items.lua) --------
-- Bows need a matching arrow-type item in the inventory to fire at all; the
-- shot consumes one. Live-only per-player state (not persisted), same
-- treatment as ManaService: it just resets to the basic arrow on rejoin.

-- Canonical rotation order for the cycle key (client/ArrowSelectUI.lua). The
-- plain arrow always comes first so a fresh player without crafting
-- materials for the fancy ones can still shoot.
local ARROW_ORDER = { "arrow", "arrow_fire", "arrow_poison" }

local selectedArrow = {} -- [userId] = itemId
local lastArrowCycle = {} -- [userId] = os.clock(), debounces the cycle key
local lastArrowWarn = {} -- [userId] = os.clock(), debounces the "no arrows" toast
local ARROW_CYCLE_COOLDOWN = 0.25

local function ownsArrow(player, itemId)
	return PlayerService.getItemCount(player, itemId) > 0
end

-- The arrow itemId to fire with right now: the player's selection if they
-- still have some in the inventory, otherwise the first type in ARROW_ORDER
-- they DO have. Returns nil if the quiver is completely empty.
local function resolveArrow(player)
	local want = selectedArrow[player.UserId] or ARROW_ORDER[1]
	if ownsArrow(player, want) then
		return want
	end
	for _, itemId in ipairs(ARROW_ORDER) do
		if ownsArrow(player, itemId) then
			return itemId
		end
	end
	return nil
end

-- Advances the player's selection to the next arrow type they actually own
-- (wrapping around ARROW_ORDER), and toasts the new pick. Called from the
-- CycleArrow remote (client fires it on a keypress while a bow is equipped).
local function cycleArrow(player)
	local now = os.clock()
	if now - (lastArrowCycle[player.UserId] or 0) < ARROW_CYCLE_COOLDOWN then
		return
	end
	lastArrowCycle[player.UserId] = now

	local current = selectedArrow[player.UserId] or ARROW_ORDER[1]
	local startIndex = 1
	for i, itemId in ipairs(ARROW_ORDER) do
		if itemId == current then
			startIndex = i
			break
		end
	end
	for step = 1, #ARROW_ORDER do
		local index = ((startIndex - 1 + step) % #ARROW_ORDER) + 1
		local itemId = ARROW_ORDER[index]
		if ownsArrow(player, itemId) then
			selectedArrow[player.UserId] = itemId
			if notifyRemote then
				local itemDef = Items.get(itemId)
				notifyRemote:FireClient(player, "Flecha: " .. (itemDef and itemDef.name or itemId))
			end
			return
		end
	end
	selectedArrow[player.UserId] = current
	if notifyRemote then
		notifyRemote:FireClient(player, "No te quedan flechas")
	end
end

-- Tinted missile trail per arrow effect, purely cosmetic (the enemy still
-- gets the normal wooden-arrow model from PROJECTILE_VISUALS otherwise).
local ARROW_EFFECT_COLORS = {
	burn = Color3.fromRGB(255, 110, 40),
	poison = Color3.fromRGB(110, 220, 90),
}

-- Applies (or refreshes/stacks) a bow ammo's damage-over-time onto the hit
-- enemy. `effect` is an arrow item's `arrowEffect` table (shared/Items.lua):
--   { kind, damagePerTick, interval, duration, maxStacks? }
-- Effects without maxStacks (e.g. burn) just refresh their timer on repeat
-- hits; effects with maxStacks (e.g. poison) also add a stack, multiplying
-- the per-tick damage, up to the cap. Ticked in updateEnemy above.
local function applyArrowEffect(enemy, effect, player)
	if not enemy or enemy.dead or not effect then
		return
	end
	enemy.dots = enemy.dots or {}
	local now = os.clock()
	local existing = enemy.dots[effect.kind]
	local stacks = 1
	if effect.maxStacks then
		stacks = math.min((existing and existing.stacks or 0) + 1, effect.maxStacks)
	end
	enemy.dots[effect.kind] = {
		untilTime = math.max(existing and existing.untilTime or 0, now + effect.duration),
		totalDuration = effect.duration,
		nextTick = (existing and existing.nextTick) or (now + effect.interval),
		interval = effect.interval,
		baseDmg = effect.damagePerTick,
		stacks = stacks,
		source = player,
	}
end

-- Called by ToolService when a "weapon" item is activated. Melee weapons hit
-- instantly and can auto-swing at the nearest enemy; ranged weapons (staff)
-- only fire at an explicitly focused target and launch a magic missile that
-- damages on impact.
local function onWeaponSwing(player, tool, def)
	local character = player.Character
	local root = character and character:FindFirstChild("HumanoidRootPart")
	if not root or HealthService.isDowned(player) then
		return
	end

	local reach = def.reach or DEFAULT_REACH
	local ranged = def.weaponType == "ranged"

	local hitEntry, hitEnemy
	if ranged then
		-- Ranged weapons require a focus: fire only at the locked target, and
		-- only while it's within reach. No target, no shot.
		local focused = entryForPart(TargetService.get(player))
		if focused and (focused.enemy.part.Position - root.Position).Magnitude <= reach then
			hitEntry, hitEnemy = focused, focused.enemy
		end
	else
		hitEntry, hitEnemy = targetFor(player, root, reach)
	end

	if not hitEnemy then
		return
	end

	local damageKind = def.damageKind or (ranged and "physical" or "melee")
	local damage, isCrit = EnemyService.computePlayerDamage(player, def.damage or 10, damageKind)

	-- Leech: WEAPON hits heal back a share of their damage (spells go
	-- through dealSpellDamage and deliberately don't).
	local function applyLifesteal()
		local lifesteal = hookedLifesteal(player)
		if lifesteal > 0 then
			HealthService.heal(player, damage * lifesteal)
		end
	end

	if ranged then
		-- Ranged magic costs mana; block the cast (and warn) when too low. Only
		-- charged here, once we know there's a valid target to fire at.
		local cost = def.manaCost or 0
		if cost > 0 and not ManaService.trySpend(player, cost) then
			local now = os.clock()
			if notifyRemote and now - (lastManaWarn[player.UserId] or 0) >= MANA_WARN_COOLDOWN then
				lastManaWarn[player.UserId] = now
				notifyRemote:FireClient(player, "Not enough mana")
			end
			return
		end

		-- Bows need an arrow in the inventory to fire; consumed 1 per shot
		-- (the free Double Nock echo below does NOT consume a second one).
		local arrowId
		if def.usesArrows then
			arrowId = resolveArrow(player)
			if not arrowId then
				local now = os.clock()
				if notifyRemote and now - (lastArrowWarn[player.UserId] or 0) >= MANA_WARN_COOLDOWN then
					lastArrowWarn[player.UserId] = now
					notifyRemote:FireClient(player, "No te quedan flechas")
				end
				return
			end
			PlayerService.removeItem(player, arrowId, 1)
		end
		local arrowDef = arrowId and Items.get(arrowId)
		local arrowEffect = arrowDef and arrowDef.arrowEffect
		local arrowColor = arrowEffect and ARROW_EFFECT_COLORS[arrowEffect.kind]

		-- Special arrows hit softer on impact than a plain arrow — the
		-- damageMult (shared/Items.lua, e.g. 0.75 = 25% less) is what they
		-- trade away for their DoT, so picking one is a real choice and not
		-- a strict upgrade.
		if arrowDef and arrowDef.damageMult then
			damage = math.max(1, math.floor(damage * arrowDef.damageMult + 0.5))
		end

		fireMissile(root.Position + Vector3.new(0, 2, 0), hitEnemy.part, function()
			dealDamage(hitEntry, hitEnemy, damage, player, isCrit, damageKind)
			applyLifesteal()
			if arrowEffect then
				applyArrowEffect(hitEnemy, arrowEffect, player)
			end
		end, damageKind, arrowColor)
		-- Double Nock: a primed charge echoes the shot — a second arrow at the
		-- same target with its own damage/crit roll, no extra mana or ammo.
		for _, fn in ipairs(extraShotHooks) do
			local ok, extra = pcall(fn, player)
			if ok and extra == true then
				task.delay(0.15, function()
					if hitEnemy.dead or not root.Parent then
						return
					end
					local echoDamage, echoCrit = EnemyService.computePlayerDamage(player, def.damage or 10, damageKind)
					if arrowDef and arrowDef.damageMult then
						echoDamage = math.max(1, math.floor(echoDamage * arrowDef.damageMult + 0.5))
					end
					fireMissile(root.Position + Vector3.new(0, 2, 0), hitEnemy.part, function()
						dealDamage(hitEntry, hitEnemy, echoDamage, player, echoCrit, damageKind)
						local lifesteal = hookedLifesteal(player)
						if lifesteal > 0 then
							HealthService.heal(player, echoDamage * lifesteal)
						end
						if arrowEffect then
							applyArrowEffect(hitEnemy, arrowEffect, player)
						end
					end, damageKind, arrowColor)
				end)
			end
		end
	else
		dealDamage(hitEntry, hitEnemy, damage, player, isCrit, damageKind)
		applyLifesteal()
	end
end

function EnemyService.start()
	notifyRemote = Remotes.get("Notify")
	damageIndicatorRemote = Remotes.get("DamageIndicator")
	enemyDiedRemote = Remotes.get("EnemyDied")

	-- Client (ArrowSelectUI) fires this on a keypress while a bow is
	-- equipped to cycle which owned arrow type gets fired next.
	Remotes.get("CycleArrow").OnServerEvent:Connect(function(player)
		cycleArrow(player)
	end)

	Players.PlayerRemoving:Connect(function(player)
		lastManaWarn[player.UserId] = nil
		lastArrowWarn[player.UserId] = nil
		lastArrowCycle[player.UserId] = nil
		selectedArrow[player.UserId] = nil
	end)

	enemyFolder = Instance.new("Folder")
	enemyFolder.Name = "Enemies"
	enemyFolder.Parent = Workspace

	-- Authored maps place spawn points via Enemy_<key> markers (same pattern
	-- as GatheringService's Node_ markers, docs/MAP_AUTHORING.md); the defs'
	-- `spots` lists stay the fallback for places without a map.
	if MapMarkers.mapPresent() then
		local markers = MapMarkers.takeFor("Enemy_", ENEMY_DEFS)
		for key, def in pairs(ENEMY_DEFS) do
			for _, marker in ipairs(markers[key] or {}) do
				local entry = { def = def, pos = marker.cframe.Position, enemy = nil }
				table.insert(spawns, entry)
				spawnAt(entry)
			end
		end
	else
		for _, def in pairs(ENEMY_DEFS) do
			for _, pos in ipairs(def.spots) do
				local entry = { def = def, pos = pos, enemy = nil }
				table.insert(spawns, entry)
				spawnAt(entry)
			end
		end
	end

	ToolService.registerActivated("weapon", onWeaponSwing)

	RunService.Heartbeat:Connect(function(dt)
		for _, entry in ipairs(spawns) do
			if entry.enemy then
				updateEnemy(entry, dt)
			end
		end
	end)
end

return EnemyService