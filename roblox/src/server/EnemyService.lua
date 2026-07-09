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
local ToolService = require(script.Parent.ToolService)
local TargetService = require(script.Parent.TargetService)
local PlayerService = require(script.Parent.PlayerService)
local ClassService = require(script.Parent.ClassService)
local PartyService = require(script.Parent.PartyService)
local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared:WaitForChild("Config"))
local Remotes = require(Shared:WaitForChild("Remotes"))
local ArtKit = require(Shared:WaitForChild("ArtKit"))

local V = Vector3.new

local EnemyService = {}

local DEFAULT_REACH = Config.defaultReach -- fallback when a weapon def omits `reach`
local MISSILE_SPEED = 90 -- studs/second the magic missile travels
local CRIT_CHANCE = Config.Combat.critChance
local CRIT_MULTIPLIER = Config.Combat.critMultiplier
local HP_PER_LEVEL = Config.Combat.mobLevel.hpPerLevel
local DAMAGE_PER_LEVEL = Config.Combat.mobLevel.damagePerLevel
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

local notifyRemote -- RemoteEvent, resolved in start()

-- Rate-limit the "not enough mana" toast so staff-spamming doesn't spam it.
local lastManaWarn = {} -- [userId] = os.clock()
local MANA_WARN_COOLDOWN = 1.5

-- Data-driven enemy types.
local ENEMY_DEFS = {
	slime = {
		name = "Slime",
		hp = 30,
		damage = 5,
		minLevel = 1,
		maxLevel = 3,
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
		damage = 10,
		minLevel = 2,
		maxLevel = 5,
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

-- The full outgoing-damage roll for a player: class multiplier, hook
-- multipliers (effects + passives), then the crit roll. Used by weapon swings
-- here and by SpellService for spell damage. Returns (damage, isCrit).
function EnemyService.computePlayerDamage(player, baseDamage, damageKind, opts)
	local damage = baseDamage
		* ClassService.getDamageMult(player, damageKind)
		* hookedDamageMult(player, damageKind)

	local isCrit = false
	if not (opts and opts.noCrit) then
		local critChance = CRIT_CHANCE + ClassService.getCritBonus(player) + hookedCritBonus(player)
		isCrit = math.random() < critChance
		if isCrit then
			damage *= CRIT_MULTIPLIER
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

local function updateHealthBar(enemy)
	enemy.fill.Size = UDim2.new(math.clamp(enemy.hp / enemy.maxHp, 0, 1), 0, 1, 0)
end

local function buildEnemy(pos, def)
	local y = groundY(pos.X, pos.Z)

	local level = math.random(def.minLevel or 1, def.maxLevel or 1)
	local maxHp = math.floor(def.hp * (1 + (level - 1) * HP_PER_LEVEL) + 0.5)
	local damage = math.floor(def.damage * (1 + (level - 1) * DAMAGE_PER_LEVEL) + 0.5)

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

	-- Face/body details ride along with the body via welds.
	if def.details then
		ArtKit.weld(part, def.details)
	end

	-- Name + level label, sits just above the health bar.
	local nameTag = Instance.new("BillboardGui")
	nameTag.Name = "NameTag"
	nameTag.Size = UDim2.new(0, 140, 0, 20)
	nameTag.StudsOffsetWorldSpace = Vector3.new(0, def.size.Y / 2 + 1.9, 0)
	nameTag.AlwaysOnTop = true
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
	billboard.Size = UDim2.new(0, 60, 0, 8)
	billboard.StudsOffsetWorldSpace = Vector3.new(0, def.size.Y / 2 + 1, 0)
	billboard.AlwaysOnTop = true
	billboard.Parent = part

	local bg = Instance.new("Frame")
	bg.Size = UDim2.new(1, 0, 1, 0)
	bg.BackgroundColor3 = Color3.fromRGB(30, 30, 30)
	bg.BorderSizePixel = 0
	bg.Parent = billboard

	local fill = Instance.new("Frame")
	fill.Name = "Fill"
	fill.Size = UDim2.new(1, 0, 1, 0)
	fill.BackgroundColor3 = Color3.fromRGB(200, 60, 60)
	fill.BorderSizePixel = 0
	fill.Parent = bg

	part.Parent = enemyFolder

	return {
		part = part,
		fill = fill,
		hp = maxHp,
		maxHp = maxHp,
		damage = damage,
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
		if root and humanoid and humanoid.Health > 0 then
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

-- Floating status marks over an enemy (stun stars, slow snail) so CC reads at
-- a glance, each with a bar draining down the remaining duration.
-- Server-side BillboardGuis, same as the name tag / health bar.
local STATUS_MARKS = {
	stun = { text = "💫", offsetX = -0.9, spin = true, barColor = Color3.fromRGB(255, 220, 120) },
	slow = { text = "🐌", offsetX = 0.9, spin = false, barColor = Color3.fromRGB(120, 190, 255) },
}

local function setStatusMark(enemy, kind, active)
	enemy.marks = enemy.marks or {}
	local existing = enemy.marks[kind]
	if active and not existing then
		local look = STATUS_MARKS[kind]
		local gui = Instance.new("BillboardGui")
		gui.Name = "Mark_" .. kind
		gui.Size = UDim2.new(0, 26, 0, 32)
		gui.StudsOffsetWorldSpace = Vector3.new(look.offsetX, enemy.def.size.Y / 2 + 3, 0)
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

-- Whether a player is a valid live chase target within `range` of `position`.
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
		and (root.Position - position).Magnitude <= range
end

local function updateEnemy(enemy, dt)
	if enemy.dead then
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
	local speedMult = slowed and (enemy.slowMult or 0.5) or 1

	-- Stunned: no chasing, no winding up new hops, no attacking. A hop already
	-- in flight still lands (freezing mid-air reads as a bug, not a stun).
	if stunned then
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

	-- Attack if in range and off cooldown.
	if root and (root.Position - enemy.part.Position).Magnitude <= def.attackRange then
		if now - enemy.lastAttack >= def.attackCooldown then
			enemy.lastAttack = now
			local humanoid = target.Character:FindFirstChildOfClass("Humanoid")
			if humanoid and humanoid.Health > 0 then
				-- Evasion: a dodged hit deals nothing and applies no on-hit
				-- effects (the enemy still spent its attack).
				if math.random() < hookedDodgeChance(target) then
					dodgePopup(target.Character)
				else
					HealthService.damagePlayer(
						target,
						enemy.damage * ClassService.getDamageTakenMult(target) * hookedDamageTakenMult(target)
					)
					HealthService.registerDamage(target) -- pause the player's regen
					for _, fn in ipairs(EnemyService.playerHitHandlers) do
						task.spawn(fn, def.lootSource, target)
					end
				end
			end
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

local function dealDamage(entry, enemy, damage, killer, isCrit)
	if not enemy or enemy.dead then
		return
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
function EnemyService.dealSpellDamage(ref, damage, player, isCrit)
	if ref and ref.enemy then
		dealDamage(ref.entry, ref.enemy, damage, player, isCrit == true)
	end
end

function EnemyService.stun(ref, duration)
	if ref and ref.enemy and not ref.enemy.dead then
		local enemy = ref.enemy
		enemy.stunnedUntil = math.max(enemy.stunnedUntil or 0, os.clock() + duration)
		enemy.stunTotal = enemy.stunnedUntil - os.clock() -- drain bar refills on refresh
	end
end

-- Slows the enemy's movement to `mult` (default 0.5) for `duration` seconds.
-- Reapplying refreshes the timer; the strongest (lowest) mult wins.
function EnemyService.slow(ref, duration, mult)
	if ref and ref.enemy and not ref.enemy.dead then
		local enemy = ref.enemy
		enemy.slowedUntil = math.max(enemy.slowedUntil or 0, os.clock() + duration)
		enemy.slowMult = math.min(enemy.slowMult or 1, mult or 0.5)
		enemy.slowTotal = enemy.slowedUntil - os.clock()
	end
end

function EnemyService.taunt(ref, player, duration)
	if ref and ref.enemy and not ref.enemy.dead then
		ref.enemy.tauntedBy = player
		ref.enemy.tauntedUntil = os.clock() + duration
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

local function fireMissile(fromPos, targetPart, onArrive, damageKind)
	local visual = PROJECTILE_VISUALS[damageKind] or PROJECTILE_VISUALS.magic

	local missile = Instance.new("Part")
	missile.Name = visual.name
	missile.Shape = visual.shape
	missile.Size = visual.size
	missile.Color = visual.color
	missile.Material = visual.material
	missile.Anchored = true
	missile.CanCollide = false
	missile.CanQuery = false
	missile.Position = fromPos

	if visual.glow then
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
		fireMissile(root.Position + Vector3.new(0, 2, 0), hitEnemy.part, function()
			dealDamage(hitEntry, hitEnemy, damage, player, isCrit)
		end, damageKind)
	else
		dealDamage(hitEntry, hitEnemy, damage, player, isCrit)
	end
end

function EnemyService.start()
	notifyRemote = Remotes.get("Notify")
	damageIndicatorRemote = Remotes.get("DamageIndicator")

	Players.PlayerRemoving:Connect(function(player)
		lastManaWarn[player.UserId] = nil
	end)

	enemyFolder = Instance.new("Folder")
	enemyFolder.Name = "Enemies"
	enemyFolder.Parent = Workspace

	for _, def in pairs(ENEMY_DEFS) do
		for _, pos in ipairs(def.spots) do
			local entry = { def = def, pos = pos, enemy = nil }
			table.insert(spawns, entry)
			spawnAt(entry)
		end
	end

	ToolService.registerActivated("weapon", onWeaponSwing)

	RunService.Heartbeat:Connect(function(dt)
		for _, entry in ipairs(spawns) do
			if entry.enemy then
				updateEnemy(entry.enemy, dt)
			end
		end
	end)
end

return EnemyService
