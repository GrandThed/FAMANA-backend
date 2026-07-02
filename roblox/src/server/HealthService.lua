-- HP: restores saved health + position on spawn, out-of-combat regen, and
-- death -> respawn. Reads the profile from PlayerService.

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Config"))
local PlayerService = require(script.Parent.PlayerService)

local HealthService = {}

-- [userId] = os.clock() of last damage, for gating regen.
local lastDamage = {}

-- Called by the combat system (step 5) whenever a player takes damage.
function HealthService.registerDamage(player)
	lastDamage[player.UserId] = os.clock()
end

local function onCharacterAdded(player, character)
	local humanoid = character:WaitForChild("Humanoid")
	local profile = PlayerService.get(player)

	local maxHealth = (profile and profile.maxHealth) or Config.HP.max
	humanoid.MaxHealth = maxHealth

	-- Restore saved HP; a dead-saved value or missing value comes back full.
	local savedHealth = (profile and profile.health) or maxHealth
	if savedHealth <= 0 then
		savedHealth = maxHealth
	end
	humanoid.Health = math.clamp(savedHealth, 1, maxHealth)

	-- Restore saved position within this cell (skip the default origin).
	if profile and profile.position then
		local p = profile.position
		if not (p.x == 0 and p.y == 0 and p.z == 0) then
			local root = character:WaitForChild("HumanoidRootPart")
			root.CFrame = CFrame.new(p.x, p.y, p.z)
		end
	end

	humanoid.Died:Connect(function()
		if profile then
			profile.health = maxHealth -- respawn at full
		end
		task.wait(Config.HP.respawnDelay)
		if player.Parent then
			player:LoadCharacter()
		end
	end)
end

function HealthService.start()
	Players.PlayerAdded:Connect(function(player)
		player.CharacterAdded:Connect(function(character)
			onCharacterAdded(player, character)
		end)
		-- Handle a character that somehow already exists.
		if player.Character then
			onCharacterAdded(player, player.Character)
		end
	end)

	Players.PlayerRemoving:Connect(function(player)
		lastDamage[player.UserId] = nil
	end)

	-- Out-of-combat regen tick.
	local accumulator = 0
	RunService.Heartbeat:Connect(function(dt)
		accumulator += dt
		if accumulator < Config.HP.regenInterval then
			return
		end
		accumulator = 0

		for _, player in ipairs(Players:GetPlayers()) do
			local character = player.Character
			local humanoid = character and character:FindFirstChildOfClass("Humanoid")
			if humanoid and humanoid.Health > 0 and humanoid.Health < humanoid.MaxHealth then
				local last = lastDamage[player.UserId] or 0
				if os.clock() - last >= Config.HP.regenDelay then
					humanoid.Health = math.min(humanoid.MaxHealth, humanoid.Health + Config.HP.regenAmount)
				end
			end
		end
	end)
end

return HealthService
