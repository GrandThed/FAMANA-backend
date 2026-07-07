# Aethelgard — Roblox Implementation Spec

How to build this design system inside Roblox (Luau + the GUI instance model). This is the engineering companion to `readme.md`; read that first for the *why*. This doc is the *how*, translated to `Color3`, `UDim2`, `UIStroke`, `UIGradient`, fonts, and `ImageLabel` icons.

> **Codename / placeholders:** "Aethelgard", class "Flamewarden", "Ironreach Keep" are sample flavor only — rename freely.

---

## 0. Translation cheat-sheet (CSS → Roblox)

| Web / CSS thing | Roblox equivalent |
|---|---|
| `background: #hex` | `Frame.BackgroundColor3 = Color3.fromRGB(...)` |
| `border: 1px solid` | child `UIStroke` (`Thickness`, `Color`, `ApplyStrokeMode = Border`) |
| `linear-gradient()` | child `UIGradient` (`Color = ColorSequence`, `Rotation`) |
| sharp corners (default) | **no `UICorner`** — leave Frames square |
| `border-radius: 50%` (orbs) | `UICorner` `CornerRadius = UDim.new(0.5, 0)` |
| `border-radius: 6px` (chips) | `UICorner` `CornerRadius = UDim.new(0, 6)` |
| `box-shadow` (drop) | 9-slice shadow `ImageLabel` behind the frame |
| `box-shadow: inset …` (glow) | inner `ImageLabel` (radial glow PNG) or `UIStroke` + `UIGradient` |
| `clip-path: polygon()` (hexagon) | pre-rendered **hexagon image**, tinted via `ImageColor3` |
| icon `<svg><use>` | `ImageLabel.Image = "rbxassetid://…"`, tint via `ImageColor3` |
| `gap` in flex row | `UIListLayout.Padding` |
| grid of cells | `UIGridLayout` (fixed `CellSize`/`CellPadding`) |
| `position:absolute; left/top` | `Position = UDim2.fromOffset(x, y)` + `AnchorPoint` |
| `text-shadow` | duplicate `TextLabel` behind, offset + dark, or `UIStroke` on text |
| `letter-spacing` | not native — bake into the string or use `RichText`/per-glyph; keep labels short |

**Global rules that never change:** sharp corners everywhere except orbs & chips; one ember accent; two serif fonts, no sans; no emoji; light reads as forge-glow from **above**; recesses read as inset black.

---

## 1. Instance architecture

```
PlayerGui
└── HUDGui (ScreenGui, IgnoreGuiInset = true, ResetOnSpawn = false, DisplayOrder = 1)
    ├── TargetPlate      (top-center enemy nameplate)
    ├── TraitRailCompact (top-left, in-world compact rail)
    ├── HotbarFrame      (bottom-center: slots + XP bar)
    ├── OrbHealth        (bottom-left)
    └── OrbMana          (bottom-right)

└── WindowsGui (ScreenGui, DisplayOrder = 10)   ← modal panels, one open at a time
    ├── InventoryWindow
    ├── CharacterWindow
    └── VendorWindow

└── TooltipGui (ScreenGui, DisplayOrder = 100)  ← always on top, follows cursor
    └── ItemTooltip
```

- Keep the three layers on separate `ScreenGui`s so tooltip z-order is trivially above windows, and windows above HUD.
- Design resolution is **1280×720**. Wrap each window's content in a fixed-size frame and scale with a `UIScale` bound to viewport (see §9), rather than authoring in `Scale` units — the whole system is offset/pixel-based (42px grid).

---

## 2. Theme module (drop-in)

Create `ReplicatedStorage/UI/Theme.luau`. Every color below is the exact token from `tokens/*.css`, pre-converted to `Color3.fromRGB`.

```lua
--!strict
-- Aethelgard design tokens. Mirrors tokens/*.css 1:1.
local Theme = {}

local function rgb(r, g, b) return Color3.fromRGB(r, g, b) end

------------------------------------------------------------------ COLORS
Theme.Color = {
	-- Ink (backgrounds & panels)
	Ink900 = rgb(8, 5, 5),      Ink850 = rgb(11, 7, 7),
	Ink800 = rgb(12, 8, 8),     Ink750 = rgb(19, 12, 12),
	Ink700 = rgb(23, 15, 15),   Ink650 = rgb(26, 18, 16),
	Ink600 = rgb(30, 20, 20),
	-- Stone (structure)
	Stone800 = rgb(46, 30, 26), Stone700 = rgb(58, 38, 32),
	Stone600 = rgb(61, 42, 34), Stone500 = rgb(74, 50, 38),
	StoneLine = rgb(42, 26, 22),
	-- Ember (accent)
	Ember600 = rgb(90, 32, 16),  Ember500 = rgb(138, 58, 30),
	Ember400 = rgb(200, 106, 58),Ember300 = rgb(214, 100, 42), -- primary accent
	Ember200 = rgb(232, 132, 58),
	-- Blood (danger)
	Blood600 = rgb(58, 28, 20), Blood500 = rgb(107, 50, 38), Blood400 = rgb(214, 122, 90),
	-- Gold / bone
	Gold400 = rgb(232, 184, 79),  Gold300 = rgb(232, 206, 172), NameGold = rgb(224, 168, 106),
	-- Parchment text ramp
	Parch100 = rgb(240, 228, 208), Parch200 = rgb(216, 200, 184),
	Parch300 = rgb(184, 152, 120), Parch400 = rgb(138, 106, 84),
	Parch500 = rgb(122, 80, 64),   Parch600 = rgb(106, 74, 58),
	BrownLabel = rgb(138, 90, 68),
	-- Cool metals
	Steel400 = rgb(205, 214, 222), Steel600 = rgb(90, 99, 108),
	Mana400 = rgb(58, 122, 198),   Mana600 = rgb(20, 48, 106),
}

-- Semantic aliases (reference these in UI code, not raw ramp names)
local C = Theme.Color
Theme.Semantic = {
	BgWorldTop = C.Ink600, BgWorldMid = C.Ink750, BgWorldBot = C.Ink900,
	PanelTop = C.Ink700, PanelBot = C.Ink800,
	SurfaceWell = C.Ink850,
	BorderPanel = C.Stone600, BorderSlot = C.Stone600,
	BorderMuted = C.Stone700, BorderDivider = C.Stone500, BorderHair = C.StoneLine,
	TextTitle = C.Gold300, TextHero = C.NameGold,
	TextBody = C.Parch200, TextStrong = C.Parch100, TextSecondary = C.Parch300,
	TextMuted = C.Parch400, TextDim = C.Parch500, TextFaint = C.Parch600, TextLabel = C.BrownLabel,
	Accent = C.Ember300, AccentHi = C.Ember200, AccentShadow = C.Ember600,
	Currency = C.Gold400, Danger = C.Blood400,
}
-- Alpha surfaces (Roblox uses BackgroundTransparency, so store as {color, transparency})
Theme.Alpha = {
	SurfaceSlot  = { C.Ink900, 0.65 }, -- rgba(0,0,0,.35)
	SurfaceRaise = { Color3.new(1,1,1), 0.97 }, -- rgba(255,255,255,.03)
}

------------------------------------------------------------------ RARITY
-- border, text, glow(color). Common has no glow.
Theme.Rarity = {
	Common    = { border = rgb(106,100,88),  text = rgb(184,178,162), glow = rgb(154,148,132), hasGlow = false },
	Uncommon  = { border = rgb(92,138,60),   text = rgb(127,176,85),  glow = rgb(92,138,60),   hasGlow = true },
	Rare      = { border = rgb(79,143,214),  text = rgb(106,164,224), glow = rgb(60,110,168),  hasGlow = true },
	Epic      = { border = rgb(167,106,214), text = rgb(196,143,240), glow = rgb(167,106,214), hasGlow = true },
	Legendary = { border = rgb(232,168,58),  text = rgb(240,192,96),  glow = rgb(224,160,58),  hasGlow = true },
}
Theme.RarityOrder = { "Common", "Uncommon", "Rare", "Epic", "Legendary" }

------------------------------------------------------------------ TRAIT TIERS (hexagon badge)
Theme.Tier = {
	Inactive  = { border = C.Stone700,      fill1 = C.Ink650,       fill2 = C.Ink650,       icon = C.Parch600 },
	Bronze    = { border = rgb(192,132,74), fill1 = rgb(110,68,35), fill2 = rgb(62,38,18),  icon = rgb(244,216,184) },
	Silver    = { border = rgb(205,214,222),fill1 = rgb(90,99,108), fill2 = rgb(46,52,58),  icon = rgb(255,255,255) },
	Gold      = { border = rgb(240,196,76), fill1 = rgb(138,106,30),fill2 = rgb(78,58,14),  icon = rgb(255,244,208) },
	-- Prismatic: border is a rainbow UIGradient (see §6.3), fills below
	Prismatic = { fill1 = rgb(42,32,54),    fill2 = rgb(20,16,25),  icon = rgb(255,255,255) },
}
Theme.PrismaticSequence = ColorSequence.new({
	ColorSequenceKeypoint.new(0.00, rgb(224,118,58)),
	ColorSequenceKeypoint.new(0.20, rgb(240,196,76)),
	ColorSequenceKeypoint.new(0.40, rgb(143,176,90)),
	ColorSequenceKeypoint.new(0.60, rgb(106,164,224)),
	ColorSequenceKeypoint.new(0.80, rgb(167,106,214)),
	ColorSequenceKeypoint.new(1.00, rgb(224,118,58)),
})

------------------------------------------------------------------ TRAIT IDENTITY HUES
Theme.TraitHue = {
	Bastion = rgb(224,168,58),  Warden = rgb(90,160,208),  Brawler = rgb(214,122,58),
	Berserker = rgb(214,74,58), Blademaster = rgb(205,214,222), Scout = rgb(143,176,90),
	Ranger = rgb(92,138,60),    Sniper = rgb(106,164,224), Lynx = rgb(154,134,200),
	Pyromancer = rgb(240,144,42),Mystic = rgb(167,106,214),Trapper = rgb(168,138,74),
}

------------------------------------------------------------------ TYPE
Theme.Font = {
	Display = Font.fromEnum(Enum.Font.GrenzeGotisch),
	DisplayBold = Font.new("rbxasset://fonts/families/GrenzeGotisch.json", Enum.FontWeight.SemiBold),
	Body = Font.fromEnum(Enum.Font.Merriweather),
	BodyBold = Font.new("rbxasset://fonts/families/Merriweather.json", Enum.FontWeight.Bold),
}
-- Point sizes (px in the mock → TextSize at 1280×720; scale with UIScale)
Theme.Text = {
	Title = 23, Hero = 19, Item = 18, Lg = 15,
	Body = 13, Sm = 12, Xs = 11, Label = 10, Micro = 8,
}

------------------------------------------------------------------ SPACING & GEOMETRY
Theme.Space = { s1=3, s2=5, s3=8, s4=12, s5=16, s6=24, s7=40 }
Theme.Size = {
	Cell = 42,       -- inventory grid module (the spine)
	CellGutter = 2,  -- item inset inside its footprint
	Slot = 46,       -- equipment slot
	Hex = 38,        -- trait hexagon (rail)
	HexSm = 26,      -- trait hexagon (compact HUD)
	Chip = 30,       -- effect / inactive-trait chip
	Orb = 74, OrbSm = 58,
	RailW = 210, PanelW = 770,
	BorderW = 1, BorderW2 = 2,
}

return Theme
```

> **Transparency note:** Roblox has no rgba on `BackgroundColor3`. Where CSS used `rgba(0,0,0,.35)` etc., set `BackgroundColor3` to the color and `BackgroundTransparency` to `1 - alpha`. The `Theme.Alpha` table stores these pairs.

---

## 3. Typography

Two **Roblox-native serif families**, so no font uploads needed:

- **Display** → `Enum.Font.GrenzeGotisch` — window titles, item names, big trait counts, primary-button labels.
- **Body** → `Enum.Font.Merriweather` — stats, section labels, thresholds, flavor text.

Set via the `FontFace` API for weight control:
```lua
label.FontFace = Theme.Font.DisplayBold   -- SemiBold Grenze
label.TextSize = Theme.Text.Title         -- 23
label.TextColor3 = Theme.Semantic.TextTitle
```

Rules:
- **No sans-serif anywhere.** If a family is missing from your Studio font picker, self-host the `.ttf` and register a `FontFace` from an uploaded font asset — ping the designer for the files.
- **Letter-spacing** (the `SECTION LABEL · 2.5px` look) isn't native. For short all-caps labels, either accept default tracking or insert thin spaces between glyphs (`E X A M P L E`) only for the very short section headers. Don't fake tracking on body text.
- **Text glow / shadow** on titles: add a `UIStroke` (Thickness 1, Color `Ink900`, Transparency 0.3) or a duplicate offset label. The ember title glow in mocks is decorative — a soft `UIStroke` is enough.

---

## 4. Spacing & the grid module

The **42px cell** is the whole system's spine.

- **Inventory grid:** a `Frame` sized `UDim2.fromOffset(cols*42, rows*42)` with a `UIGridLayout`:
  ```lua
  grid.CellSize = UDim2.fromOffset(42, 42)
  grid.CellPadding = UDim2.fromOffset(0, 0)   -- lines are drawn, not gaps
  ```
  Grid lines: place a background `Frame` (`SurfaceWell` = Ink850) with a tiling line texture, or draw 1px divider Frames. Item footprints are absolute-positioned over the grid, **not** grid children (a 2×3 item spans cells).
- **Item footprint:** an item occupying C×R cells is `UDim2.fromOffset(C*42, R*42)`, positioned at `UDim2.fromOffset(col*42, row*42)`, inset by `CellGutter` (2px) via a child with `Position = (2,2)` / `Size = -4,-4`.
- **Equipment slots:** 46px squares laid out with `UIListLayout` (vertical, `Padding = 6–7`).
- **Spacing scale:** use `Theme.Space` for all paddings (`UIPadding`) and list gaps (`UIListLayout.Padding`). Don't free-type pixel values.

---

## 5. Rarity system

Border color, name-text color, and glow escalate together; Common has no glow. Apply to any slot/tooltip/tile:

```lua
local function applyRarity(frame, rarityName)
	local r = Theme.Rarity[rarityName]
	local stroke = frame:FindFirstChildOfClass("UIStroke")
	stroke.Color = r.border
	if r.hasGlow then
		-- inner glow: radial glow ImageLabel tinted r.glow at ~0.8 transparency
		frame.Glow.ImageColor3 = r.glow
		frame.Glow.Visible = true
	else
		frame.Glow.Visible = false
	end
end
```

Name text uses `r.text`. Order for sorting/summaries is `Theme.RarityOrder`.

---

## 6. Component recipes

### 6.1 Panel (window shell)
- `Frame`, `BackgroundColor3 = PanelTop`, plus a child `UIGradient` from `PanelTop → PanelBot` (`Rotation = 90`).
- `UIStroke` Thickness 1, Color `BorderPanel`.
- **Drop shadow:** a 9-slice shadow `ImageLabel` (soft black PNG, `SliceCenter`) behind the panel, sized ~+40px, `ImageTransparency ≈ 0.25`.
- **Top forge highlight** (`--inset-panel`): a 1px `Frame` at the top edge, `Ember200` at ~0.9 transparency, or a thin `UIGradient` overlay.
- **Title bar:** child frame, bottom `UIStroke`/divider `BorderPanel` at 2px; title uses `DisplayBold` / `TextTitle`; a `titlebar-wash` gradient (ember at .10 → transparent).

### 6.2 Item slot
- Square `Frame` (`Slot` = 46 for equipment, or footprint size in grid).
- `BackgroundColor3 = Ink900`, `BackgroundTransparency = 0.6`; child `UIGradient`/radial for the `radial-gradient(circle at 50% 35%, glow, black)` — simplest is a radial glow `ImageLabel` tinted the rarity glow.
- `UIStroke` = rarity border. Higher rarities add the outer glow image (§5).
- Icon `ImageLabel` centered, `ImageColor3 = rarity.text`, size ≈ 55% of slot.
- **Empty slot:** no icon; a centered `TextLabel` (`Micro` size, `TextFaint`) with the slot name (`HANDS`, `LEGS`, `NECK`…).

### 6.3 Trait hexagon badge  ← the signature element
Do **not** try to polygon-clip in Roblox. Ship a **hexagon image** and tint it:

1. Upload two PNGs (flat-top hexagon, from `assets/sprite.svg` proportions): `hex_border` (solid hexagon) and `hex_fill` (hexagon inset ~2px). Both white on transparent.
2. Build the badge as a stack:
   ```
   HexBadge (Frame, transparent, size = Hex or HexSm, AspectRatio 1:1.1)
   ├── Border  (ImageLabel, Image=hex_border, ImageColor3 = tier.border)
   ├── Fill    (ImageLabel, Image=hex_fill,   inset 2px)   ← UIGradient tier.fill1→fill2, Rotation 150
   └── Icon    (ImageLabel, trait glyph, ImageColor3 = tier.icon, ~50% size)
   ```
3. **Tiers:** set `Border.ImageColor3` = `Theme.Tier[tier].border`; Fill gradient from `fill1→fill2`.
   - **Prismatic:** give `Fill`'s parent a `UIGradient` with `Color = Theme.PrismaticSequence` on the **Border** image, and animate `Rotation` 0→360 over ~6s for the shimmer.
   - **Inactive:** use the `Inactive` tier colors and swap the hexagon for a **rounded-square chip** (30px, `UICorner` 6) — inactive traits are visually demoted (see mocks).

### 6.4 Trait row — three variants
All three read the same trait data `{ key, name, count, breakpoints = {…}, tier }`.

- **Detailed (rail):** `[hex 38] [count Display] [name + dotted breakpoints]`. Active rows get a left accent edge = tier color (2px `Frame` on the left) and a faint tier-tinted background gradient. Inactive rows use the chip + muted text + `count/next`.
- **Compact (HUD):** `[hex 26] [name] [count/next]`, dark row bg (`Ink800` @ .8), 2px left border = tier color. Width ~200.
- **Minimal (HUD):** just `[hex] [count/next]` stacked vertically; trait name shown only on hover (a small tooltip or the compact row on mouse-enter).

Dotted breakpoints (`2 · 4 · 6 · 8` with the reached one lit): build with `RichText` in one `TextLabel` —
```lua
label.RichText = true
label.Text = '2 · 4 · <font color="#f0c44c">6</font> · 8'
```

### 6.5 Item tooltip
- `TooltipGui` layer. A `Frame` with the §6.1 panel treatment but border = **rarity color** and a rarity-glow drop shadow.
- **Pointer:** a small 45°-rotated square `Frame` on the left edge (`Ink900` bg, two-sided `UIStroke` won't rotate cleanly — use a tiny triangle image instead, tinted rarity border).
- Content order (see `components/tooltip.card.html`): name (Display, rarity text) + `Lv` · rarity·slot · size · divider · stat lines (`+N` in `TextStrong`) · **granted trait points** (mini 19px hexes + `Name +N`) · italic flavor.
- **Follow logic:** on `MouseEnter` of a slot, position the tooltip next to the cursor, clamped to screen; hide on `MouseLeave`. Use `UserInputService`/`GetMouseLocation` and offset by the pointer.

### 6.6 Buttons
- **Primary:** `Frame` + `UIGradient` `Ember500→Ember600` (Rotation 90), `UIStroke` `Ember400`, label `DisplayBold` `#ffe4c8`, faint ember glow shadow. Hover → shift gradient toward `Ember400/Ember300`; press → darken + 1px down.
- **Ghost:** transparent bg, `UIStroke` `Stone500`, label `TextSecondary`.
- **Close:** 24–26px square, `Blood600` bg, `Blood500` stroke, `✕` in `Danger`.
- **Class pill:** `SurfaceRaise` bg, `Stone500` stroke, tiny all-caps `TextSecondary` label.

### 6.7 Status orbs (the only round chrome)
- `Frame` size 74 (58 compact), `UICorner` `UDim.new(0.5,0)`.
- `BackgroundColor3` base + `UIGradient` won't do radial; use a **radial orb PNG** (`ImageLabel`) tinted, OR a `Frame` with a radial highlight image on top.
  - HP: `radial(circle at 40% 30%, #d64a3a, #7a1810)` → orb art tinted red; ring `UIStroke` `#2e120c` 2px + soft outer glow (blood) + inner top highlight (light image at ~.3).
  - Mana: same with blue (`#3a7ac6 → #14306a`), ring `#0e1e34`.
- Center `TextLabel` `BodyBold`, value text with a dark `UIStroke` for legibility.
- To show fill %, clip the orb art with a bottom-anchored `Frame` + `UIGradient` `Transparency` mask, or a second darker orb revealed top-down.

### 6.8 Hotbar
- Bottom-center `UIListLayout` (horizontal, `Padding 6`) of 46–52px slots, each with a keybind label top-left (`Xs`, `#c8a878`) and optional cooldown overlay (dark `Frame` + big Display number). XP bar below: thin `Frame` + `UIGradient` `#8a6a1e→#e8b84f`, level number left, % right.

---

## 7. Icons

- All glyphs live in `assets/sprite.svg` as 24×24 symbols. **Roblox can't use SVG at runtime** — export each symbol to a **PNG** (recommend 256×256, white on transparent) and upload as an image asset.
- Tint at runtime with `ImageLabel.ImageColor3` (tier color, rarity text color, or trait identity hue). Because the source is white, any tint works.
- Keep a mapping module `ReplicatedStorage/UI/Icons.luau`:
  ```lua
  return {
    -- traits
    Bastion="rbxassetid://0", Warden="rbxassetid://0", Brawler="rbxassetid://0",
    Berserker="rbxassetid://0", Blademaster="rbxassetid://0", Scout="rbxassetid://0",
    Ranger="rbxassetid://0", Sniper="rbxassetid://0", Lynx="rbxassetid://0",
    Pyromancer="rbxassetid://0", Mystic="rbxassetid://0", Trapper="rbxassetid://0",
    -- items
    Chest="rbxassetid://0", Sword="rbxassetid://0", Shield="rbxassetid://0",
    Boots="rbxassetid://0", Helm="rbxassetid://0", Potion="rbxassetid://0",
    Ring="rbxassetid://0", Gem="rbxassetid://0", Scroll="rbxassetid://0",
    Staff="rbxassetid://0", Ration="rbxassetid://0", Coin="rbxassetid://0",
    -- shapes
    HexBorder="rbxassetid://0", HexFill="rbxassetid://0",
    RadialGlow="rbxassetid://0", Shadow9Slice="rbxassetid://0",
  }
  ```
  Fill the `0`s after uploading. (I can export the PNG set from the sprite on request.)
- **Currency `◈` and close `✕`** can stay as text glyphs (they render in the body font), or be swapped for images if the glyph is missing.

---

## 8. Screen layouts (anchors @ 1280×720)

Positions are from the mocks in `ui_kits/*/index.html`; treat them as the spec.

- **Inventory:** trait rail `x=16, y=26, w=210`; window `x=352, y=30, w=770, h=640`. Paperdoll column 308px on the left (avatar center as a `ViewportFrame` — see §10), 12 equipment slots around it; the 10-wide grid fills the right. Tooltip floats over the grid anchored to the hovered item.
- **HUD:** compact rail top-left (`x=20,y=20`); target plate top-center; `Inventory [B]` button top-right; HP orb bottom-left, mana orb bottom-right; hotbar + XP bar bottom-center.
- **Vendor:** window `x=170,y=66, 940×588`; title + Buy/Sell/Buyback tabs; stock grid (wrapping `UIGridLayout` of 64px tiles with a price tag) on the left, item-detail column 320px on the right with the buy button pinned bottom.
- **Character:** same window box; left 330px portrait column (name, class, XP, `ViewportFrame` avatar, equipped mini-row); right column = Attributes (2-col with `+` allocate buttons), Combat chips (4-col grid), Resistance chips (wrap), Active-Traits summary (wrap of tier-bordered rows).

---

## 9. Scaling & responsiveness

- Author everything at 1280×720 in offset units. Add a single `UIScale` on each window/HUD root and drive it:
  ```lua
  local function fit()
      local vp = workspace.CurrentCamera.ViewportSize
      scale.Scale = math.min(vp.X/1280, vp.Y/720)
  end
  workspace.CurrentCamera:GetPropertyChangedSignal("ViewportSize"):Connect(fit); fit()
  ```
- Orbs/hotbar can instead be anchored to screen corners with `AnchorPoint` and a smaller independent scale if you want them fixed-size on big screens.
- Set `ScreenGui.IgnoreGuiInset = true` so top-bar insets don't shift the layout.

---

## 10. The avatar (paperdoll & portrait)

The mocks draw a stylized blocky avatar with CSS. **In-engine, don't rebuild that** — use a `ViewportFrame` (or `WorldModel`) containing a clone of the player's `Character`/`HumanoidDescription`, lit warm from above to match the forge glow. The surrounding chrome, slot positions, sizes, and spacing in the mocks are the real spec; the figure itself is just a placeholder for the ViewportFrame.

---

## 11. Motion

- Use `TweenService`, `Theme`-level constants: duration **0.2s**, easing `Enum.EasingStyle.Quart`, `Enum.EasingDirection.Out` (matches `--ease-ui`). Fast state (hover) ~0.12s.
- Hover = brighten toward `AccentHi`; press = darken + 1px inset. **No bounce, no big slides** — heavy, grounded UI.
- Trait activation "pop": briefly scale the hex 1.0→1.15→1.0 and flash the border to the new tier color. Prismatic border rotates continuously.
- Window open/close: fade + 4–6px rise, 0.2s. Tooltip appears instantly (no tween) so it tracks the cursor cleanly.

---

## 12. Data shapes (suggested)

```lua
type Rarity = "Common"|"Uncommon"|"Rare"|"Epic"|"Legendary"
type Item = {
	id: string, name: string, icon: string, rarity: Rarity,
	slot: string, level: number, size: {w: number, h: number}, -- grid footprint
	stats: { {label: string, value: string} },
	grants: { {trait: string, points: number} },              -- trait points this item gives
	flavor: string?,
}
type Trait = {
	key: string, name: string, hue: Color3,
	breakpoints: {number},   -- e.g. {2,4,6,8} or {3,6,9} or {5,10,15}
	count: number,           -- current active count
}
-- tier is derived: how many breakpoints <= count →
--   0 = Inactive, then map count of reached breakpoints to Bronze/Silver/Gold,
--   final breakpoint = Prismatic.
```

`tierFor(trait)` = count how many `breakpoints[i] <= trait.count`; 0→Inactive, last→Prismatic, else Bronze/Silver/Gold by index. Keep the exact bronze/silver/gold cutoffs in one place so all three trait-row variants agree.

---

## 13. Build checklist

- [ ] `Theme.luau` + `Icons.luau` in `ReplicatedStorage/UI`
- [ ] Export the 12 trait + 12 item glyphs, hexagon border/fill, radial glow, 9-slice shadow → upload → fill `Icons.luau`
- [ ] Confirm `GrenzeGotisch` + `Merriweather` in the Studio font picker (else self-host)
- [ ] Reusable widgets: `Panel`, `ItemSlot`, `HexBadge`, `TraitRow` (3 variants), `Tooltip`, `Button`, `Orb`
- [ ] Three `ScreenGui` layers (HUD / Windows / Tooltip) with the DisplayOrders in §1
- [ ] `UIScale` fit on each root
- [ ] Grid = `UIGridLayout` 42px; items absolute-positioned over it
- [ ] Avatar via `ViewportFrame`, not CSS blocks
- [ ] Tooltip cursor-follow + screen clamp
- [ ] Sanity pass: **no `UICorner` except orbs (0.5) & chips (6)**; every border is a `UIStroke`; every gradient a `UIGradient`

---

### Open items for the designer
- **Real names** for game/class/locations (currently placeholders).
- **Logo / brand mark** (none provided — title currently renders in the display font).
- Want the **PNG icon set exported** from `assets/sprite.svg` at upload resolution? Say the word.
- Self-hosted **font `.ttf`s** if you don't want to depend on the native Roblox fonts.
