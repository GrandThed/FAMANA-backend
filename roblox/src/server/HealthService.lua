-- HP: restores saved health + position on spawn, out-of-combat regen, and
-- death -> respawn. Reads the profile from PlayerService.
--
-- Downed state: a hit that would be lethal instead drops the player to 1 HP
-- and "downs" them (HealthService.damagePlayer is the one choke point for
-- all player-facing damage — EnemyService calls it instead of
-- humanoid:TakeDamage directly, so this can intercept). Downed players:
--   * can't move past a crawl, can't jump, take no further damage, and
--     can't cast/attack (SpellService/EnemyService check isDowned());
--   * have `Config.HP.downedBleedTime` seconds before it becomes a real
--     death — unless ANY nearby player holds the ProximityPrompt on them
--     (no party requirement), which pauses the bleed timer for as long as
--     they hold it (PromptButtonHoldBegan/Ended) and, once the hold
--     completes (Triggered), revives them at
--     `Config.HP.downedReviveHealPercent` of max HP;
--   * are only *visible* as downed (the floating billboard) within
--     `Config.HP.downedVisibleRange` studs — BillboardGui.MaxDistance does
--     this natively, no per-player client filtering needed. The revive
--     prompt itself is already shorter-range than that (its
--     MaxActivationDistance), so nothing extra is needed there.
-- The `Downed` / `DownedBleedRemaining` Player attributes are how the
-- client's HUD overlay (HudUI) reads this with no remote.

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Config"))
local Classes = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Classes"))
local PlayerService = require(script.Parent.PlayerService)

local HealthService = {}

-- [userId] = os.clock() of last damage, for gating regen.
local lastDamage = {}

-- [userId] = { bleedRemaining, beingRevived, prompt, billboard, saved
-- WalkSpeed/JumpPower/JumpHeight, and the connections tied to that prompt }.
local downed = {}

function HealthService.isDowned(player)
	return downed[player.UserId] ~= nil
end

-- Public entrypoint for spells (Renacimiento): instantly revives a downed
-- player, skipping their bleed timer, at `healPercent` of max HP. No-ops if
-- they're not actually downed (SpellService should already be targeting a
-- downed ally, but this stays safe regardless of caller).
function HealthService.reviveDowned(player, healPercent)
	if not downed[player.UserId] then
		return false
	end
	exitDowned(player, true, healPercent)
	return true
end

local enterDowned, exitDowned -- forward declarations (mutually referenced)

function enterDowned(player, humanoid)
	local character = player.Character
	local root = character and character:FindFirstChild("HumanoidRootPart")
	if not root or downed[player.UserId] then
		return
	end

	local state = {
		bleedRemaining = Config.HP.downedBleedTime,
		beingRevived = false,
		savedWalkSpeed = humanoid.WalkSpeed,
		savedJumpPower = humanoid.JumpPower,
		savedJumpHeight = humanoid.JumpHeight,
	}
	downed[player.UserId] = state

	humanoid.WalkSpeed = Config.HP.downedWalkSpeed
	humanoid.JumpPower = 0
	humanoid.JumpHeight = 0
	-- Watchdog: nothing else should touch WalkSpeed while downed, but if it
	-- does (a stray effect refresh, say), clamp it back to a crawl.
	state.watchdog = humanoid:GetPropertyChangedSignal("WalkSpeed"):Connect(function()
		if downed[player.UserId] == state and humanoid.WalkSpeed ~= Config.HP.downedWalkSpeed then
			humanoid.WalkSpeed = Config.HP.downedWalkSpeed
		end
	end)
	-- Belt-and-suspenders: every Health-raising code path already checks
	-- isDowned() before touching a downed player, but this watchdog makes
	-- it unconditional — if Health ever ticks above 1 while downed, for
	-- ANY reason, it's slapped back down the same frame. Health *can* still
	-- go to 0 here (a stray hit landing before some other system's guard
	-- catches up); that's fine, it just reads as the bleed timer's own
	-- exitDowned(false) a moment early.
	state.healthWatchdog = humanoid.HealthChanged:Connect(function()
		if downed[player.UserId] == state and humanoid.Health > 1 then
			humanoid.Health = 1
		end
	end)

	player:SetAttribute("Downed", true)
	player:SetAttribute("DownedBleedRemaining", state.bleedRemaining)

	-- Billboard so allies can spot + read the countdown from a distance.
	local billboard = Instance.new("BillboardGui")
	billboard.Name = "DownedBillboard"
	billboard.Size = UDim2.new(0, 180, 0, 44)
	billboard.StudsOffset = Vector3.new(0, 3.2, 0)
	billboard.AlwaysOnTop = true
	billboard.MaxDistance = Config.HP.downedVisibleRange -- only shows up close
	billboard.Parent = root
	local label = Instance.new("TextLabel")
	label.BackgroundTransparency = 1
	label.Size = UDim2.new(1, 0, 1, 0)
	label.Font = Enum.Font.GothamBold
	label.TextScaled = true
	label.TextColor3 = Color3.fromRGB(255, 90, 90)
	label.TextStrokeTransparency = 0.3
	label.Text = ("⚠ %s caído"):format(player.Name)
	label.Parent = billboard
	state.billboard = billboard

	-- Revive prompt: holding it pauses the bleed timer; only a *completed*
	-- hold (Triggered) actually revives — letting go resumes the bleed from
	-- wherever it was paused, per spec.
	local prompt = Instance.new("ProximityPrompt")
	prompt.Name = "RevivePrompt"
	prompt.ActionText = "Reanimar"
	prompt.ObjectText = player.Name
	prompt.HoldDuration = Config.HP.downedReviveTime
	prompt.MaxActivationDistance = 8
	prompt.RequiresLineOfSight = false
	prompt.Parent = root
	state.prompt = prompt

	state.holdBegan = prompt.PromptButtonHoldBegan:Connect(function(reviver)
		if reviver ~= player then
			state.beingRevived = true
		end
	end)
	state.holdEnded = prompt.PromptButtonHoldEnded:Connect(function(reviver)
		if reviver ~= player then
			state.beingRevived = false
		end
	end)
	state.triggered = prompt.Triggered:Connect(function(reviver)
		if reviver ~= player then
			exitDowned(player, true)
		end
	end)
end

-- revived == true: skips the bleed timer entirely — either an ally
-- completed the ProximityPrompt hold (healPercentOverride nil, uses
-- Config.HP.downedReviveHealPercent) or a spell like Renacimiento revived
-- them directly (passes its own scaled percent).
-- revived == false: the bleed timer hit zero — this is a real death now.
function exitDowned(player, revived, healPercentOverride)
	local state = downed[player.UserId]
	if not state then
		return
	end
	downed[player.UserId] = nil

	for _, conn in ipairs({ state.watchdog, state.healthWatchdog, state.holdBegan, state.holdEnded, state.triggered }) do
		if conn then
			conn:Disconnect()
		end
	end
	if state.prompt then
		state.prompt:Destroy()
	end
	if state.billboard then
		state.billboard:Destroy()
	end

	player:SetAttribute("Downed", false)
	player:SetAttribute("DownedBleedRemaining", nil)

	local character = player.Character
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	if not humanoid then
		return
	end

	if revived then
		humanoid.WalkSpeed = state.savedWalkSpeed
		humanoid.JumpPower = state.savedJumpPower
		humanoid.JumpHeight = state.savedJumpHeight
		local healPercent = healPercentOverride or Config.HP.downedReviveHealPercent
		humanoid.Health = math.max(1, math.floor(humanoid.MaxHealth * healPercent + 0.5))
	else
		humanoid.Health = 0 -- fires Humanoid.Died -> the normal respawn flow
	end
end

-- Central damage entrypoint for anything hitting a player (currently only
-- EnemyService's melee attacks). A hit that would drop Health to 0 or below
-- downs instead of killing; downed players take no further damage.
function HealthService.damagePlayer(player, amount)
	local character = player.Character
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	if not humanoid or humanoid.Health <= 0 then
		return
	end
	if downed[player.UserId] then
		return
	end
	if amount >= humanoid.Health then
		humanoid.Health = 1
		enterDowned(player, humanoid)
	else
		humanoid:TakeDamage(amount)
	end
end

-- Called by the combat system (step 5) whenever a player takes damage.
function HealthService.registerDamage(player)
	lastDamage[player.UserId] = os.clock()
end

-- Heals `player` by `amount`, clamped to their current MaxHealth. Used by
-- Cleric spells (SpellService's "heal"/"line" behaviors) — this is the only
-- writer of positive Health deltas outside natural regen, so it's the one
-- place to add e.g. an "overheal" or heal-received hook later if needed.
function HealthService.heal(player, amount)
	local humanoid = player.Character and player.Character:FindFirstChildOfClass("Humanoid")
	if not humanoid or humanoid.Health <= 0 or downed[player.UserId] then
		return
	end
	humanoid.Health = math.min(humanoid.MaxHealth, humanoid.Health + amount)
end

-- registerMaxHealthMult: fn(player) -> multiplier on max HP (Brawler trait).
local maxHealthMultHooks = {}
function HealthService.registerMaxHealthMult(fn)
	table.insert(maxHealthMultHooks, fn)
end

-- registerBonusRegen: fn(player) -> extra HP per SECOND, applied even in
-- combat (unlike the base out-of-combat regen) — the Brawler trickle.
local bonusRegenHooks = {}
function HealthService.registerBonusRegen(fn)
	table.insert(bonusRegenHooks, fn)
end

local function hookedMaxHealthMult(player)
	local mult = 1
	for _, fn in ipairs(maxHealthMultHooks) do
		local ok, value = pcall(fn, player)
		if ok and typeof(value) == "number" then
			mult *= value
		end
	end
	return mult
end

local function hookedBonusRegen(player)
	local rate = 0
	for _, fn in ipairs(bonusRegenHooks) do
		local ok, value = pcall(fn, player)
		if ok and typeof(value) == "number" then
			rate += value
		end
	end
	return rate
end

local function maxHealthFor(player)
	local profile = PlayerService.get(player)
	-- Base max HP scaled by the player's current class AND level (see
	-- shared/Classes.lua statsAtLevel), plus any registered multipliers
	-- (Brawler trait).
	local classDef = Classes.get(profile and profile.currentClass)
	local level = (profile and profile.level) or 1
	local stats = Classes.statsAtLevel(classDef, level)
	return math.floor(stats.hp * hookedMaxHealthMult(player) + 0.5)
end

-- Re-derives MaxHealth mid-life (equipment/trait changes). Current HP stays
-- absolute — more max is headroom, less max clamps.
function HealthService.refreshMaxHealth(player)
	local character = player.Character
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	if not humanoid or humanoid.Health <= 0 then
		return
	end
	local maxHealth = maxHealthFor(player)
	if humanoid.MaxHealth ~= maxHealth then
		humanoid.MaxHealth = maxHealth
		humanoid.Health = math.min(humanoid.Health, maxHealth)
	end
end

local function onCharacterAdded(player, character)
	local humanoid = character:WaitForChild("Humanoid")
	local profile = PlayerService.get(player)

	-- Defensive: a fresh character should never start downed.
	downed[player.UserId] = nil
	player:SetAttribute("Downed", false)
	player:SetAttribute("DownedBleedRemaining", nil)

	local maxHealth = maxHealthFor(player)
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
			profile.health = humanoid.MaxHealth -- respawn at full (current max)
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
		local state = downed[player.UserId]
		if state then
			downed[player.UserId] = nil
			for _, conn in ipairs({ state.watchdog, state.healthWatchdog, state.holdBegan, state.holdEnded, state.triggered }) do
				if conn then
					conn:Disconnect()
				end
			end
			-- No need to destroy the prompt/billboard: they're parented
			-- under the character, which is torn down with the player.
		end
	end)

	-- Out-of-combat regen tick.
	local accumulator = 0
	RunService.Heartbeat:Connect(function(dt)
		-- Downed bleed-out: ticks every frame (not gated by the regen
		-- accumulator below) so the countdown is smooth and pauses exactly
		-- while an ally is holding the revive prompt.
		for userId, state in pairs(downed) do
			if not state.beingRevived then
				state.bleedRemaining -= dt
				local player = Players:GetPlayerByUserId(userId)
				if player then
					player:SetAttribute("DownedBleedRemaining", math.max(0, state.bleedRemaining))
					if state.bleedRemaining <= 0 then
						exitDowned(player, false)
					end
				end
			end
		end

		accumulator += dt
		if accumulator < Config.HP.regenInterval then
			return
		end
		accumulator = 0

		for _, player in ipairs(Players:GetPlayers()) do
			local character = player.Character
			local humanoid = character and character:FindFirstChildOfClass("Humanoid")
			if humanoid and humanoid.Health > 0 and humanoid.Health < humanoid.MaxHealth and not downed[player.UserId] then
				-- Trait regen (Brawler) trickles even in combat; the base
				-- regen still waits for the out-of-combat delay.
				local heal = hookedBonusRegen(player) * Config.HP.regenInterval
				local last = lastDamage[player.UserId] or 0
				if os.clock() - last >= Config.HP.regenDelay then
					heal += Config.HP.regenAmount
				end
				if heal > 0 then
					humanoid.Health = math.min(humanoid.MaxHealth, humanoid.Health + heal)
				end
			end
		end
	end)
end

return HealthService
