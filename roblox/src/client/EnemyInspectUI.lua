-- Click-to-inspect: left-click ANY enemy OR player on screen, at any
-- distance (no weapon/reach requirement — unlike TargetingController's
-- aim-lock focus), to pop a small stat card in a fixed spot (top-center)
-- with level, HP, damage, armor and magic resist. Purely informational: it
-- never sets the server focus and never touches combat.
--
-- Enemy stats are read straight off attributes EnemyService.buildEnemy
-- already replicates on the enemy part (Level/MaxHp/Damage/Armor/
-- MagicResist), plus the health-bar fill fraction for current HP — same
-- "no extra networking" trick TargetingController uses for its own HP bar.
-- An enemy card also lists its possible drops (shared/Loot, keyed by the
-- part's LootSource attribute) — same data DropService actually rolls on
-- kill, so scouting never promises something a kill can't deliver.
--
-- Player stats are read the same way: ClassService already replicates
-- Armor/MagicResist/AttackDamage/AbilityPower as Player attributes, and
-- MaxHealth/Health live on the Humanoid (a normal replicated property, no
-- extra plumbing needed). Only one card is ever shown at a time — clicking
-- a player while an enemy card is open swaps the same panel over, rather
-- than stacking a second one.

local Players = game:GetService("Players")
local UserInputService = game:GetService("UserInputService")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Classes = require(Shared:WaitForChild("Classes"))
local Items = require(Shared:WaitForChild("Items"))
local Loot = require(Shared:WaitForChild("Loot"))
local Rarity = require(Shared:WaitForChild("Rarity"))
local Theme = require(script.Parent.Theme)
local UIKit = require(script.Parent.UIKit)
local ClientState = require(script.Parent.ClientState)

local player = Players.LocalPlayer
local mouse = player:GetMouse()

local EnemyInspectUI = {}

local HIDE_AFTER = 4 -- seconds of inactivity before the card auto-hides
local PANEL_WIDTH = 220
local ROW_HEIGHT = 16

-- Fixed screen anchor for the card: top-center, clear of the top-right menu,
-- the top-left quest tracker, and the bottom HUD orbs. Every enemy inspected
-- shows up in this same spot instead of hugging the cursor.
local FIXED_ANCHOR = Vector2.new(0.5, 0)
local FIXED_OFFSET = UDim2.new(0.5, 0, 0, 70)

local function hpFraction(enemyPart)
	local billboard = enemyPart:FindFirstChild("HealthBar")
	local fill = billboard and billboard:FindFirstChild("Fill", true)
	return fill and math.clamp(fill.Size.X.Scale, 0, 1) or nil
end

-- Resolves a clicked BasePart back to the Player it belongs to (works for
-- any part of the character — body, accessories, tools) and the Model it
-- hangs off of, which is what a Highlight needs as its Adornee.
local function playerFromTarget(target)
	local character = target:FindFirstAncestorWhichIsA("Model")
	if not character then
		return nil, nil
	end
	local hitPlayer = Players:GetPlayerFromCharacter(character)
	if not hitPlayer then
		return nil, nil
	end
	return hitPlayer, character
end

function EnemyInspectUI.start()
	local gui = Instance.new("ScreenGui")
	gui.Name = "EnemyInspectUI"
	gui.ResetOnSpawn = false
	gui.IgnoreGuiInset = true
	gui.Enabled = false
	gui.Parent = player:WaitForChild("PlayerGui")

	local panel = Instance.new("Frame")
	panel.Size = UDim2.new(0, PANEL_WIDTH, 0, 0)
	panel.AutomaticSize = Enum.AutomaticSize.Y
	panel.AnchorPoint = FIXED_ANCHOR
	panel.Position = FIXED_OFFSET
	panel.Parent = gui
	UIKit.stylePanel(panel) -- Aethelgard shell — same shell as every other card
	UIKit.autoScale(panel)

	local padding = Instance.new("UIPadding")
	padding.PaddingTop = UDim.new(0, 8)
	padding.PaddingBottom = UDim.new(0, 8)
	padding.PaddingLeft = UDim.new(0, 10)
	padding.PaddingRight = UDim.new(0, 10)
	padding.Parent = panel

	local layout = Instance.new("UIListLayout")
	layout.Padding = UDim.new(0, 2)
	-- Every row below gets an explicit LayoutOrder (header=1, stats=2-6,
	-- "Drops"=7, drop rows=8+) — but UIListLayout defaults to sorting by
	-- instance Name, not LayoutOrder, so without this every plain "Frame"
	-- row (stats AND drop rows alike) sorted ahead of the "TextLabel"
	-- section header alphabetically, shoving "Drops" to the very bottom.
	layout.SortOrder = Enum.SortOrder.LayoutOrder
	layout.Parent = panel

	local headerRow = Instance.new("Frame")
	headerRow.BackgroundTransparency = 1
	headerRow.Size = UDim2.new(1, 0, 0, 20)
	headerRow.LayoutOrder = 1
	headerRow.Parent = panel

	local nameLabel = UIKit.label(headerRow, "", Theme.Text.Lg, Theme.Semantic.TextHero, Theme.Font.DisplayBold)
	nameLabel.Size = UDim2.new(1, -24, 1, 0)
	nameLabel.ZIndex = panel.ZIndex + 1

	-- Pin toggle: keeps the card up (no auto-hide timer, survives clicking
	-- elsewhere in the world) until the enemy dies or it's unpinned by hand.
	local pinButton = Instance.new("TextButton")
	pinButton.Size = UDim2.new(0, 18, 0, 18)
	pinButton.Position = UDim2.new(1, -18, 0, 1)
	pinButton.BackgroundColor3 = Theme.Color.Stone700
	pinButton.BorderSizePixel = 0
	pinButton.AutoButtonColor = false
	pinButton.FontFace = Theme.Font.BodyBold
	pinButton.TextSize = 12
	pinButton.Text = "📌"
	pinButton.TextColor3 = Theme.Semantic.TextDim
	pinButton.ZIndex = panel.ZIndex + 1
	pinButton.Parent = headerRow

	local pinStroke = Instance.new("UIStroke")
	pinStroke.Thickness = 1
	pinStroke.Color = Theme.Color.Stone500
	pinStroke.Transparency = 0.25
	pinStroke.Parent = pinButton

	-- World-space highlight on the inspected enemy itself — the card alone
	-- got lost in a crowd of slimes. A cool blue (Mana400) reads as "info",
	-- not "targeted for combat" (TargetingController's own highlight is a
	-- warm gold, kept visually distinct); it warms to the same ember tone
	-- as the pin button once locked, so the glow itself tells you it's pinned.
	local highlight = Instance.new("Highlight")
	highlight.FillTransparency = 0.75
	highlight.OutlineTransparency = 0
	highlight.FillColor = Theme.Color.Mana400
	highlight.OutlineColor = Theme.Color.Mana400
	highlight.DepthMode = Enum.HighlightDepthMode.AlwaysOnTop

	-- One "Label ......... Value" row, both halves ZIndexed above the panel.
	local function addRow(order)
		local row = Instance.new("Frame")
		row.BackgroundTransparency = 1
		row.Size = UDim2.new(1, 0, 0, ROW_HEIGHT)
		row.LayoutOrder = order
		row.Parent = panel

		local label = UIKit.label(row, "", Theme.Text.Sm, Theme.Semantic.TextLabel)
		label.Size = UDim2.new(0.5, 0, 1, 0)
		label.TextXAlignment = Enum.TextXAlignment.Left
		label.ZIndex = panel.ZIndex + 1

		local value = UIKit.label(row, "", Theme.Text.Sm, Theme.Semantic.TextStrong)
		value.Size = UDim2.new(0.5, 0, 1, 0)
		value.Position = UDim2.new(0.5, 0, 0, 0)
		value.TextXAlignment = Enum.TextXAlignment.Right
		value.ZIndex = panel.ZIndex + 1

		return label, value
	end

	local hpLabel, hpValue = addRow(2)
	hpLabel.Text = "HP"
	local adLabel, adValue = addRow(3)
	adLabel.Text = "Attack Damage"
	local apLabel, apValue = addRow(4)
	apLabel.Text = "Ability Power"
	local armorLabel, armorValue = addRow(5)
	armorLabel.Text = "Armor"
	local mrLabel, mrValue = addRow(6)
	mrLabel.Text = "Magic Resist"

	-- ---- drops section (enemies only) -----------------------------------------
	-- Built fresh each time a new enemy is shown (not every frame like the
	-- stat rows above — the drop list itself never changes while watching
	-- the same target, only its position in the list layout matters).
	local dropsHeader = UIKit.sectionLabel(panel, "Drops")
	dropsHeader.Size = UDim2.new(1, 0, 0, 16)
	dropsHeader.LayoutOrder = 7
	dropsHeader.Visible = false

	local dropRows = {} -- row Frames built for the currently shown enemy

	local function clearDropRows()
		for _, row in ipairs(dropRows) do
			row:Destroy()
		end
		dropRows = {}
		dropsHeader.Visible = false
	end

	-- itemId's own rarity tier (Rarity.forDef) colors its name, same as
	-- everywhere else in the UI — a rare drop reads as rare here too.
	local function coloredName(itemId, prefix)
		local itemDef = Items.get(itemId)
		local rarity = Rarity.forDef(itemDef)
		return (prefix or "") .. (itemDef and itemDef.name or itemId), rarity.hasGlow and rarity.textColor or nil
	end

	-- Populates the drops section for `source` (an enemy's LootSource
	-- attribute): one "Item  chance%" row per guaranteed/chance table drop,
	-- then a "Gear (random)  chance%" row followed by the pool it can roll
	-- from (no per-item odds shown — the roll picks one uniformly).
	local function buildDropRows(source)
		clearDropRows()
		local order = 8
		local hasAny = false

		local tableLoot = source and Loot.TABLE[source]
		if tableLoot then
			for _, entry in ipairs(tableLoot) do
				local qtyNote = entry.max > 1 and string.format(" x%d-%d", entry.min, entry.max) or ""
				local name, color = coloredName(entry.itemId, nil)
				local label, value = addRow(order)
				label.Text = name .. qtyNote
				label.TextTruncate = Enum.TextTruncate.AtEnd
				if color then
					label.TextColor3 = color
				end
				value.Text = string.format("%d%%", math.floor(entry.chance * 100 + 0.5))
				table.insert(dropRows, label.Parent)
				order += 1
				hasAny = true
			end
		end

		local gear = source and Loot.GEAR[source]
		if gear then
			local gearLabel, gearValue = addRow(order)
			gearLabel.Text = "Gear (random)"
			gearValue.Text = string.format("%d%%", math.floor(gear.chance * 100 + 0.5))
			table.insert(dropRows, gearLabel.Parent)
			order += 1
			for _, itemId in ipairs(gear.pool) do
				local name, color = coloredName(itemId, "  · ")
				local label, value = addRow(order)
				label.Text = name
				label.TextTruncate = Enum.TextTruncate.AtEnd
				label.TextColor3 = color or Theme.Semantic.TextDim
				value.Text = ""
				table.insert(dropRows, label.Parent)
				order += 1
			end
			hasAny = true
		end

		dropsHeader.Visible = hasAny
	end

	local watchedKind = nil -- "enemy" | "player" | nil
	local watchedPart = nil -- enemy: the anchor part carrying its attributes
	local watchedPlayer = nil -- player: the Player instance
	local watchedCharacter = nil -- player: their current character Model
	local hideToken = 0
	local pinned = false

	local function setPinVisual()
		pinButton.BackgroundColor3 = pinned and Theme.Color.Ember500 or Theme.Color.Stone700
		pinButton.TextColor3 = pinned and Theme.Semantic.TextHero or Theme.Semantic.TextDim
		pinStroke.Color = pinned and Theme.Color.Ember400 or Theme.Color.Stone500
		local glow = pinned and Theme.Color.Ember300 or Theme.Color.Mana400
		highlight.FillColor = glow
		highlight.OutlineColor = glow
	end

	local function hide()
		hideToken += 1
		watchedKind = nil
		watchedPart = nil
		watchedPlayer = nil
		watchedCharacter = nil
		pinned = false
		setPinVisual()
		highlight.Adornee = nil
		highlight.Parent = nil
		gui.Enabled = false
	end

	-- Re-reads the watched target's attributes/HP fraction. Called on first
	-- show and every frame after — the card's HP number stays live while a
	-- fight is happening in front of it, same as the aim-lock target panel.
	-- Also the ONLY thing that can close a pinned card: the target dying/
	-- leaving (part or character gone), never the timer or a background click.
	local function refreshEnemy()
		if not (watchedPart and watchedPart.Parent) then
			hide()
			return
		end
		local maxHp = watchedPart:GetAttribute("MaxHp") or 0
		local frac = hpFraction(watchedPart) or 1
		hpValue.Text = string.format("%d / %d", math.floor(maxHp * frac + 0.5), maxHp)
		adValue.Text = tostring(watchedPart:GetAttribute("AttackDamage") or 0)
		apValue.Text = tostring(watchedPart:GetAttribute("AbilityPower") or 0)

		local armor = watchedPart:GetAttribute("Armor") or 0
		local mr = watchedPart:GetAttribute("MagicResist") or 0
		-- Mitigation %% alongside the raw stat — same curve as player Armor/
		-- MR (Classes.mitigation), so "40 armor" reads as "how much weaker
		-- your weapon hits land", not just an opaque number.
		armorValue.Text = string.format("%d (-%d%%)", armor, math.floor(Classes.mitigation(armor) * 100 + 0.5))
		mrValue.Text = string.format("%d (-%d%%)", mr, math.floor(Classes.mitigation(mr) * 100 + 0.5))
	end

	local function refreshPlayer()
		if not (watchedPlayer and watchedPlayer.Parent and watchedCharacter and watchedCharacter.Parent) then
			hide()
			return
		end
		local humanoid = watchedCharacter:FindFirstChildOfClass("Humanoid")
		if not humanoid then
			-- Character exists but hasn't finished loading its Humanoid yet
			-- (rare timing case right after CharacterAdded) — just wait for
			-- the next frame instead of tearing the card down.
			return
		end
		hpValue.Text = string.format("%d / %d", math.floor(humanoid.Health + 0.5), math.floor(humanoid.MaxHealth + 0.5))
		adValue.Text = tostring(watchedPlayer:GetAttribute("AttackDamage") or 0)
		apValue.Text = tostring(watchedPlayer:GetAttribute("AbilityPower") or 0)

		local armor = watchedPlayer:GetAttribute("Armor") or 0
		local mr = watchedPlayer:GetAttribute("MagicResist") or 0
		armorValue.Text = string.format("%d (-%d%%)", armor, math.floor(Classes.mitigation(armor) * 100 + 0.5))
		mrValue.Text = string.format("%d (-%d%%)", mr, math.floor(Classes.mitigation(mr) * 100 + 0.5))
	end

	local function refresh()
		if watchedKind == "enemy" then
			refreshEnemy()
		elseif watchedKind == "player" then
			refreshPlayer()
		end
	end

	-- Only schedules an auto-hide when NOT pinned; a pinned card just skips
	-- this and waits for hide() to be called some other way (death/unpin).
	local function scheduleAutoHide()
		local token = hideToken
		task.delay(HIDE_AFTER, function()
			if not pinned and token == hideToken then
				hide()
			end
		end)
	end

	local function showEnemy(part)
		watchedKind = "enemy"
		watchedPart = part
		watchedPlayer = nil
		watchedCharacter = nil
		pinned = false
		setPinVisual()
		nameLabel.Text = string.format("%s · Lv %d", part.Name, part:GetAttribute("Level") or 1)
		buildDropRows(part:GetAttribute("LootSource"))
		refresh()
		gui.Enabled = true
		highlight.Adornee = part
		highlight.Parent = part
		-- Position stays fixed (set once at panel creation) — the card
		-- always appears in the same spot on screen regardless of where
		-- the target or the cursor is.

		hideToken += 1
		scheduleAutoHide()
	end

	local function showPlayer(targetPlayer, character)
		watchedKind = "player"
		watchedPart = nil
		watchedPlayer = targetPlayer
		watchedCharacter = character
		pinned = false
		setPinVisual()
		local classDef = Classes.get(targetPlayer:GetAttribute("Class"))
		nameLabel.Text =
			string.format("%s · %s Lv %d", targetPlayer.DisplayName, classDef.name, targetPlayer:GetAttribute("Level") or 1)
		clearDropRows() -- drops only apply to enemies, never to another player
		refresh()
		gui.Enabled = true
		-- Adorn the whole character model (not a single limb) so the
		-- outline reads as "this person", same as the enemy highlight.
		highlight.Adornee = character
		highlight.Parent = character

		hideToken += 1
		scheduleAutoHide()
	end

	pinButton.MouseButton1Click:Connect(function()
		if not watchedKind then
			return
		end
		pinned = not pinned
		setPinVisual()
		if not pinned then
			-- Unpinned with the cursor off the target: behave like a fresh
			-- show() so it still fades out after HIDE_AFTER instead of
			-- lingering forever.
			hideToken += 1
			scheduleAutoHide()
		end
	end)

	UserInputService.InputBegan:Connect(function(input, gameProcessed)
		if gameProcessed or input.UserInputType ~= Enum.UserInputType.MouseButton1 then
			return
		end
		-- Full-screen panels already own the click (inventory drag/drop,
		-- vendor, quest giver) — don't fight them for it.
		if ClientState.inventoryOpen or ClientState.storeOpen or ClientState.questOpen then
			return
		end

		local target = mouse.Target
		local enemiesFolder = Workspace:FindFirstChild("Enemies")
		-- Only real enemies (they carry a HealthBar billboard), same check
		-- TargetingController uses — never a stray part that happens to
		-- share a name.
		if target and target.Parent == enemiesFolder and target:FindFirstChild("HealthBar") then
			showEnemy(target)
			return
		end

		if target then
			local hitPlayer, character = playerFromTarget(target)
			-- Skip inspecting yourself — there's no "far away" click on your
			-- own character, and CharacterUI already covers your own stats.
			if hitPlayer and hitPlayer ~= player then
				showPlayer(hitPlayer, character)
				return
			end
		end

		if watchedKind and not pinned then
			-- Clicked elsewhere in the world (not on a person UI): dismiss
			-- the card instead of leaving it stuck on a stale target. A
			-- pinned card rides this out — only death/leaving or unpinning
			-- closes it.
			hide()
		end
	end)

	RunService.RenderStepped:Connect(function()
		if watchedKind then
			refresh()
		end
	end)
end

return EnemyInspectUI