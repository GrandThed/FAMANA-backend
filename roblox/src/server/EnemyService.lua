-- Slime enemies: spawn at fixed points, chase + melee the nearest player,
-- take damage from weapon swings, die, and respawn. On death, fires kill
-- handlers (the drop system in step 6 hooks in here). In-memory per server.

local Players = game:GetService("Players")
local Workspace = game:GetService("Workspace")
local RunService = game:GetService("RunService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local HealthService = require(script.Parent.HealthService)
local ToolService = require(script.Parent.ToolService)

local EnemyService = {}

-- Fixed slime spawn spots for this cell (X/Z; Y found by raycast).
local SLIME_SPOTS = {
	Vector3.new(-20, 0, 12),
	Vector3.new(-28, 0, 20),
	Vector3.new(-15, 0, 26),
}

local SLIME_HP = 30
local AGGRO_RANGE = 30
local ATTACK_RANGE = 6
local ATTACK_DAMAGE = 5
local ATTACK_COOLDOWN = 1.5
local WALK_SPEED = 8
local MELEE_RANGE = 9 -- how close a player must be for their sword to connect
local RESPAWN_TIME = 15

local spawns = {} -- { pos, slime = { part, fill, hp, lastAttack, dead } | nil }
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

local function updateHealthBar(slime)
	slime.fill.Size = UDim2.new(math.clamp(slime.hp / SLIME_HP, 0, 1), 0, 1, 0)
end

local function buildSlime(pos)
	local y = groundY(pos.X, pos.Z)

	local part = Instance.new("Part")
	part.Name = "Slime"
	part.Anchored = true
	part.Size = Vector3.new(3, 3, 3)
	part.Color = Color3.fromRGB(80, 200, 120)
	part.Material = Enum.Material.SmoothPlastic
	part.Position = Vector3.new(pos.X, y + 1.5, pos.Z)

	local billboard = Instance.new("BillboardGui")
	billboard.Name = "HealthBar"
	billboard.Size = UDim2.new(0, 60, 0, 8)
	billboard.StudsOffsetWorldSpace = Vector3.new(0, 2.6, 0)
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

	return { part = part, fill = fill, hp = SLIME_HP, lastAttack = 0, dead = false }
end

local function spawnAt(entry)
	entry.slime = buildSlime(entry.pos)
end

local function nearestPlayer(position)
	local closest, closestDist
	for _, player in ipairs(Players:GetPlayers()) do
		local character = player.Character
		local root = character and character:FindFirstChild("HumanoidRootPart")
		local humanoid = character and character:FindFirstChildOfClass("Humanoid")
		if root and humanoid and humanoid.Health > 0 then
			local dist = (root.Position - position).Magnitude
			if dist <= AGGRO_RANGE and (not closestDist or dist < closestDist) then
				closest, closestDist = player, dist
			end
		end
	end
	return closest, closestDist
end

local function updateSlime(slime, dt)
	if slime.dead then
		return
	end
	local target = nearestPlayer(slime.part.Position)
	if not target then
		return
	end
	local root = target.Character:FindFirstChild("HumanoidRootPart")
	if not root then
		return
	end

	-- Move toward the player along the ground plane (keep our own height).
	local from = slime.part.Position
	local flatTarget = Vector3.new(root.Position.X, from.Y, root.Position.Z)
	local toTarget = flatTarget - from
	local planarDist = toTarget.Magnitude
	if planarDist > ATTACK_RANGE then
		local step = toTarget.Unit * math.min(WALK_SPEED * dt, planarDist)
		slime.part.Position = from + step
	end

	-- Attack if in range and off cooldown.
	if (root.Position - slime.part.Position).Magnitude <= ATTACK_RANGE then
		local now = os.clock()
		if now - slime.lastAttack >= ATTACK_COOLDOWN then
			slime.lastAttack = now
			local humanoid = target.Character:FindFirstChildOfClass("Humanoid")
			if humanoid and humanoid.Health > 0 then
				humanoid:TakeDamage(ATTACK_DAMAGE)
				HealthService.registerDamage(target) -- pause the player's regen
			end
		end
	end
end

local function killSlime(entry, slime, killer)
	if slime.dead then
		return
	end
	slime.dead = true
	local position = slime.part.Position
	slime.part:Destroy()
	entry.slime = nil

	for _, fn in ipairs(EnemyService.killedHandlers) do
		task.spawn(fn, "slime", position, killer)
	end

	task.delay(RESPAWN_TIME, function()
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

	local hitEntry, hitSlime, hitDist
	for _, entry in ipairs(spawns) do
		local slime = entry.slime
		if slime and not slime.dead then
			local dist = (slime.part.Position - root.Position).Magnitude
			if dist <= MELEE_RANGE and (not hitDist or dist < hitDist) then
				hitEntry, hitSlime, hitDist = entry, slime, dist
			end
		end
	end

	if hitSlime then
		hitSlime.hp -= (def.damage or 10)
		updateHealthBar(hitSlime)
		if hitSlime.hp <= 0 then
			killSlime(hitEntry, hitSlime, player)
		end
	end
end

function EnemyService.start()
	enemyFolder = Instance.new("Folder")
	enemyFolder.Name = "Enemies"
	enemyFolder.Parent = Workspace

	for _, pos in ipairs(SLIME_SPOTS) do
		local entry = { pos = pos, slime = nil }
		table.insert(spawns, entry)
		spawnAt(entry)
	end

	ToolService.registerActivated("weapon", onWeaponSwing)

	RunService.Heartbeat:Connect(function(dt)
		for _, entry in ipairs(spawns) do
			if entry.slime then
				updateSlime(entry.slime, dt)
			end
		end
	end)
end

return EnemyService
