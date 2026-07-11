-- Active spells (subclass abilities from shared/Spells.lua). Owns:
--   * which spells each player knows — derived from EQUIPMENT-earned school
--     points (SynergyService.getSchoolPoints; recomputed on every inventory/
--     Level/Class change, so equipping a Berserker item can unlock Battle
--     Cry on the spot) and pushed to the client through the SpellsChanged
--     remote (known + newlyUnlocked + recommended order);
--   * the CastSpell remote: validation (known, alive, cooldown, mana), then
--     dispatch to a behavior (projectile / zone / strike / aoe / buff /
--     taunt / summon / heal / line / revive);
--   * per-spell cooldowns, mirrored to the client as SpellCd_<id> player
--     attributes holding the expiry on the server clock (like Effect_<id>);
--   * subclass passives (+% damage / armor), fed into EnemyService's damage
--     hooks so weapon swings benefit too;
--   * summoned familiars (follow their owner, auto-attack nearby enemies).

local Players = game:GetService("Players")
local Workspace = game:GetService("Workspace")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Spells = require(Shared:WaitForChild("Spells"))
local Remotes = require(Shared:WaitForChild("Remotes"))
local ArtKit = require(Shared:WaitForChild("ArtKit"))

local PlayerService = require(script.Parent.PlayerService)
local ManaService = require(script.Parent.ManaService)
local EnemyService = require(script.Parent.EnemyService)
local EffectService = require(script.Parent.EffectService)
local SynergyService = require(script.Parent.SynergyService)
local HealthService = require(script.Parent.HealthService)
local ToolService = require(script.Parent.ToolService)

local SpellService = {}

local spellsChangedRemote -- RemoteEvent, resolved in start()
local notifyRemote -- RemoteEvent, resolved in start()

-- [userId] = { set = {spellId=true}, list = {spellId} } (list is priority-sorted)
local knownCache = {}

-- [userId] = { [spellId] = os.clock() expiry }
local cooldowns = {}

-- [userId] = { { part, expiresAt, lastShot, damage, shotEvery, range, color } }
local familiars = {}

-- Rate-limit failure toasts so key-mashing doesn't spam the corner.
local lastWarn = {} -- [userId] = os.clock()
local WARN_COOLDOWN = 1.5

local function warnPlayer(player, message)
	local now = os.clock()
	if notifyRemote and now - (lastWarn[player.UserId] or 0) >= WARN_COOLDOWN then
		lastWarn[player.UserId] = now
		notifyRemote:FireClient(player, message)
	end
end

-- ---- known spells + unlock push ----------------------------------------------

-- Recomputes the player's known spells from their equipment-earned school
-- points; pushes SpellsChanged (and toasts) when something new unlocked.
-- `recommended` is the same priority-sorted list — v1 of the hotbar
-- recommendation system (see docs/TRAITS_AND_SPELLS.md).
local function pushSpells(player)
	if not PlayerService.get(player) then
		return -- profile still loading; the load-time recompute re-fires this
	end
	local list = Spells.knownFor(SynergyService.getSchoolPoints(player))

	local previous = knownCache[player.UserId]
	local set, newlyUnlocked = {}, {}
	for _, spellId in ipairs(list) do
		set[spellId] = true
		if previous and not previous.set[spellId] then
			table.insert(newlyUnlocked, spellId)
		end
	end
	knownCache[player.UserId] = { set = set, list = list }

	if spellsChangedRemote then
		spellsChangedRemote:FireClient(player, {
			known = list,
			-- On the very first push (login) nothing counts as "newly
			-- unlocked" — the client seeds its hotbar from `recommended`.
			newlyUnlocked = previous and newlyUnlocked or {},
			recommended = list,
		})
	end

	if previous and notifyRemote then
		for _, spellId in ipairs(newlyUnlocked) do
			local def = Spells.get(spellId)
			notifyRemote:FireClient(player, ("New spell: %s %s"):format(def.name, def.icon or ""))
		end
	end
end

function SpellService.isKnown(player, spellId)
	local cache = knownCache[player.UserId]
	return cache ~= nil and cache.set[spellId] == true
end

-- ---- visual helpers ------------------------------------------------------------

local function makeCosmeticPart(props)
	local part = Instance.new("Part")
	part.Anchored = true
	part.CanCollide = false
	part.CanQuery = false
	part.Material = Enum.Material.Neon
	part.CastShadow = false
	for key, value in pairs(props) do
		part[key] = value
	end
	return part
end

-- A quick expanding-and-fading sphere (impacts, AoE bursts).
local function burst(position, color, radius, duration)
	local ball = makeCosmeticPart({
		Name = "SpellBurst",
		Shape = Enum.PartType.Ball,
		Size = Vector3.new(1, 1, 1),
		Color = color,
		Transparency = 0.2,
		Position = position,
	})
	ball.Parent = Workspace
	local tween = TweenService:Create(
		ball,
		TweenInfo.new(duration or 0.4, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
		{ Size = Vector3.new(radius * 2, radius * 2, radius * 2), Transparency = 1 }
	)
	tween.Completed:Connect(function()
		ball:Destroy()
	end)
	tween:Play()
end

-- Flies a glowing bolt from `fromPos` to the target ref's part, then calls
-- onArrive. Same cosmetic-tween approach as EnemyService's weapon missiles,
-- but sized/colored per spell.
local function fireBolt(fromPos, targetPart, missile, onArrive)
	local size = missile and missile.size or 1
	local speed = missile and missile.speed or 90
	local bolt = makeCosmeticPart({
		Name = "SpellBolt",
		Shape = Enum.PartType.Ball,
		Size = Vector3.new(size, size, size),
		Color = missile and missile.color or Color3.fromRGB(150, 90, 255),
		Position = fromPos,
	})
	local light = Instance.new("PointLight")
	light.Color = bolt.Color
	light.Range = 8
	light.Brightness = 3
	light.Parent = bolt
	bolt.Parent = Workspace

	local destination = targetPart.Position
	local travel = math.clamp((destination - fromPos).Magnitude / speed, 0.05, 1.5)
	local tween = TweenService:Create(bolt, TweenInfo.new(travel, Enum.EasingStyle.Linear), { Position = destination })
	tween.Completed:Connect(function()
		bolt:Destroy()
		onArrive()
	end)
	tween:Play()
end

-- Snaps a position to the ground (for zone placement), ignoring characters,
-- enemies, and cosmetic parts.
local function groundPosition(position)
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	local exclude = {}
	local enemyFolder = Workspace:FindFirstChild("Enemies")
	if enemyFolder then
		table.insert(exclude, enemyFolder)
	end
	for _, player in ipairs(Players:GetPlayers()) do
		if player.Character then
			table.insert(exclude, player.Character)
		end
	end
	params.FilterDescendantsInstances = exclude
	local result = Workspace:Raycast(position + Vector3.new(0, 40, 0), Vector3.new(0, -200, 0), params)
	return result and result.Position or position
end

-- ---- behaviors -------------------------------------------------------------------
-- Each behavior resolves its target FIRST and returns either a `fire` thunk
-- (cast is valid — mana/cooldown get committed, then the thunk runs) or
-- (nil, "reason") so nothing is charged on a whiffed cast.

local function acquireTarget(player, root, def)
	local ref = EnemyService.focusedTarget(player, def.range)
	if not ref and not def.requiresFocus then
		ref = EnemyService.nearestTarget(root.Position, def.range)
	end
	return ref
end

local BEHAVIORS = {}

function BEHAVIORS.projectile(player, root, def)
	local ref = acquireTarget(player, root, def)
	if not ref then
		return nil, def.requiresFocus and "You need a focused target" or "No target in range"
	end
	return function()
		local damage, isCrit = EnemyService.computePlayerDamage(player, def.damage, def.damageKind)
		fireBolt(root.Position + Vector3.new(0, 2, 0), ref.part, def.missile, function()
			local impactPos = ref.part and ref.part.Position or nil
			EnemyService.dealSpellDamage(ref, damage, player, isCrit)
			if def.splashRadius and impactPos then
				burst(impactPos, def.missile and def.missile.color or Color3.new(1, 1, 1), def.splashRadius)
				local splash = math.max(1, math.floor(damage * (def.splashMult or 0.5) + 0.5))
				for _, other in ipairs(EnemyService.enemiesNear(impactPos, def.splashRadius)) do
					if other.enemy ~= ref.enemy then
						EnemyService.dealSpellDamage(other, splash, player, false)
					end
				end
			end
		end)
	end
end

-- Ticking ground zones (Muro de Llamas, Lluvia Arcana, Tormenta Arcana).
function BEHAVIORS.zone(player, root, def)
	local centerCF
	if def.placement == "front" then
		local look = root.CFrame.LookVector
		local flat = Vector3.new(look.X, 0, look.Z)
		flat = flat.Magnitude > 0.05 and flat.Unit or Vector3.new(0, 0, -1)
		local pos = groundPosition(root.Position + flat * def.frontDistance)
		centerCF = CFrame.lookAt(pos, pos + flat)
	else -- "target"
		local ref = acquireTarget(player, root, def)
		if not ref then
			return nil, "No target in range"
		end
		local pos = groundPosition(ref.part.Position)
		centerCF = CFrame.new(pos)
	end

	return function()
		local visual
		if def.box then
			visual = makeCosmeticPart({
				Name = "SpellZone",
				Size = Vector3.new(def.box.width, def.box.height, def.box.depth),
				Color = def.color,
				Transparency = 0.45,
				CFrame = centerCF * CFrame.new(0, def.box.height / 2, 0),
			})
		else
			-- Flat disc: a cylinder's height runs along X, so lay it on its side.
			visual = makeCosmeticPart({
				Name = "SpellZone",
				Shape = Enum.PartType.Cylinder,
				Size = Vector3.new(0.4, def.radius * 2, def.radius * 2),
				Color = def.color,
				Transparency = 0.45,
				CFrame = centerCF * CFrame.new(0, 0.3, 0) * CFrame.Angles(0, 0, math.rad(90)),
			})
		end
		local light = Instance.new("PointLight")
		light.Color = def.color
		light.Range = math.max(def.radius or def.box.width, 8)
		light.Brightness = 1.5
		light.Parent = visual
		visual.Parent = Workspace

		-- Enemies inside the shape take a (crit-less) tick every interval,
		-- and/or get slowed (Snare Trap is a pure-slow zone: tickDamage 0).
		local searchRadius = def.radius or math.max(def.box.width, def.box.depth)
		task.spawn(function()
			local elapsed = 0
			while elapsed < def.duration do
				task.wait(def.tickInterval)
				elapsed += def.tickInterval
				local tick = 0
				if (def.tickDamage or 0) > 0 then
					tick = EnemyService.computePlayerDamage(player, def.tickDamage, def.damageKind, { noCrit = true })
				end
				for _, ref in ipairs(EnemyService.enemiesNear(centerCF.Position, searchRadius)) do
					local inside = true
					if def.box then
						local lp = centerCF:PointToObjectSpace(ref.part.Position)
						inside = math.abs(lp.X) <= def.box.width / 2 + 1 and math.abs(lp.Z) <= def.box.depth / 2 + 1
					end
					if inside then
						if tick > 0 then
							EnemyService.dealSpellDamage(ref, tick, player, false)
						end
						if def.slow then
							EnemyService.slow(ref, def.slow.duration, def.slow.mult, player)
						end
					end
				end
			end
			local fade = TweenService:Create(visual, TweenInfo.new(0.5), { Transparency = 1 })
			fade.Completed:Connect(function()
				visual:Destroy()
			end)
			fade:Play()
		end)
	end
end

-- Single-target hit at melee-ish range, optionally stunning (Golpe Salvaje,
-- Golpe Aturdidor, Veredicto).
function BEHAVIORS.strike(player, root, def)
	local ref = acquireTarget(player, root, def)
	if not ref then
		return nil, "No target in range"
	end
	return function()
		local damage, isCrit = EnemyService.computePlayerDamage(player, def.damage, def.damageKind)
		EnemyService.dealSpellDamage(ref, damage, player, isCrit)
		if def.stunDuration then
			EnemyService.stun(ref, def.stunDuration, player)
		end
		if ref.part then
			burst(ref.part.Position, Color3.fromRGB(255, 240, 200), 3, 0.25)
		end
	end
end

-- Burst around the caster (Juicio, SuperNova).
function BEHAVIORS.aoe(player, root, def)
	local refs = EnemyService.enemiesNear(root.Position, def.radius)
	if #refs == 0 then
		return nil, "No enemies nearby"
	end
	return function()
		burst(root.Position, def.color or Color3.new(1, 1, 1), def.radius, 0.5)
		for _, ref in ipairs(refs) do
			local damage, isCrit = EnemyService.computePlayerDamage(player, def.damage, def.damageKind)
			EnemyService.dealSpellDamage(ref, damage, player, isCrit)
			if def.stunDuration then
				EnemyService.stun(ref, def.stunDuration, player)
			end
		end
	end
end

-- Self (and optionally nearby-ally) buffs via EffectService.
function BEHAVIORS.buff(player, root, def)
	return function()
		EffectService.apply(player, def.effectId)
		if def.allyRadius then
			for _, other in ipairs(Players:GetPlayers()) do
				if other ~= player then
					local otherRoot = other.Character and other.Character:FindFirstChild("HumanoidRootPart")
					local humanoid = other.Character and other.Character:FindFirstChildOfClass("Humanoid")
					if otherRoot and humanoid and humanoid.Health > 0
						and (otherRoot.Position - root.Position).Magnitude <= def.allyRadius then
						EffectService.apply(other, def.effectId)
					end
				end
			end
		end
		burst(root.Position, Color3.fromRGB(255, 255, 255), 4, 0.3)
	end
end

-- Forces nearby enemies onto the caster + a self guard buff (Provocar).
function BEHAVIORS.taunt(player, root, def)
	return function()
		for _, ref in ipairs(EnemyService.enemiesNear(root.Position, def.radius)) do
			EnemyService.taunt(ref, player, def.tauntDuration)
		end
		if def.effectId then
			EffectService.apply(player, def.effectId)
		end
		burst(root.Position, Color3.fromRGB(220, 120, 120), def.radius / 2, 0.4)
	end
end

-- ---- healing (Cleric) -----------------------------------------------------------
-- Outgoing-heal roll: base amount * (1 + healing-school passives). Mirrors
-- EnemyService.computePlayerDamage's shape but heals don't crit.
local function computeHeal(player, baseAmount)
	local healing = Spells.passivesFor(SynergyService.getSchoolPoints(player)).healing
	return math.max(1, math.floor(baseAmount * (1 + healing) + 0.5))
end

-- Every other player within `radius` of `position` that's alive, as
-- { player, root, humanoid }. Used by both the "heal" auto-target and the
-- "line" behavior's ally sweep.
local function alliesNear(position, radius, exclude)
	local list = {}
	for _, other in ipairs(Players:GetPlayers()) do
		if other ~= exclude then
			local character = other.Character
			local otherRoot = character and character:FindFirstChild("HumanoidRootPart")
			local humanoid = character and character:FindFirstChildOfClass("Humanoid")
			if otherRoot and humanoid and humanoid.Health > 0
				and (otherRoot.Position - position).Magnitude <= radius then
				table.insert(list, { player = other, root = otherRoot, humanoid = humanoid })
			end
		end
	end
	return list
end

-- Smart-heal auto-target: the lowest-HP% ally in range that isn't already
-- full, falling back to self. No manual target-picking UI needed for this
-- first pass — every heal spell just finds whoever needs it most.
local function acquireHealTarget(player, root, range)
	local best, bestRatio
	for _, ally in ipairs(alliesNear(root.Position, range, player)) do
		if ally.humanoid.Health < ally.humanoid.MaxHealth then
			local ratio = ally.humanoid.Health / ally.humanoid.MaxHealth
			if not bestRatio or ratio < bestRatio then
				best, bestRatio = ally, ratio
			end
		end
	end
	if best then
		return best
	end
	local humanoid = player.Character and player.Character:FindFirstChildOfClass("Humanoid")
	if humanoid and humanoid.Health > 0 and humanoid.Health < humanoid.MaxHealth then
		return { player = player, root = root, humanoid = humanoid }
	end
	return nil
end

-- Single-target instant heal (Toque Curativo, Renacimiento's flat-% variant).
-- Nearest DOWNED ally in range — Renacimiento's target pool is disjoint
-- from acquireHealTarget's (downed players sit at 1 HP forever, so
-- "neediest by HP%" would always just point at whoever's already downed;
-- this instead only considers players HealthService actually has flagged).
local function acquireDownedAlly(root, range)
	local best, bestDist
	for _, ally in ipairs(alliesNear(root.Position, range, nil)) do
		if HealthService.isDowned(ally.player) then
			local dist = (ally.root.Position - root.Position).Magnitude
			if not bestDist or dist < bestDist then
				best, bestDist = ally, dist
			end
		end
	end
	return best
end

function BEHAVIORS.heal(player, root, def)
	local target = acquireHealTarget(player, root, def.range)
	if not target then
		return nil, "No one needs healing"
	end
	return function()
		local base = def.healPercent and (target.humanoid.MaxHealth * def.healPercent) or def.healAmount
		local amount = computeHeal(player, base)
		HealthService.heal(target.player, amount)
		burst(target.root.Position, Color3.fromRGB(160, 255, 190), 4, 0.3)
	end
end

-- Instant revive: skips a downed ally's bleed timer entirely (Renacimiento).
-- Distinct from "heal" — it targets HealthService's downed set specifically,
-- not "whoever's hurt", and goes through HealthService.reviveDowned instead
-- of a flat HP add so it also restores WalkSpeed/JumpPower and tears down
-- the ProximityPrompt/billboard, exactly like completing the manual revive.
function BEHAVIORS.revive(player, root, def)
	local target = acquireDownedAlly(root, def.range)
	if not target then
		return nil, "No one nearby is downed"
	end
	return function()
		-- healing-school passives scale how full the revive lands, same
		-- math as a flat heal, just expressed as a percent of max HP.
		local percent = math.min(1, def.healPercent * (1 + Spells.passivesFor(SynergyService.getSchoolPoints(player)).healing))
		HealthService.reviveDowned(target.player, percent)
		burst(target.root.Position, Color3.fromRGB(255, 235, 170), 6, 0.5)
	end
end

-- Instant line/box strike in front of the caster: enemies inside take
-- damage, allies inside get healed, in the same pass (Golpe Sagrado).
function BEHAVIORS.line(player, root, def)
	return function()
		local look = root.CFrame.LookVector
		local flat = Vector3.new(look.X, 0, look.Z)
		flat = flat.Magnitude > 0.05 and flat.Unit or Vector3.new(0, 0, -1)
		local pos = groundPosition(root.Position + flat * def.frontDistance)
		local centerCF = CFrame.lookAt(pos, pos + flat)
		local halfWidth, halfDepth = def.box.width / 2 + 1, def.box.depth / 2 + 1

		local visual = makeCosmeticPart({
			Name = "SpellLine",
			Size = Vector3.new(def.box.width, def.box.height, def.box.depth),
			Color = def.color,
			Transparency = 0.4,
			CFrame = centerCF * CFrame.new(0, def.box.height / 2, 0),
		})
		visual.Parent = Workspace
		local fade = TweenService:Create(visual, TweenInfo.new(0.35), { Transparency = 1 })
		fade.Completed:Connect(function()
			visual:Destroy()
		end)
		fade:Play()

		local searchRadius = math.max(def.box.width, def.box.depth)
		for _, ref in ipairs(EnemyService.enemiesNear(centerCF.Position, searchRadius)) do
			local lp = centerCF:PointToObjectSpace(ref.part.Position)
			if math.abs(lp.X) <= halfWidth and math.abs(lp.Z) <= halfDepth then
				local damage, isCrit = EnemyService.computePlayerDamage(player, def.damage, def.damageKind)
				EnemyService.dealSpellDamage(ref, damage, player, isCrit)
			end
		end
		for _, ally in ipairs(alliesNear(centerCF.Position, searchRadius, nil)) do
			local lp = centerCF:PointToObjectSpace(ally.root.Position)
			if math.abs(lp.X) <= halfWidth and math.abs(lp.Z) <= halfDepth then
				HealthService.heal(ally.player, computeHeal(player, def.healAmount))
			end
		end
	end
end

-- ---- familiars ----------------------------------------------------------------

local FAMILIAR_LOOKS = {
	familiar = { size = 1.2, color = Color3.fromRGB(120, 220, 180) },
	gran = { size = 2.2, color = Color3.fromRGB(220, 90, 90) },
}

local function despawnFamiliars(userId)
	local units = familiars[userId]
	if units then
		for _, unit in ipairs(units) do
			unit.part:Destroy()
		end
		familiars[userId] = nil
	end
end

local function spawnFamiliarUnit(player, root, def, index)
	local look = FAMILIAR_LOOKS[def.summon.variant] or FAMILIAR_LOOKS.familiar
	local part = makeCosmeticPart({
		Name = "Familiar",
		Shape = Enum.PartType.Ball,
		Size = Vector3.new(look.size, look.size, look.size),
		Color = look.color,
		Transparency = 0.15,
		Position = root.Position + Vector3.new(index * 2 - 3, 3, 0),
	})
	local eyeSize = look.size * 0.18
	ArtKit.weld(part, {
		{ name = "EyeL", size = Vector3.new(eyeSize, eyeSize * 1.4, eyeSize), offset = Vector3.new(-look.size * 0.2, look.size * 0.1, -look.size * 0.45), color = "ink" },
		{ name = "EyeR", size = Vector3.new(eyeSize, eyeSize * 1.4, eyeSize), offset = Vector3.new(look.size * 0.2, look.size * 0.1, -look.size * 0.45), color = "ink" },
	})
	local light = Instance.new("PointLight")
	light.Color = look.color
	light.Range = 6
	light.Brightness = 1.5
	light.Parent = part
	part.Parent = Workspace

	return {
		part = part,
		expiresAt = os.clock() + def.summon.duration,
		lastShot = 0,
		damage = def.summon.damage,
		shotEvery = def.summon.shotEvery,
		range = def.summon.range,
		color = look.color,
	}
end

function BEHAVIORS.summon(player, root, def)
	return function()
		-- Re-summoning replaces the current pets with a fresh full set.
		despawnFamiliars(player.UserId)
		local count = 1
		if def.summon.variant == "familiar" then
			count = Spells.familiarCountFor(SynergyService.getSchoolPoints(player))
		end
		local units = {}
		for i = 1, count do
			table.insert(units, spawnFamiliarUnit(player, root, def, i))
		end
		familiars[player.UserId] = units
		burst(root.Position + Vector3.new(0, 2, 0), FAMILIAR_LOOKS[def.summon.variant].color, 4, 0.4)
	end
end

-- Follow + auto-attack tick for every summoned familiar.
local FAMILIAR_TICK = 0.1
local function updateFamiliars()
	local now = os.clock()
	for userId, units in pairs(familiars) do
		local player = Players:GetPlayerByUserId(userId)
		local root = player and player.Character and player.Character:FindFirstChild("HumanoidRootPart")
		local humanoid = player and player.Character and player.Character:FindFirstChildOfClass("Humanoid")
		if not player or not root or not humanoid or humanoid.Health <= 0 then
			despawnFamiliars(userId)
			continue
		end

		-- Drop expired units.
		for i = #units, 1, -1 do
			if now >= units[i].expiresAt then
				units[i].part:Destroy()
				table.remove(units, i)
			end
		end
		if #units == 0 then
			familiars[userId] = nil
			continue
		end

		for index, unit in ipairs(units) do
			-- Orbit the owner with a lazy bob; ease toward the orbit point so
			-- movement reads floaty instead of snappy.
			local angle = now * 0.9 + index * (math.pi * 2 / #units)
			local orbit = root.Position + Vector3.new(
				math.cos(angle) * 3.2,
				2.6 + math.sin(now * 2 + index) * 0.35,
				math.sin(angle) * 3.2
			)
			local pos = unit.part.Position:Lerp(orbit, 0.18)
			local ref = EnemyService.nearestTarget(unit.part.Position, unit.range)
			if ref and ref.part then
				unit.part.CFrame = CFrame.lookAt(pos, ref.part.Position)
			else
				unit.part.CFrame = CFrame.lookAt(pos, pos + root.CFrame.LookVector)
			end

			if ref and now - unit.lastShot >= unit.shotEvery then
				unit.lastShot = now
				local damage = EnemyService.computePlayerDamage(player, unit.damage, "magic", { noCrit = true })
				fireBolt(unit.part.Position, ref.part, { size = 0.5, color = unit.color, speed = 80 }, function()
					EnemyService.dealSpellDamage(ref, damage, player, false)
				end)
			end
		end
	end
end

-- ---- casting ---------------------------------------------------------------------

local function tryCast(player, spellId)
	if typeof(spellId) ~= "string" then
		return
	end
	local def = Spells.get(spellId)
	if not def or def.implemented == false then
		return
	end
	if not SpellService.isKnown(player, spellId) then
		warnPlayer(player, "You don't know that spell yet")
		return
	end

	local character = player.Character
	local root = character and character:FindFirstChild("HumanoidRootPart")
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	if not root or not humanoid or humanoid.Health <= 0 or HealthService.isDowned(player) then
		return
	end

	local userCds = cooldowns[player.UserId]
	if not userCds then
		userCds = {}
		cooldowns[player.UserId] = userCds
	end
	if (userCds[spellId] or 0) > os.clock() then
		return -- still cooling down; the hotbar overlay already shows it
	end

	local behavior = BEHAVIORS[def.behavior]
	if not behavior then
		warn("[SpellService] no behavior for spell: " .. spellId)
		return
	end
	local fire, reason = behavior(player, root, def)
	if not fire then
		warnPlayer(player, reason or "Couldn't cast that")
		return
	end

	if (def.manaCost or 0) > 0 and not ManaService.trySpend(player, def.manaCost) then
		warnPlayer(player, "Not enough mana")
		return
	end

	userCds[spellId] = os.clock() + def.cooldown
	player:SetAttribute(Spells.cdAttributeFor(spellId), Workspace:GetServerTimeNow() + def.cooldown)

	fire()
end

-- ---- start ------------------------------------------------------------------------

function SpellService.start()
	spellsChangedRemote = Remotes.get("SpellsChanged")
	notifyRemote = Remotes.get("Notify")

	local castRemote = Remotes.get("CastSpell")
	castRemote.OnServerEvent:Connect(tryCast)

	-- Client pulls once at boot (mirrors RequestInventory: wait for the
	-- profile to finish loading instead of answering empty).
	local requestSpells = Remotes.getFunction("RequestSpells")
	requestSpells.OnServerInvoke = function(player)
		local deadline = os.clock() + 10
		while not PlayerService.get(player) and os.clock() < deadline do
			task.wait(0.1)
		end
		if not knownCache[player.UserId] then
			pushSpells(player)
		end
		local cache = knownCache[player.UserId]
		return {
			known = cache and cache.list or {},
			newlyUnlocked = {},
			recommended = cache and cache.list or {},
		}
	end

	-- School passives ride the same damage hooks as effect buffs, so weapon
	-- swings and spells both benefit. Armor converts to a damage-taken
	-- multiplier: 100/(100+armor) — 42 armor ≈ 30% less damage.
	EnemyService.registerDamageMult(function(player, kind)
		return 1 + (Spells.passivesFor(SynergyService.getSchoolPoints(player))[kind] or 0)
	end)
	EnemyService.registerDamageTakenMult(function(player)
		local armor = Spells.passivesFor(SynergyService.getSchoolPoints(player)).armor
		return armor > 0 and 100 / (100 + armor) or 1
	end)
	-- Ranger school passives (docs/TRAITS_CATALOG.md §2): Scout's attack
	-- speed sums with Agile Hands in the same swing-cooldown hook; Trapper's
	-- control makes the player's slows bite deeper.
	ToolService.registerSwingCooldownMult(function(player)
		return 1 / (1 + Spells.passivesFor(SynergyService.getSchoolPoints(player)).attackSpeed)
	end)
	EnemyService.registerSlowPotency(function(player)
		return Spells.passivesFor(SynergyService.getSchoolPoints(player)).control
	end)

	-- Equipment is the only source of school points, so knowns re-derive on
	-- every synergy recompute (equip/unequip, level gating, class switches).
	SynergyService.onRecomputed(pushSpells)

	Players.PlayerRemoving:Connect(function(player)
		knownCache[player.UserId] = nil
		cooldowns[player.UserId] = nil
		lastWarn[player.UserId] = nil
		despawnFamiliars(player.UserId)
	end)

	local accumulator = 0
	RunService.Heartbeat:Connect(function(dt)
		accumulator += dt
		if accumulator >= FAMILIAR_TICK then
			accumulator = 0
			updateFamiliars()
		end
	end)
end

return SpellService
