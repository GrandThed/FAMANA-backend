# Low-Poly Tree Asset Pack

A set of four game-ready, low-poly stylized trees, procedurally built in Blender (via the Blender MCP) from two AI-generated concept images in this folder.

![Family preview](SM_Trees_Family_preview.png)

## Style

Taken from the concept references, minus the cel-shading:

- **Faceted geometry** — large flat polygons, sharp edges, no smoothing (flat shading everywhere)
- **Flat color planes** — plain Principled BSDF base colors, high roughness, low specular; no textures needed
- **No outlines** — the bold black cel-shaded edges from the concepts were intentionally left out

## Assets

| File | Description | Tris | Height |
|------|-------------|------|--------|
| `SM_Tree_LowPoly` | Oak (reference) — green canopy, 4 leaf tones | 2,668 | ~4.5 m |
| `SM_Tree_Oak_Autumn` | Oak (autumn) — rust/orange/amber/gold canopy + 16 fallen leaves at the base | 2,700 | ~4.5 m |
| `SM_Tree_Conifer_Winter` | Conifer (winter) — 9 star-shaped drooping tiers, snow clumps + base mound | 520 | ~6.7 m |
| `SM_Tree_Gnarled_Dead` | Gnarled (dead) — twisted leafless limbs, cool grey bark | 3,719 | ~4.3 m |

Each asset ships as **`.glb`** (materials embedded — drop straight into Godot/Unity/Unreal) and **`.fbx`**.

## Variants (`variants/`)

Five variants of each type live in the `variants/` folder (GLB + FBX each, 40 files), so scattered trees don't read as copies. All share the root assets' materials, style, and game-ready checklist. Since every builder is seeded and parameterized, the differences are structural — not just rotations:

| Set | Files | What varies | Tris |
|-----|-------|-------------|------|
| Oak (green) | `SM_Tree_Oak_Green_01–05` | branch layout, height (±12%), canopy width, blob count, trunk lean, leaf-tone mix | 1.9k–2.4k |
| Oak (autumn) | `SM_Tree_Oak_Autumn_01–05` | same as green, plus palette bias (rust-heavy ↔ golden) and fallen-leaf scatter | 2.2k–2.5k |
| Conifer (winter) | `SM_Tree_Conifer_Winter_01–05` | height (5.6–7.6 m), tier count (7–10), base radius, snow amount (light dusting ↔ heavy) | 300–604 |
| Gnarled (dead) | `SM_Tree_Gnarled_Dead_01–05` | size (±15%), limb count (3–5), fork depth, crookedness | 1.3k–4.5k |

Contact-sheet renders of each set: `variants/_preview_<Type>.png`.

### Game-ready checklist (applies to all)

- Single mesh per tree, no modifiers, identity transforms
- Origin at the base of the trunk; lowest vertices sit exactly on z = 0 (flat ground contact)
- Flat-shaded polygons (facet look comes from the normals, not textures)
- UV-unwrapped (Smart UV Project) — ready for lightmaps or texture painting
- Simple flat-color materials, shared across the set where possible

### Materials

| Material | Used by | Color |
|----------|---------|-------|
| `M_Tree_Bark` | both oaks | dark brown `#3E2A1E` |
| `M_Tree_Leaf_Dark/Mid/Light/Pale` | green oak | greens `#39572A` → `#8FB44A` |
| `M_Tree_Leaf_Rust/Orange/Amber/Gold` | autumn oak | `#A84B28` → `#D4B040` |
| `M_Tree_PaleWood` | conifer trunk | grey-beige `#B0A691` |
| `M_Tree_Pine_Dark/Mid` | conifer tiers | teal greens `#3B6653`, `#4E7F66` |
| `M_Tree_Snow` | conifer snow | white `#EDF2F6` |
| `M_Tree_DeadBark` | dead tree | cool grey `#525459` |

## Enemies

Three enemy assets from the `enemies.png` concept, in the same faceted flat-color style (no cel shading):

![Enemies preview](SM_Enemies_preview.png)

| File | Description | Tris | Height |
|------|-------------|------|--------|
| `SM_Enemy_Moss_Goblin` | Green goblin — spiked helmet, leather vest + belt, loincloth, wooden club in right hand | 804 | ~1.3 m |
| `SM_Enemy_Rock_Golem` | Hulking boulder body, moss on all upward-facing rock surfaces, emissive glowing eyes | 1,240 | ~2.1 m |
| `SM_Enemy_Cave_Spider` | Dark faceted abdomen, tan cephalothorax, 6 bead eyes, fangs, 8 angular two-segment legs | 2,528 | ~1.0 m |

Same game-ready checklist as the trees (single mesh, origin at feet on z = 0, flat shading, UVs, GLB + FBX). Enemy materials are prefixed `M_Enemy_*`; the golem's eyes use an emissive material (`M_Enemy_GlowEyes`). The golem's moss is assigned by face normal — any rock face pointing up became moss — so it stays consistent from every angle.

**Rigging note:** the enemy GLB/FBX files in this folder are static meshes. All three enemies also have **rigged and animated Roblox versions** in `roblox/` — skinned rigs with palette textures and Idle/Walk/Attack clips as FBX, plus `ROBLOX.md` with the full Studio import guide (goblin: 11 bones, golem: 10, spider: 19 with two-bone leg chains).

## How they were built

All geometry was generated procedurally with Python inside Blender:

- **Oaks** — a branching edge skeleton (trunk, 5 main branches, sub-branches, root flares) skinned with the Skin modifier, then vertex-jittered for irregular facets. Foliage is ~21 icospheres (2 subdivisions) with random rotation, non-uniform squash, and jitter, in 4 leaf tones. The autumn oak is the same mesh with swapped leaf materials plus flat diamond quads scattered as fallen leaves.
- **Conifer** — a 6-sided tapered trunk column with stacked 6-point star "skirt" tiers (long points drooping down), and flattened 1-subdivision icospheres as snow.
- **Dead tree** — a recursive zigzag branch-growing function (each segment kinks and forks) skinned the same way as the oaks, scaled and colored to the concept.

Randomness is seeded, so the builds are reproducible.

## Other files

- `Gemini_Generated_Image_i7khaai7khaai7kh.png` — concept: green oak + style detail
- `Gemini_Generated_Image_zeoji3zeoji3zeoj.png` — concept: the four-variant lineup
- `SM_Tree_LowPoly_preview.png` — render of the green oak alone
- `SM_Trees_Family_preview.png` — render of all four variants

*Previews were rendered in Blender (Eevee) with a preview-only camera, sun light, and ground plane — none of those are included in the exports.*
