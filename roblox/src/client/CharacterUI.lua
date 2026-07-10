-- Character window (C key / the top-right button) — the docs/UI.md §8
-- "Character" screen adapted to the stats this game actually has:
--   left  — live avatar viewport over the player's name, class + level,
--           XP progress and gold.
--   right — VITALS: HP/Mana; COMBAT: Attack Damage/Ability Power/Armor/
--           Magic Resist from the player's class + level (see
--           shared/Classes.lua statsAtLevel, replicated as attributes by
--           ClassService); COMBAT BONUSES: the summed bonuses of the
--           equipped traits (Traits.statsFor over the TraitPoints
--           attribute); ACTIVE TRAITS: every trait/school with points,
--           tinted by its reached metal tier (Theme.tierFor).
-- Pure read-only view: everything derives from replicated attributes, so
-- there are no remotes here.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ContextActionService = game:GetService("ContextActionService")
local HttpService = game:GetService("HttpService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Traits = require(Shared:WaitForChild("Traits"))
local Spells = require(Shared:WaitForChild("Spells"))
local Classes = require(Shared:WaitForChild("Classes"))
local Theme = require(script.Parent.Theme)
local TopRightMenu = require(script.Parent.TopRightMenu)
local UIKit = require(script.Parent.UIKit)

local player = Players.LocalPlayer

local CharacterUI = {}

local PANEL_W, PANEL_H = 600, 520
local TOPBAR = 36
local LEFT_W = 210

function CharacterUI.start()
	local gui = Instance.new("ScreenGui")
	gui.Name = "CharacterUI"
	gui.ResetOnSpawn = false
	gui.Parent = player:WaitForChild("PlayerGui")

	local panel = Instance.new("Frame")
	panel.Size = UDim2.new(0, PANEL_W, 0, PANEL_H)
	panel.Position = UDim2.new(0.5, 0, 0.5, 0)
	panel.AnchorPoint = Vector2.new(0.5, 0.5)
	panel.Visible = false
	panel.Parent = gui
	UIKit.stylePanel(panel)
	UIKit.addShadow(panel)
	UIKit.autoScale(panel)

	UIKit.titleBar(panel, "Character", TOPBAR)
	local closeBtn = UIKit.closeButton(panel)
	closeBtn.Position = UDim2.new(1, -5, 0, 5)
	closeBtn.AnchorPoint = Vector2.new(1, 0)

	-- ---- left column: avatar + identity ------------------------------------
	local leftCol = Instance.new("Frame")
	leftCol.Size = UDim2.new(0, LEFT_W, 1, -(TOPBAR + 24))
	leftCol.Position = UDim2.new(0, 12, 0, TOPBAR + 12)
	leftCol.BackgroundColor3 = Theme.Semantic.SurfaceWell
	leftCol.BorderSizePixel = 0
	leftCol.Parent = panel

	local doll = Instance.new("ViewportFrame")
	doll.Size = UDim2.new(1, -8, 0, 210)
	doll.Position = UDim2.new(0, 4, 0, 4)
	doll.BackgroundTransparency = 1
	doll.Ambient = Color3.fromRGB(160, 160, 170)
	doll.LightColor = Color3.new(1, 1, 1)
	doll.Parent = leftCol

	local dollCharacter = nil
	local function refreshDoll()
		local character = player.Character
		if not character or not character:FindFirstChild("HumanoidRootPart") then
			return
		end
		if character == dollCharacter then
			return
		end
		dollCharacter = character
		doll:ClearAllChildren()
		character.Archivable = true
		local clone = character:Clone()
		character.Archivable = false
		for _, descendant in ipairs(clone:GetDescendants()) do
			if descendant:IsA("BaseScript") or descendant:IsA("Sound") then
				descendant:Destroy()
			elseif descendant:IsA("BasePart") then
				descendant.Anchored = true
			end
		end
		clone:PivotTo(CFrame.new())
		clone.Parent = doll

		local camera = Instance.new("Camera")
		camera.FieldOfView = 30
		camera.Parent = doll
		doll.CurrentCamera = camera
		local _, size = clone:GetBoundingBox()
		camera.CFrame = CFrame.lookAt(Vector3.new(0, 0.2, -(size.Y * 2.1 + 1)), Vector3.zero)
	end

	local nameLabel =
		UIKit.label(leftCol, player.DisplayName, Theme.Text.Hero, Theme.Semantic.TextHero, Theme.Font.DisplayBold)
	nameLabel.Size = UDim2.new(1, 0, 0, 24)
	nameLabel.Position = UDim2.new(0, 0, 0, 216)

	local classLabel = UIKit.label(leftCol, "", Theme.Text.Body, Theme.Semantic.TextSecondary)
	classLabel.Size = UDim2.new(1, 0, 0, 18)
	classLabel.Position = UDim2.new(0, 0, 0, 240)

	-- XP bar (same read as the HUD's: Xp/XpToNext attributes).
	local xpBg = Instance.new("Frame")
	xpBg.Size = UDim2.new(1, -24, 0, 8)
	xpBg.Position = UDim2.new(0, 12, 0, 266)
	xpBg.BackgroundColor3 = Theme.Color.Ink900
	xpBg.BorderSizePixel = 0
	xpBg.Parent = leftCol

	local xpStroke = Instance.new("UIStroke")
	xpStroke.Thickness = 1
	xpStroke.Color = Theme.Semantic.BorderMuted
	xpStroke.Parent = xpBg

	local xpFill = Instance.new("Frame")
	xpFill.Size = UDim2.new(0, 0, 1, 0)
	xpFill.BackgroundColor3 = Color3.new(1, 1, 1)
	xpFill.BorderSizePixel = 0
	xpFill.Parent = xpBg

	local xpGradient = Instance.new("UIGradient")
	xpGradient.Color = ColorSequence.new(Color3.fromRGB(138, 106, 30), Theme.Color.Gold400)
	xpGradient.Parent = xpFill

	local xpLabel = UIKit.label(leftCol, "", Theme.Text.Xs, Theme.Semantic.TextMuted, Theme.Font.Body)
	xpLabel.Size = UDim2.new(1, 0, 0, 14)
	xpLabel.Position = UDim2.new(0, 0, 0, 278)

	local goldLabel = UIKit.label(leftCol, "", 14, Theme.Semantic.Currency)
	goldLabel.Size = UDim2.new(1, 0, 0, 18)
	goldLabel.Position = UDim2.new(0, 0, 1, -26)

	-- ---- right column: combat stats + active traits --------------------------
	-- ScrollingFrame (not a plain Frame) so a long trait/school list scrolls
	-- instead of overflowing the panel — draggable on touch, wheel on mouse.
	local rightCol = Instance.new("ScrollingFrame")
	rightCol.Size = UDim2.new(1, -(LEFT_W + 36), 1, -(TOPBAR + 24))
	rightCol.Position = UDim2.new(0, LEFT_W + 24, 0, TOPBAR + 12)
	rightCol.BackgroundTransparency = 1
	rightCol.BorderSizePixel = 0
	rightCol.ScrollBarThickness = 6
	rightCol.ScrollBarImageColor3 = Theme.Semantic.BorderMuted
	rightCol.ScrollingDirection = Enum.ScrollingDirection.Y
	rightCol.CanvasSize = UDim2.new(0, 0, 0, 0)
	rightCol.AutomaticCanvasSize = Enum.AutomaticSize.Y
	rightCol.Parent = panel

	local layout = Instance.new("UIListLayout")
	layout.SortOrder = Enum.SortOrder.LayoutOrder
	layout.Padding = UDim.new(0, 3)
	layout.Parent = rightCol

	-- Keeps rows clear of the scrollbar (ScrollBarThickness above) instead of
	-- letting the value column sit underneath it.
	local rightColPadding = Instance.new("UIPadding")
	rightColPadding.PaddingRight = UDim.new(0, 14)
	rightColPadding.Parent = rightCol

	-- Trait totals from the server ({ [traitOrSchoolId] = points }).
	local function traitTotals()
		local raw = player:GetAttribute("TraitPoints")
		if typeof(raw) ~= "string" or raw == "" then
			return {}
		end
		local ok, decoded = pcall(HttpService.JSONDecode, HttpService, raw)
		return (ok and typeof(decoded) == "table") and decoded or {}
	end

	local rowOrder = 0
	local function addRow(leftText, rightText, leftColor, rightColor, tall)
		rowOrder += 1
		local row = Instance.new("Frame")
		row.Size = UDim2.new(1, 0, 0, tall and 20 or 17)
		row.BackgroundTransparency = 1
		row.LayoutOrder = rowOrder
		row.Parent = rightCol

		local left = UIKit.label(row, leftText, Theme.Text.Body, leftColor or Theme.Semantic.TextBody,
			tall and Theme.Font.BodyBold or Theme.Font.Body)
		left.Size = UDim2.new(1, -70, 1, 0)
		left.TextXAlignment = Enum.TextXAlignment.Left

		if rightText then
			local right = UIKit.label(row, rightText, Theme.Text.Body, rightColor or Theme.Semantic.TextStrong)
			right.Size = UDim2.new(0, 66, 1, 0)
			right.Position = UDim2.new(1, -66, 0, 0)
			right.TextXAlignment = Enum.TextXAlignment.Right
		end
		return row
	end

	local function addSection(text)
		rowOrder += 1
		local label = UIKit.sectionLabel(rightCol, text)
		label.Size = UDim2.new(1, 0, 0, 18)
		label.TextXAlignment = Enum.TextXAlignment.Left
		label.LayoutOrder = rowOrder
	end

	local refresh -- rebuilds both columns from the current attributes

	refresh = function()
		if not panel.Visible then
			return
		end
		refreshDoll()

		local level = player:GetAttribute("Level") or 1
		local classDef = Classes.get(player:GetAttribute("Class"))
		classLabel.Text = string.format("%s — Lv %d", classDef.name, level)

		local xp = player:GetAttribute("Xp") or 0
		local xpToNext = player:GetAttribute("XpToNext") or 1
		xpFill.Size = UDim2.new(math.clamp(xp / math.max(xpToNext, 1), 0, 1), 0, 1, 0)
		xpLabel.Text = string.format("%d / %d XP", xp, xpToNext)
		goldLabel.Text = ("◈ %d Gold"):format(player:GetAttribute("Gold") or 0)

		for _, child in ipairs(rightCol:GetChildren()) do
			if child:IsA("GuiObject") then
				child:Destroy()
			end
		end
		rowOrder = 0

		-- Base pools, straight from the replicated character/attributes.
		local humanoid = player.Character and player.Character:FindFirstChildOfClass("Humanoid")
		addSection("Vitals")
		addRow("Health", humanoid and string.format("%d / %d", humanoid.Health, humanoid.MaxHealth) or "—")
		addRow(
			"Mana",
			string.format("%d / %d", player:GetAttribute("Mana") or 0, player:GetAttribute("MaxMana") or 0)
		)

		-- Regen rates (SynergyService.recompute publishes these). HP regen's
		-- base tick only runs out of combat (Config.HP.regenDelay), so it's
		-- labeled distinctly from the always-on Brawler trickle; mana regen
		-- is always on, mirroring ManaService's own tick.
		local hpRegen = player:GetAttribute("HpRegenPerSec") or 0
		local hpRegenAlwaysOn = player:GetAttribute("HpRegenAlwaysOnPerSec") or 0
		if hpRegenAlwaysOn > 0 then
			addRow("HP Regen", string.format("+%.1f/s", hpRegen + hpRegenAlwaysOn))
		else
			addRow("HP Regen", string.format("+%.1f/s (out of combat)", hpRegen))
		end
		addRow("Mana Regen", string.format("+%.1f/s", player:GetAttribute("ManaRegenPerSec") or 0))

		-- Trait totals up front — Combat needs them to show Armor/Magic Resist
		-- INCLUDING trait bonuses (e.g. Bastion), not just the class base.
		local totals = traitTotals()
		local stats = Traits.statsFor(totals)

		-- Class + level combat stats (see shared/Classes.lua statsAtLevel),
		-- replicated by ClassService as plain attributes — same pattern as
		-- Vitals above, no remote needed. Armor/Magic Resist add the trait
		-- bonus (Bastion, etc.) on top so the number shown is the player's
		-- actual total, not just the class's base value.
		addSection("Combat")
		addRow("Attack Damage", tostring(player:GetAttribute("AttackDamage") or 0))
		addRow("Ability Power", tostring(player:GetAttribute("AbilityPower") or 0))
		addRow("Armor", tostring((player:GetAttribute("Armor") or 0) + (stats.armor or 0)))
		addRow("Magic Resist", tostring((player:GetAttribute("MagicResist") or 0) + (stats.mr or 0)))
		addRow(
			"Crit Chance",
			string.format("%d%%", math.floor((player:GetAttribute("CritChance") or 0) * 100 + 0.5))
		)
		local dodge = player:GetAttribute("DodgeChance") or 0
		if dodge > 0 then
			addRow("Dodge Chance", string.format("%d%%", math.floor(dodge * 100 + 0.5)))
		end

		-- Combat bonuses granted by the equipped traits (school passives ride
		-- the damage hooks server-side and aren't listed here).
		addSection("Trait bonuses")
		local any = false
		for _, key in ipairs({ "crit", "attackSpeed", "duration", "hp", "regen", "armor", "dodge" }) do
			if stats[key] then
				any = true
				addRow(Traits.statLabel(key, stats[key]), nil, Theme.Semantic.TextStrong)
			end
		end
		if not any then
			addRow("None — equip trait gear", nil, Theme.Semantic.TextDim)
		end

		-- Every trait/school with points, tinted by its reached metal tier.
		addSection("Traits & schools")
		local listed = false
		for _, schoolId in ipairs(Spells.schoolOrder) do
			local points = tonumber(totals[schoolId]) or 0
			if points > 0 then
				listed = true
				local school = Spells.schools[schoolId]
				local steps = Spells.timelineFor(school)
				local reached = 0
				for _, step in ipairs(steps) do
					if points >= step.level then
						reached += 1
					end
				end
				local tier = Theme.tierFor(reached, #steps)
				addRow(school.name, tostring(points), tier.border, Theme.Semantic.TextBody, true)
			end
		end
		for _, traitId in ipairs(Traits.order) do
			local points = tonumber(totals[traitId]) or 0
			local traitDef = Traits.get(traitId)
			if points > 0 and traitDef then
				listed = true
				local reached = 0
				for _, threshold in ipairs(traitDef.thresholds) do
					if points >= threshold[1] then
						reached += 1
					end
				end
				local tier = Theme.tierFor(reached, #traitDef.thresholds)
				local color = reached > 0 and tier.border or Theme.Semantic.TextMuted
				addRow(traitDef.name, tostring(points), color, Theme.Semantic.TextBody, true)
			end
		end
		if not listed then
			addRow("Nothing equipped yet", nil, Theme.Semantic.TextDim)
		end
	end

	-- ---- toggling --------------------------------------------------------------
	local function setOpen(open)
		panel.Visible = open
		if open then
			refresh()
		end
	end

	local openBtn = TopRightMenu.addButton("Character (C)", 2)

	openBtn.Activated:Connect(function()
		setOpen(not panel.Visible)
	end)
	closeBtn.Activated:Connect(function()
		setOpen(false)
	end)

	ContextActionService:BindAction("ToggleCharacter", function(_, inputState)
		if inputState == Enum.UserInputState.Begin then
			setOpen(not panel.Visible)
		end
		return Enum.ContextActionResult.Pass
	end, false, Enum.KeyCode.C)

	-- Live refresh while open (equipment, level, gold and mana all move).
	for _, attribute in ipairs({
		"TraitPoints",
		"Level",
		"Xp",
		"Gold",
		"Mana",
		"MaxMana",
		"Class",
		"AttackDamage",
		"AbilityPower",
		"Armor",
		"MagicResist",
		"CritChance",
		"DodgeChance",
		"HpRegenPerSec",
		"HpRegenAlwaysOnPerSec",
		"ManaRegenPerSec",
	}) do
		player:GetAttributeChangedSignal(attribute):Connect(refresh)
	end
end

return CharacterUI