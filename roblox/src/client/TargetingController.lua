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

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Items = require(Shared:WaitForChild("Items"))
local Config = require(Shared:WaitForChild("Config"))
local Remotes = require(Shared:WaitForChild("Remotes"))
local ClientState = require(script.Parent.ClientState)

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
				if m:IsA("Model") and m.Name == "Tree" then
					local trunk = m.PrimaryPart or m:FindFirstChild("Trunk")
					if trunk and not trunk:GetAttribute("Depleted") then
						table.insert(out, { adornee = m, anchor = trunk, name = "Tree", hasHp = false })
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
	panel.Size = UDim2.new(0, 320, 0, 44)
	panel.Position = UDim2.new(0.5, 0, 0, 14)
	panel.AnchorPoint = Vector2.new(0.5, 0)
	panel.BackgroundColor3 = Color3.fromRGB(20, 20, 26)
	panel.BackgroundTransparency = 0.2
	panel.BorderSizePixel = 0
	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0, 8)
	corner.Parent = panel
	panel.Parent = gui

	local nameLabel = Instance.new("TextLabel")
	nameLabel.Size = UDim2.new(1, -16, 0, 18)
	nameLabel.Position = UDim2.new(0, 8, 0, 4)
	nameLabel.BackgroundTransparency = 1
	nameLabel.Font = Enum.Font.GothamBold
	nameLabel.TextSize = 14
	nameLabel.TextColor3 = Color3.new(1, 1, 1)
	nameLabel.TextXAlignment = Enum.TextXAlignment.Left
	nameLabel.Text = ""
	nameLabel.Parent = panel

	local barBg = Instance.new("Frame")
	barBg.Size = UDim2.new(1, -16, 0, 12)
	barBg.Position = UDim2.new(0, 8, 0, 26)
	barBg.BackgroundColor3 = Color3.fromRGB(45, 45, 45)
	barBg.BorderSizePixel = 0
	barBg.Parent = panel

	local barFill = Instance.new("Frame")
	barFill.Size = UDim2.new(1, 0, 1, 0)
	barFill.BackgroundColor3 = Color3.fromRGB(220, 70, 70)
	barFill.BorderSizePixel = 0
	barFill.Parent = barBg

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
				barFill.Size = UDim2.new(frac, 0, 1, 0)
			end
		end
	end)
end

return TargetingController
