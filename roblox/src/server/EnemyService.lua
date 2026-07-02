-- Enemies: spawn at fixed points, chase + melee the nearest player, take damage
-- from weapon swings, die, and respawn. On death, fires kill handlers (the drop
-- system hooks in here). Enemy types are data-driven (ENEMY_DEFS), so adding a
-- new enemy is just a new entry. In-memory per server.

local Players = game:GetService("Players")
local Workspace = game:GetService("Workspace")
local RunService = game:GetService("RunService")

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local HealthService = require(script.Parent.HealthService)
local ToolService = require(script.Parent.ToolService)
local Config = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Config"))

local EnemyService = {}

local MELEE_RANGE = Config.reach.weapon -- how close a player must be for their weapon to connect

-- Data-driven enemy types.
local ENEMY_DEFS = {
	slime = {
		name = "Slime",
		hp = 30,
		damage = 5,
		attackCooldown = 1.5,
		walkSpeed = 8,
		aggroRange = 30,
		attackRange = 6,
		respawn = 15,
		lootSource = "slime",
		size = Vector3.new(3, 3, 3),
		color = Color3.fromRGB(80, 200, 120),
		material = Enum.Material.SmoothPlastic,
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
		attackCooldown = 1.2,
		walkSpeed = 12,
		aggroRange = 35,
		attackRange = 6,
		respawn = 20,
		lootSource = "goblin",
		size = Vector3.new(2.5, 4, 2.5),
		color = Color3.fromRGB(90, 150, 70),
		material = Enum.Material.SmoothPlastic,
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

local function groundY(x, z)
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	params.FilterDescendantsInstances = { enemyFolder }
	local result = Workspace:Raycast(Vector3.new(x, 200, z), Vector3.new(0, -1000, 0), params)
	return result and result.Position.Y or 0
end

local function updateHealthBar(enemy)
	enemy.fill.Size = UDim2.new(math.clamp(enemy.hp / enemy.def.hp, 0, 1), 0, 1, 0)
end

local function buildEnemy(pos, def)
	local y = groundY(pos.X, pos.Z)

	local part = Instance.new("Part")
	part.Name = def.name
	part.Anchored = true
	part.Size = def.size
	part.Color = def.color
	part.Material = def.material
	part.Position = Vector3.new(pos.X, y + def.size.Y / 2, pos.Z)

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

	return { part = part, fill = fill, hp = def.hp, lastAttack = 0, dead = false, def = def }
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

local function updateEnemy(enemy, dt)
	if enemy.dead then
		return
	end
	local def = enemy.def
	local target = nearestPlayer(enemy.part.Position, def.aggroRange)
	if not target then
		return
	end
	local root = target.Character:FindFirstChild("HumanoidRootPart")
	if not root then
		return
	end

	-- Move toward the player along the ground plane (keep our own height).
	local from = enemy.part.Position
	local flatTarget = Vector3.new(root.Position.X, from.Y, root.Position.Z)
	local toTarget = flatTarget - from
	local planarDist = toTarget.Magnitude
	if planarDist > def.attackRange then
		local step = toTarget.Unit * math.min(def.walkSpeed * dt, planarDist)
		enemy.part.Position = from + step
	end

	-- Attack if in range and off cooldown.
	if (root.Position - enemy.part.Position).Magnitude <= def.attackRange then
		local now = os.clock()
		if now - enemy.lastAttack >= def.attackCooldown then
			enemy.lastAttack = now
			local humanoid = target.Character:FindFirstChildOfClass("Humanoid")
			if humanoid and humanoid.Health > 0 then
				humanoid:TakeDamage(def.damage)
				HealthService.registerDamage(target) -- pause the player's regen
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
	enemy.part:Destroy()
	entry.enemy = nil

	for _, fn in ipairs(EnemyService.killedHandlers) do
		task.spawn(fn, lootSource, position, killer)
	end

	task.delay(respawn, function()
		spawnAt(entry)
	end)
end

-- Called by ToolService when a "weapon" item is activated (sword swing).
local function onWeaponSwing(player, tool, def)
	local character = player.Character
	local root = character and character:FindFirstChild("HumanoidRootPart")
	if not root then
		return
	end

	local hitEntry, hitEnemy, hitDist
	for _, entry in ipairs(spawns) do
		local enemy = entry.enemy
		if enemy and not enemy.dead then
			local dist = (enemy.part.Position - root.Position).Magnitude
			if dist <= MELEE_RANGE and (not hitDist or dist < hitDist) then
				hitEntry, hitEnemy, hitDist = entry, enemy, dist
			end
		end
	end

	if hitEnemy then
		hitEnemy.hp -= (def.damage or 10)
		updateHealthBar(hitEnemy)
		if hitEnemy.hp <= 0 then
			killEnemy(hitEntry, hitEnemy, player)
		end
	end
end

function EnemyService.start()
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
