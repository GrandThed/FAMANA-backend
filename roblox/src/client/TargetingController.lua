-- Tool-aware focus/targeting. While aiming (right mouse held), focuses the best
-- object for whatever is equipped — sword→enemies, axe→trees, pickaxe→rocks —
-- but only if it's within that tool's reach. The focus gets a highlight and a
-- top-screen target panel (with an HP bar for enemies). Enemy HP is read from
-- the replicated health-bar fill, so no extra networking.

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Items = require(Shared:WaitForChild("Items"))
local Config = require(Shared:WaitForChild("Config"))
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
	if def.type == "weapon" then
		return { category = "enemy", reach = Config.reach.weapon }
	elseif def.type == "tool" and def.toolType then
		return { category = def.toolType, reach = Config.reach[def.toolType] }
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
				if e:IsA("BasePart") then
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
					if trunk then
						table.insert(out, { adornee = m, anchor = trunk, name = "Tree", hasHp = false })
					end
				end
			end
		end
	elseif category == "pickaxe" then
		local folder = Workspace:FindFirstChild("Resources")
		if folder then
			for _, r in ipairs(folder:GetChildren()) do
				if r:IsA("BasePart") and r.Name == "Rock" then
					table.insert(out, { adornee = r, anchor = r, name = "Rock", hasHp = false })
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

	local currentAdornee

	local function clear()
		if currentAdornee then
			currentAdornee = nil
			highlight.Adornee = nil
			highlight.Parent = nil
			gui.Enabled = false
		end
	end

	local function setTarget(cand)
		if cand.adornee ~= currentAdornee then
			currentAdornee = cand.adornee
			highlight.Adornee = cand.adornee
			highlight.Parent = cand.adornee
			nameLabel.Text = cand.name
			barBg.Visible = cand.hasHp
			gui.Enabled = true
		end
	end

	RunService.RenderStepped:Connect(function()
		local character = player.Character
		local root = character and character:FindFirstChild("HumanoidRootPart")
		local camera = Workspace.CurrentCamera

		if not (ClientState.aiming and root and camera) then
			clear()
			return
		end

		local focus = equippedFocus(character)
		if not focus then
			clear()
			return
		end

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

		if not best then
			clear()
			return
		end

		setTarget(best)

		if not best.adornee.Parent then
			clear()
		elseif best.hasHp then
			local frac = hpFraction(best.anchor)
			if frac then
				barFill.Size = UDim2.new(frac, 0, 1, 0)
			end
		end
	end)
end

return TargetingController
