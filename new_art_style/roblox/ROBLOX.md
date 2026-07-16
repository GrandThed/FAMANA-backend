# Roblox Studio Integration Guide

How to get the animated enemies (and the rest of the asset pack) into Roblox Studio.

## Files in this folder

All three enemies follow the same pattern: one rigged model FBX + three animation FBXs + a palette PNG (also embedded in the FBXs).

| Enemy | Model | Animations | Notes |
|-------|-------|------------|-------|
| Moss Goblin | `Goblin_Model.fbx` (11 bones) | `Goblin_Anim_Idle/Walk/Attack.fbx` | Attack = club swing with lunge |
| Rock Golem | `Golem_Model.fbx` (10 bones) | `Golem_Anim_Idle/Walk/Attack.fbx` | Attack = two-fist overhead slam; slow stomping walk |
| Cave Spider | `Spider_Model.fbx` (19 bones) | `Spider_Anim_Idle/Walk/Attack.fbx` | Walk = fast alternating-tetrapod scuttle; Attack = rear-up threat + strike |

Suggested File Scale at import: **3.0** for all (goblin ≈ 4 studs, golem ≈ 6.3 studs, spider ≈ 3 studs tall / ~7.5 studs leg span).

## 1. Import the rigged model

1. In Studio: **Avatar tab → 3D Importer** (or Home → Import 3D) → select `Goblin_Model.fbx`.
2. In the import preview:
   - **File Scale ≈ 3.0** — the goblin is authored 1.3 m tall; ×3 makes him ~4 studs, a good enemy size next to R15 characters (~5 studs). Adjust to taste, but **use the same scale for every goblin file**.
   - Rig should be auto-detected (bones appear in the hierarchy). Leave "Rig Type" as **General/Custom** — this is not an R15 avatar.
   - The palette texture is embedded and should show on the preview. If not, upload `GoblinPalette.png` as an Image asset and set it as the MeshPart's `TextureID` (or a `SurfaceAppearance.ColorMap`).
3. Insert. You get a `Model` containing a skinned `MeshPart` with `Bone` instances inside.

## 2. Set up for animation

Inside the imported model add:
- **AnimationController** with an **Animator** inside it (for an NPC enemy — no Humanoid needed), and
- anchor the root or weld it to whatever moves the enemy (your choice of movement system).

## 3. Import + publish the animation clips

For each of the three animation FBX files:

1. **Avatar tab → Animation Editor**, select the goblin model in the workspace.
2. In the editor: **… (menu) → Import → From FBX Animation** → pick e.g. `Goblin_Anim_Idle.fbx`. The keyframes map onto the rig's bones by name.
3. For **Idle** and **Walk**: toggle **looping** on in the editor. For **Attack**: leave looping off and set its priority to **Action** (Walk = Movement, Idle = Idle) so the swing overrides locomotion.
4. **File → Publish to Roblox** → copy the **Animation asset ID**.

## 4. Play the animations from a script

`Script` inside the goblin model:

```lua
local model = script.Parent
local animator = model.AnimationController.Animator

local function load(id, looped, priority)
    local anim = Instance.new("Animation")
    anim.AnimationId = "rbxassetid://" .. id
    local track = animator:LoadAnimation(anim)
    track.Looped = looped
    track.Priority = priority
    return track
end

local idle   = load(IDLE_ID,   true,  Enum.AnimationPriority.Idle)
local walk   = load(WALK_ID,   true,  Enum.AnimationPriority.Movement)
local attack = load(ATTACK_ID, false, Enum.AnimationPriority.Action)

idle:Play()
-- in your AI: walk:Play() when moving, walk:Stop() when idle,
-- attack:Play() when in range (it auto-stops; non-looped)
```

Replace `IDLE_ID` etc. with the asset IDs from step 3.

## Importing the trees & other enemies (static meshes)

- Use the same **3D Importer** with the `.fbx` files from the main folder / `variants/`. They're static MeshParts — no rig needed. All are well under Roblox's 10k-triangle MeshPart limit.
- The flat-color materials import as separate MeshParts per material with their colors. If you'd rather have **one MeshPart per tree** (better for streaming/instancing), ask for palette-atlas versions like the goblin — the same baking step works for every asset in the pack.
- Suggested File Scale: **3.0** for everything, to keep the world consistent (oak ≈ 13.5 studs tall).

## Notes / gotchas

- **Scale consistency matters**: the model and its animation FBXs must be imported at the same File Scale, or root-motion bobs will be off.
- The rig uses **rigid per-piece skinning** (every vertex weighted 100% to one bone). This is intentional — zero deformation artifacts on the chunky low-poly style, and it keeps the skinned mesh cheap.
- Bone names — Goblin: `Root, Hips, Torso, Head, UpperArmL/R, ForearmL/R, LegL/R, Club` (club has its own bone, child of `ForearmL`, so you can animate twirls/drops in the Roblox Animation Editor later). Golem: `Root, Hips, Torso, Head, UpperArmL/R, ForearmL/R, LegL/R`. Spider: `Root, Body, Abdomen`, plus `Leg1LA/Leg1LB … Leg4RA/Leg4RB` (legs numbered front→back, A = hip-to-knee, B = knee-to-foot).
- The golem and spider use **island-rigid skinning** — every rock/leg piece is bound whole to one bone, so nothing tears no matter how far you push new poses.
- Roblox can't run custom vertex shaders, so **tree wind sway** isn't available the way it is in other engines. Options: leave trees static (normal for Roblox), or add a very subtle scripted rotation via TweenService on special "hero" trees only.
