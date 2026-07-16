-- Tool-aware focus/targeting. While aiming (right mouse held), locks onto the
-- best object for whatever is equipped — sword→enemies, axe→trees,
-- pickaxe→rocks — within that tool's reach (a per-item stat). The lock is
-- sticky: once acquired it persists through releasing RMB and attacking, and
-- only clears when the target dies/depletes, leaves reach, or the equipped tool
-- changes. The focus gets a highlight and a top-screen target panel (with an HP
-- bar for enemies). Enemy HP is read from the replicated health-bar fill, so no
-- extra networking. Ranged weapons (bow/staff) also draw a ground ring while
-- aiming, showing their actual hit range.

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")
local UserInputService = game:GetService("UserInputService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Items = require(Shared:WaitForChild("Items"))
local Config = require(Shared:WaitForChild("Config"))
local Remotes = require(Shared:WaitForChild("Remotes"))
local ClientState = require(script.Parent.ClientState)
local Theme = require(script.Parent.Theme)
local UIKit = require(script.Parent.UIKit)

local player = Players.LocalPlayer

-- How much looser the lock-on/cycling radius is versus the weapon's actual
-- strike reach (see equippedFocus below). 2.5x turns a 10-stud sword reach
-- into a 25-stud tracking radius — enough to hold/pick a target you're
-- closing in on without it being unusable for judging whether a swing lands.
local LOCK_REACH_MULTIPLIER = 2.5

-- Ranged weapons (bow/staff) don't need that "closing the gap" margin — the
-- player is already aiming from max range, not walking into melee. Reusing
-- the melee multiplier here blew their lock-on radius way past their actual
-- hit range (e.g. a 60-stud staff could lock a target 150 studs out). This
-- keeps just enough slack that the lock doesn't drop from a tiny wobble
-- right at the edge of range.
local RANGED_LOCK_REACH_MULTIPLIER = 1.15

local TargetingController = {}

-- What the equipped item focuses, and where those objects live.
local function equippedFocus(character)
	local tool = character and character:FindFirstChildOfClass("Tool")
	if not tool then
		return nil
	end
	local def = Items.get(tool:GetAttribute("itemId"))
	if not def then
		return nil
	end
	-- Reach comes straight from the item's own `reach` stat (single source of
	-- truth, shared with the server); Config.defaultReach is just a safety net.
	local reach = def.reach or Config.defaultReach
	-- `reach` alone is the actual strike distance (short, e.g. 8-10 studs for
	-- melee) — too tight to use for targeting too, or a mob that falls a bit
	-- behind while you're fighting a cluster becomes both un-cyclable (never
	-- makes the eligible list) and un-stick-able (lockStale drops it the
	-- instant it's a hair past strike range). `lockReach` is the looser
	-- radius used everywhere lock-on decides what counts as "in range" —
	-- letting you pre-lock or hold a target further out and close the gap,
	-- while actual damage still checks the real `reach` server-side.
	local ranged = def.weaponType == "ranged"
	local multiplier = ranged and RANGED_LOCK_REACH_MULTIPLIER or LOCK_REACH_MULTIPLIER
	local lockReach = reach * multiplier
	if def.type == "weapon" then
		return { category = "enemy", reach = reach, lockReach = lockReach, ranged = ranged }
	elseif def.type == "tool" and def.toolType then
		return { category = def.toolType, reach = reach, lockReach = lockReach, ranged = false }
	end
	return nil
end

-- Candidate targets for a category: { adornee, anchor (BasePart), name, hasHp }.
local function candidates(category)
	local out = {}
	if category == "enemy" then
		local folder = Workspace:FindFirstChild("Enemies")
		if folder then
			for _, e in ipairs(folder:GetChildren()) do
				-- Only real enemies (they carry a HealthBar billboard) — never
				-- cosmetics like projectiles that pass through the folder.
				if e:IsA("BasePart") and e:FindFirstChild("HealthBar") then
					table.insert(out, { adornee = e, anchor = e, name = e.Name, hasHp = true })
				end
			end
		end
	elseif category == "axe" or category == "pickaxe" then
		-- Gathering nodes: GatheringService stamps every node model with
		-- NodeTool/NodeName attributes at spawn (mesh pools and ArtKit
		-- fallbacks alike), so new node types show up here with zero client
		-- changes — matching model names broke the moment nodes went mesh.
		local folder = Workspace:FindFirstChild("Resources")
		if folder then
			for _, m in ipairs(folder:GetChildren()) do
				if m:IsA("Model") and m:GetAttribute("NodeTool") == category then
					local anchor = m.PrimaryPart
					if anchor and not anchor:GetAttribute("Depleted") then
						table.insert(out, { adornee = m, anchor = anchor, name = m:GetAttribute("NodeName") or m.Name, hasHp = false })
					end
				end
			end
		end
	end
	return out
end

local function hpFraction(enemyPart)
	local billboard = enemyPart:FindFirstChild("HealthBar")
	local fill = billboard and billboard:FindFirstChild("Fill", true)
	return fill and math.clamp(fill.Size.X.Scale, 0, 1) or nil
end

function TargetingController.start()
	-- ---- target panel (top-center) ----
	local gui = Instance.new("ScreenGui")
	gui.Name = "TargetUI"
	gui.ResetOnSpawn = false
	gui.IgnoreGuiInset = true
	gui.Enabled = false
	gui.Parent = player:WaitForChild("PlayerGui")

	local panel = Instance.new("Frame")
	panel.Size = UDim2.new(0, 320, 0, 50)
	panel.Position = UDim2.new(0.5, 0, 0, 14)
	panel.AnchorPoint = Vector2.new(0.5, 0)
	panel.Parent = gui
	UIKit.stylePanel(panel) -- Aethelgard shell: Ink gradient, Stone border, ember forge-light
	UIKit.autoScale(panel)

	local nameLabel = UIKit.label(panel, "", Theme.Text.Lg, Theme.Semantic.TextHero, Theme.Font.DisplayBold)
	nameLabel.Size = UDim2.new(1, -20, 0, 20)
	nameLabel.Position = UDim2.new(0, 10, 0, 5)
	nameLabel.TextXAlignment = Enum.TextXAlignment.Left
	nameLabel.ZIndex = panel.ZIndex + 1

	local barBg = Instance.new("Frame")
	barBg.Size = UDim2.new(1, -20, 0, 14)
	barBg.Position = UDim2.new(0, 10, 0, 28)
	barBg.BackgroundColor3 = Theme.Color.Ink900
	barBg.BorderSizePixel = 0
	barBg.ClipsDescendants = true
	barBg.ZIndex = panel.ZIndex + 1
	barBg.Parent = panel

	local barBorder = Instance.new("UIStroke")
	barBorder.Thickness = 1
	barBorder.Color = Theme.Semantic.BorderPanel
	barBorder.Parent = barBg

	-- Ghost afterimage, same trick as the enemy overhead bar: lags behind on
	-- damage and eases down a beat later so hits read as "chipping" the bar.
	local barGhost = Instance.new("Frame")
	barGhost.Name = "Ghost"
	barGhost.Size = UDim2.new(1, 0, 1, 0)
	barGhost.BackgroundColor3 = Theme.Color.Gold300
	barGhost.BorderSizePixel = 0
	barGhost.ZIndex = barBg.ZIndex + 1
	barGhost.Parent = barBg

	local barFill = Instance.new("Frame")
	barFill.Size = UDim2.new(1, 0, 1, 0)
	barFill.BackgroundColor3 = Theme.Orb.HpTop
	barFill.BorderSizePixel = 0
	barFill.ZIndex = barGhost.ZIndex + 1
	barFill.Parent = barBg

	local barGradient = Instance.new("UIGradient")
	barGradient.Rotation = 90
	barGradient.Color = ColorSequence.new(Theme.Orb.HpTop, Theme.Orb.HpBottom)
	barGradient.Parent = barFill

	local FILL_TWEEN = TweenInfo.new(0.15, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
	local GHOST_TWEEN = TweenInfo.new(0.35, Enum.EasingStyle.Quad, Enum.EasingDirection.In)
	local GHOST_DELAY = 0.25
	local ghostToken = 0
	local lastFrac = 1

	-- Applies a new HP fraction with the tween + delayed-ghost treatment.
	-- Kept local to setupPanel-scope so both the initial acquire and the
	-- per-frame poll below share one code path. No-ops if the fraction
	-- hasn't actually moved — this is polled every RenderStepped, so a fresh
	-- tween per frame would be both wasteful and visually mushy.
	local function setBarFraction(frac)
		if math.abs(frac - lastFrac) < 0.001 then
			return
		end
		lastFrac = frac
		TweenService:Create(barFill, FILL_TWEEN, { Size = UDim2.new(frac, 0, 1, 0) }):Play()
		ghostToken += 1
		local token = ghostToken
		task.delay(GHOST_DELAY, function()
			if ghostToken ~= token then
				return
			end
			TweenService:Create(barGhost, GHOST_TWEEN, { Size = UDim2.new(frac, 0, 1, 0) }):Play()
		end)
	end

	-- ---- highlight ----
	local highlight = Instance.new("Highlight")
	highlight.FillTransparency = 0.7
	highlight.FillColor = Color3.fromRGB(255, 230, 120)
	highlight.OutlineColor = Color3.fromRGB(255, 230, 120)
	highlight.OutlineTransparency = 0

	local setTargetRemote = Remotes.get("SetTarget")
	-- The current locked focus. It sticks until the target dies/depletes, leaves
	-- reach, or the equipped tool no longer matches — NOT when the player stops
	-- aiming or clicks to attack.
	local lock = nil -- { adornee, anchor, hasHp, category } or nil

	local reticleGui = nil
	local reticleLabel = nil

	-- ---- ranged weapon range ring ----
	-- A flat circle on the ground, radius = the equipped ranged weapon's real
	-- `reach`, shown while aiming so it's obvious at a glance whether a target
	-- is actually hittable — instead of finding out only when the shot whiffs.
	-- Built from Beams strung between Attachments on one invisible anchor part
	-- (no image asset required, so it doesn't depend on anything being
	-- uploaded to work).
	local RING_SEGMENTS = 48
	local RING_GROUND_OFFSET = 0.12 -- studs above the floor; avoids z-fighting
	local RING_WIDTH = 0.3
	local RING_COLOR = Theme.Color.Ember300 or Color3.fromRGB(255, 220, 100)

	local ringAnchor = nil
	local ringRadius = nil
	local ringRayParams = RaycastParams.new()
	ringRayParams.FilterType = Enum.RaycastFilterType.Exclude

	local function destroyRing()
		if ringAnchor then
			ringAnchor:Destroy()
			ringAnchor = nil
		end
		ringRadius = nil
	end

	local function buildRing(radius)
		destroyRing()
		ringRadius = radius

		local anchor = Instance.new("Part")
		anchor.Name = "RangeRingAnchor"
		anchor.Anchored = true
		anchor.CanCollide = false
		anchor.CanQuery = false
		anchor.CanTouch = false
		anchor.Transparency = 1
		anchor.Size = Vector3.new(0.1, 0.1, 0.1)
		anchor.CFrame = CFrame.new(0, -1000, 0) -- parked until the first update positions it
		anchor.Parent = Workspace

		local points = {}
		for i = 1, RING_SEGMENTS do
			local angle = (i - 1) / RING_SEGMENTS * math.pi * 2
			local attachment = Instance.new("Attachment")
			attachment.Position = Vector3.new(math.cos(angle) * radius, 0, math.sin(angle) * radius)
			attachment.Parent = anchor
			points[i] = attachment
		end
		for i = 1, RING_SEGMENTS do
			local a = points[i]
			local b = points[(i % RING_SEGMENTS) + 1]
			local beam = Instance.new("Beam")
			beam.Attachment0 = a
			beam.Attachment1 = b
			beam.Width0 = RING_WIDTH
			beam.Width1 = RING_WIDTH
			beam.Color = ColorSequence.new(RING_COLOR)
			beam.Transparency = NumberSequence.new(0.35)
			beam.FaceCamera = false
			beam.LightEmission = 0.6
			beam.Segments = 1
			beam.Parent = anchor
		end

		ringAnchor = anchor
	end

	-- Re-anchors and (if the radius changed, e.g. switched bow→staff) rebuilds
	-- the ring under the player each frame while aiming with a ranged weapon.
	local function updateRing(reach, root)
		if ringRadius ~= reach then
			buildRing(reach)
		end
		-- Ground-snap via raycast so it hugs slopes/stairs instead of floating
		-- at a fixed height under the character.
		ringRayParams.FilterDescendantsInstances = { player.Character }
		local origin = root.Position
		local rayResult = Workspace:Raycast(origin, Vector3.new(0, -20, 0), ringRayParams)
		local groundY = rayResult and rayResult.Position.Y or (origin.Y - 3)
		ringAnchor.CFrame = CFrame.new(origin.X, groundY + RING_GROUND_OFFSET, origin.Z)
	end

	local function hideRing()
		if ringAnchor then
			destroyRing()
		end
	end

	local function createReticle(anchor)
		if reticleGui then
			reticleGui:Destroy()
			reticleGui = nil
		end

		reticleGui = Instance.new("BillboardGui")
		reticleGui.Name = "LockOnReticle"
		reticleGui.Size = UDim2.new(0, 40, 0, 40)
		reticleGui.AlwaysOnTop = true
		reticleGui.Parent = anchor

		reticleLabel = Instance.new("TextLabel")
		reticleLabel.Size = UDim2.new(2, 0, 2, 0) -- start larger for the "lock-on" snap effect
		reticleLabel.Position = UDim2.new(-0.5, 0, -0.5, 0)
		reticleLabel.BackgroundTransparency = 1
		reticleLabel.Font = Enum.Font.GothamBlack
		reticleLabel.TextSize = 28
		reticleLabel.TextColor3 = Theme.Color.Ember300 or Color3.fromRGB(255, 220, 100)
		reticleLabel.TextStrokeTransparency = 0.4
		reticleLabel.TextStrokeColor3 = Color3.fromRGB(20, 20, 20)
		reticleLabel.Text = "⌖"
		reticleLabel.TextTransparency = 1
		reticleLabel.Parent = reticleGui

		-- 1. Pulse-in animation (from 2x size to 1x size, and fade in)
		TweenService:Create(reticleLabel, TweenInfo.new(0.2, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
			Size = UDim2.new(1, 0, 1, 0),
			Position = UDim2.new(0, 0, 0, 0),
			TextTransparency = 0
		}):Play()

		-- 2. Continuous rotation animation
		local spin = TweenService:Create(
			reticleLabel,
			TweenInfo.new(4, Enum.EasingStyle.Linear, Enum.EasingDirection.Out, -1),
			{ Rotation = 360 }
		)
		spin:Play()
	end

	local function clear()
		if lock then
			lock = nil
			highlight.Adornee = nil
			highlight.Parent = nil
			gui.Enabled = false
			if reticleGui then
				reticleGui:Destroy()
				reticleGui = nil
			end
			setTargetRemote:FireServer(nil) -- tell the server we have no focus
		end
	end

	local function setTarget(cand, category)
		if lock and cand.adornee == lock.adornee then
			return
		end
		lock = { adornee = cand.adornee, anchor = cand.anchor, hasHp = cand.hasHp, category = category }
		highlight.Adornee = cand.adornee
		highlight.Parent = cand.adornee
		nameLabel.Text = cand.name
		barBg.Visible = cand.hasHp
		gui.Enabled = true

		createReticle(cand.anchor)

		if cand.hasHp then
			-- Snap instantly to the new target's HP — a fresh target's bar
			-- must never visibly tween in from the previous target's value.
			ghostToken += 1
			local frac = hpFraction(cand.anchor) or 1
			lastFrac = frac
			barFill.Size = UDim2.new(frac, 0, 1, 0)
			barGhost.Size = UDim2.new(frac, 0, 1, 0)
		end
		-- Send the anchor part so the server can match + validate it.
		setTargetRemote:FireServer(cand.anchor)
	end

	local function cycleTarget(direction)
		local character = player.Character
		local root = character and character:FindFirstChild("HumanoidRootPart")
		local camera = Workspace.CurrentCamera
		if not (character and root and camera) then
			return
		end

		local focus = equippedFocus(character)
		if not focus then
			return
		end

		local cands = candidates(focus.category)
		local eligible = {}
		for _, cand in ipairs(cands) do
			if (cand.anchor.Position - root.Position).Magnitude <= focus.lockReach then
				table.insert(eligible, cand)
			end
		end

		if #eligible == 0 then
			return
		end

		table.sort(eligible, function(a, b)
			local spA = camera:WorldToViewportPoint(a.anchor.Position)
			local spB = camera:WorldToViewportPoint(b.anchor.Position)
			return spA.X < spB.X
		end)

		local currentIndex = nil
		if lock then
			for i, cand in ipairs(eligible) do
				if cand.adornee == lock.adornee then
					currentIndex = i
					break
				end
			end
		end

		local nextIndex
		if currentIndex then
			nextIndex = currentIndex + direction
			if nextIndex > #eligible then
				nextIndex = 1
			elseif nextIndex < 1 then
				nextIndex = #eligible
			end
		else
			local vp = camera.ViewportSize
			local center = Vector2.new(vp.X / 2, vp.Y / 2)
			local best, bestScore
			for i, cand in ipairs(eligible) do
				local sp, onScreen = camera:WorldToViewportPoint(cand.anchor.Position)
				if onScreen and sp.Z > 0 then
					local frac = (Vector2.new(sp.X, sp.Y) - center).Magnitude / vp.Y
					if not bestScore or frac < bestScore then
						best, bestScore = i, frac
					end
				end
			end
			nextIndex = best or 1
		end

		local nextCand = eligible[nextIndex]
		if nextCand then
			setTarget(nextCand, focus.category)
		end
	end

	-- True once the lock's target is dead/depleted, out of reach, or no longer
	-- matches what the equipped tool can focus.
	local function lockStale(focus, root)
		local anchor = lock.anchor
		return focus.category ~= lock.category
			or not anchor
			or not anchor.Parent
			or anchor:GetAttribute("Depleted")
			or (anchor.Position - root.Position).Magnitude > focus.lockReach
	end

	-- Freeze Roblox's default camera zoom while aiming or holding a lock, so
	-- scrolling to cycle targets (see the mouse-wheel bind below) doesn't
	-- also zoom the camera in/out. The built-in camera script reads
	-- CameraMinZoomDistance/CameraMaxZoomDistance every frame, so pinning
	-- both to the player's current distance stops it reacting to the wheel;
	-- restoring the original bounds on release hands zoom back to normal.
	local originalMinZoom, originalMaxZoom
	local zoomFrozen = false

	local function setZoomFrozen(frozen)
		if frozen == zoomFrozen then
			return
		end
		zoomFrozen = frozen
		if frozen then
			originalMinZoom = player.CameraMinZoomDistance
			originalMaxZoom = player.CameraMaxZoomDistance
			local camera = Workspace.CurrentCamera
			-- The default camera measures zoom to its Focus (the subject point
			-- it maintains at head height), NOT to the root — measuring to the
			-- root pins the bounds slightly past the real zoom, so every RMB
			-- press made the camera pop out to the too-far pinned distance.
			local currentDistance = originalMinZoom
			if camera then
				currentDistance = math.clamp(
					(camera.CFrame.Position - camera.Focus.Position).Magnitude,
					originalMinZoom,
					originalMaxZoom
				)
			end
			player.CameraMinZoomDistance = currentDistance
			player.CameraMaxZoomDistance = currentDistance
		elseif originalMinZoom and originalMaxZoom then
			player.CameraMinZoomDistance = originalMinZoom
			player.CameraMaxZoomDistance = originalMaxZoom
		end
	end

	RunService.RenderStepped:Connect(function()
		local character = player.Character
		local root = character and character:FindFirstChild("HumanoidRootPart")
		local camera = Workspace.CurrentCamera

		setZoomFrozen(ClientState.aiming or lock ~= nil)

		local focus = (root and camera) and equippedFocus(character) or nil
		if not focus then
			clear() -- dead, no camera, or nothing that can focus is equipped
			hideRing()
			return
		end

		-- Range ring: only while actively aiming a ranged weapon (bow/staff).
		-- Melee doesn't get one — its reach is short enough to judge by eye,
		-- and a ring hugging the character at 10-25 studs would just be clutter.
		if ClientState.aiming and not ClientState.inventoryOpen and focus.ranged then
			updateRing(focus.reach, root)
		else
			hideRing()
		end

		-- Drop the existing lock only if it has become invalid.
		if lock and lockStale(focus, root) then
			clear()
		end

		-- While aiming with nothing locked yet, acquire the best on-screen
		-- target in reach. Gated on `not lock` — once something IS locked,
		-- this must stay hands-off (the lock is sticky per the header
		-- comment) and only cycleTarget (Tab/scroll) or lockStale above
		-- should change it. Without this gate, this block re-runs every
		-- single RenderStepped frame while aiming and re-snaps to whatever's
		-- nearest the crosshair, undoing a cycleTarget switch one frame
		-- after it happens — which is why Tab/scroll looked like they did
		-- nothing.
		if ClientState.aiming and not ClientState.inventoryOpen and not lock then
			local vp = camera.ViewportSize
			local center = Vector2.new(vp.X / 2, vp.Y / 2)

			local best, bestScore
			for _, cand in ipairs(candidates(focus.category)) do
				if (cand.anchor.Position - root.Position).Magnitude <= focus.lockReach then
					local sp, onScreen = camera:WorldToViewportPoint(cand.anchor.Position)
					if onScreen and sp.Z > 0 then
						local frac = (Vector2.new(sp.X, sp.Y) - center).Magnitude / vp.Y
						if not bestScore or frac < bestScore then
							best, bestScore = cand, frac
						end
					end
				end
			end

			if best then
				setTarget(best, focus.category)
			end
		end

		-- Keep the HP bar current for whatever is locked.
		if lock and lock.hasHp then
			local frac = hpFraction(lock.anchor)
			if frac then
				setBarFraction(frac)
			end
		end
	end)

	-- Key binds for Tab cycling
	UserInputService.InputBegan:Connect(function(input, gameProcessed)
		if gameProcessed then
			return
		end
		-- Only allow cycling if we have a focusable tool equipped
		local character = player.Character
		if not character or not equippedFocus(character) then
			return
		end

		if input.KeyCode == Enum.KeyCode.Tab then
			cycleTarget(1) -- Tab cycles forward
		end
	end)

	-- Mouse wheel for cycling (only when aiming or locked)
	UserInputService.InputChanged:Connect(function(input, gameProcessed)
		if gameProcessed then
			return
		end
		if input.UserInputType ~= Enum.UserInputType.MouseWheel then
			return
		end
		-- Only cycle if we have a focusable tool equipped and are aiming or locked
		if not (ClientState.aiming or lock) then
			return
		end
		local character = player.Character
		if not character or not equippedFocus(character) then
			return
		end

		if input.Position.Z > 0 then
			cycleTarget(1) -- Scroll Up -> next target (right)
		elseif input.Position.Z < 0 then
			cycleTarget(-1) -- Scroll Down -> previous target (left)
		end
	end)
end

return TargetingController