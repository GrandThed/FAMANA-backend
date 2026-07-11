-- Tool-aware focus/targeting. While aiming (right mouse held), locks onto the
-- best object for whatever is equipped — sword→enemies, axe→trees,
-- pickaxe→rocks — within that tool's reach (a per-item stat). The lock is
-- sticky: once acquired it persists through releasing RMB and attacking, and
-- only clears when the target dies/depletes, leaves reach, or the equipped tool
-- changes. The focus gets a highlight and a top-screen target panel (with an HP
-- bar for enemies). Enemy HP is read from the replicated health-bar fill, so no
-- extra networking.

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Items = require(Shared:WaitForChild("Items"))
local Config = require(Shared:WaitForChild("Config"))
local Remotes = require(Shared:WaitForChild("Remotes"))
local ClientState = require(script.Parent.ClientState)
local Theme = require(script.Parent.Theme)
local UIKit = require(script.Parent.UIKit)

local player = Players.LocalPlayer

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
	if def.type == "weapon" then
		return { category = "enemy", reach = reach }
	elseif def.type == "tool" and def.toolType then
		return { category = def.toolType, reach = reach }
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
	elseif category == "axe" then
		local folder = Workspace:FindFirstChild("Resources")
		if folder then
			for _, m in ipairs(folder:GetChildren()) do
				if m:IsA("Model") and (m.Name == "Tree" or m.Name == "HardwoodTree") then
					local trunk = m.PrimaryPart or m:FindFirstChild("Trunk")
					if trunk and not trunk:GetAttribute("Depleted") then
						table.insert(out, { adornee = m, anchor = trunk, name = m.Name == "HardwoodTree" and "Old Tree" or "Tree", hasHp = false })
					end
				end
			end
		end
	elseif category == "pickaxe" then
		local folder = Workspace:FindFirstChild("Resources")
		if folder then
			for _, r in ipairs(folder:GetChildren()) do
				if r:IsA("Model") and (r.Name == "Rock" or r.Name == "IronRock") then
					local boulder = r.PrimaryPart or r:FindFirstChild("Boulder")
					if boulder and not boulder:GetAttribute("Depleted") then
						table.insert(out, { adornee = r, anchor = boulder, name = r.Name == "IronRock" and "Iron Vein" or "Rock", hasHp = false })
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

	local function clear()
		if lock then
			lock = nil
			highlight.Adornee = nil
			highlight.Parent = nil
			gui.Enabled = false
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

	-- True once the lock's target is dead/depleted, out of reach, or no longer
	-- matches what the equipped tool can focus.
	local function lockStale(focus, root)
		local anchor = lock.anchor
		return focus.category ~= lock.category
			or not anchor
			or not anchor.Parent
			or anchor:GetAttribute("Depleted")
			or (anchor.Position - root.Position).Magnitude > focus.reach
	end

	RunService.RenderStepped:Connect(function()
		local character = player.Character
		local root = character and character:FindFirstChild("HumanoidRootPart")
		local camera = Workspace.CurrentCamera

		local focus = (root and camera) and equippedFocus(character) or nil
		if not focus then
			clear() -- dead, no camera, or nothing that can focus is equipped
			return
		end

		-- Drop the existing lock only if it has become invalid.
		if lock and lockStale(focus, root) then
			clear()
		end

		-- While aiming, acquire / switch to the best on-screen target in reach.
		-- This never clears an existing lock — if nothing qualifies, the current
		-- lock is kept.
		if ClientState.aiming and not ClientState.inventoryOpen then
			local vp = camera.ViewportSize
			local center = Vector2.new(vp.X / 2, vp.Y / 2)

			local best, bestScore
			for _, cand in ipairs(candidates(focus.category)) do
				if (cand.anchor.Position - root.Position).Magnitude <= focus.reach then
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
end

return TargetingController