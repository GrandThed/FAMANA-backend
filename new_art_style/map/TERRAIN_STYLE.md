# FAMANA Map Terrain — Recipe (Path A: scripted voxel terrain)

DECIDED 2026-07-20: game terrain is **native Roblox voxel terrain generated
in Luau** — `roblox/src/shared/TerrainGen.lua`, run at server boot for cell
places (see `init.server.lua`). Blender is no longer used for terrain; the
earlier Blender/low-poly-mesh exploration (faceted grids, hero renders, the
mesh-terrain + WaterSpans experiment) has been removed. What survives from
it is this recipe: the height field, the color palette, and the zone rules,
all implemented by `TerrainGen`.

## References

`reference/` keeps the style references (terrain colors, mountain look,
the celled world-map sketches). They guided the palette below.

## Delivery model

- **One world-space height field, sliced per cell.** Geography is
  hand-authored data in `roblox/src/shared/WorldMap.lua` (translated from
  the user's painted zone map — coast polygons, hill bands, the village
  plateau, fords, per-cell world windows). Cells are NOT uniform squares:
  each declares its own window (center + size in studs), and
  `TerrainGen.generateCell()` samples the shared field through it —
  `math.noise` + shared data → neighboring cells seam by construction.
  Design shorthand: 1 stud ≈ 1 m; cell A's village zone is ~300 m across.
- **Regenerated every boot, never persisted.** The map pull/deploy pipeline
  (`scripts/pull-maps.mjs`) keeps only `Workspace.Map`, so persisted voxels
  would be lost anyway. Deterministic regeneration makes that a non-issue.
- **Walkability guards:** the cell center and each border entry point get
  smoothstep-flattened discs (4 studs high) so spawns and the
  `BorderService` handoff (`ENTRY_Y`) always land on open ground.
- Edit-time preview (Rojo connected, command bar):
  `require(game.ReplicatedStorage.Shared.TerrainGen).generateCell()`.
  NOTE: Play regenerates the current place's cell at boot, wiping edit-mode
  previews for the session. To steer what Play builds, set the Workspace
  attributes `TerrainCell` (string, e.g. "B") and/or `TerrainSize` (studs).

## Elevation (recipe units; 1 unit = `SCALE` = 3 studs, water = 0)

```
h  = 6.0 * fbm(x, y, scale=0.018)          -- rolling meadows (5 octaves)
   + 1.8 * fbm(x+100, y-50, scale=0.06)    -- fine detail layer
   + 2.2                                    -- bias so most land sits above water

h -= 8.0 * smoothstep(1 - dist(lake_center)/41)     -- carved lake (southwest)

edge = 25 + 10*fbm(x*0.5, 777, 0.02)                -- mountain wall (north)
h   += smoothstep((y-edge)/45) * (30*ridged(x,y,0.03) + 8)
```

- `fbm` = 5-octave fractal noise (lacunarity 2, gain 0.5, normalized).
- `ridged` = ridged multifractal (per octave `n=(1-|noise|)²` weighted by the
  previous octave) — jagged creased mountains; plain fbm gives smooth hills.
- Lakes are **carved deliberately** (radial basins), never left to noise —
  noise-only produces scattered accidental ponds.
- World layout today: meadows at the origin cell, lake to the southwest,
  mountain range across the north. Far-north cells are alpine.

## Palette (terrain material tints, `SetMaterialColor`)

| Material | RGB           | Zone                         |
| -------- | ------------- | ---------------------------- |
| Grass    | 115, 178, 77  | meadows (uniform mid-green)  |
| Ground   | 168, 130, 87  | steep low slopes (dirt)      |
| Rock     | 158, 145, 128 | steep high slopes, mountains |
| Snow     | 245, 245, 252 | gentle facets above snowline |
| Sand     | 230, 204, 145 | shorelines                   |
| Mud      | 140, 140, 97  | lakebeds (olive)             |
| Water    | 61, 158, 158  | teal, transparency 0.2       |

Grass is deliberately **uniform** (decided 2026-07-20): one mid-green tint,
no patchwork — variation comes from lighting and material texture, not hue.

## Zone rules (per column; z in units, slope = |∇h|)

1. `z < −1` → Mud (lakebed).
2. `z < 0.9 + 0.5·n_band` → Sand (`n_band` = fbm scale 0.03 — wobbles every
   boundary so lines are never straight).
3. `z > rock_line (= 13 + 4·n_band)` → Rock; above
   `snow_line (= 26 + 3·n_band)` with slope < 1.2 → Snow (steep faces stay
   rock, snow only caps walkable-ish ground).
4. Otherwise Grass; slope > 1.4 → Ground below z=6, Rock above.

## Open knobs

- **Cell size** — cells are currently `GridConfig.HALF*2` = 80 studs; one
  cell sees a small patch of the world. Either grow `HALF` or shrink
  `SCALE` if features feel too large at play scale.
- **World layout authoring** — `heightU` is pure noise + two hand-placed
  features. A per-cell feature mask (deliberate lakes/rivers/biomes on the
  world map) can layer on later without breaking seams, as long as it stays
  a function of world coordinates.
- **Authored-map integration** — the existing authored Maps sit on flat
  ground; decide per cell whether the map's ground plane or the generated
  terrain is the floor.
