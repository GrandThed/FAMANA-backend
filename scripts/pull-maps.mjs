// Pulls each live place's authored Map folder AND hand-sculpted Terrain down
// into roblox/maps/ so Studio stays the source of truth for world content
// while git stays the source of truth for code. deploy-places.mjs calls
// pullMap() before every build; this file is also runnable standalone to
// refresh maps without deploying:
//
//   node scripts/pull-maps.mjs           # pull every place in places.json
//   node scripts/pull-maps.mjs cellA     # only the named place(s)
//
// How a pull works:
//   1. Download the live place file via the Open Cloud Asset Delivery API
//      (the ROBLOX_API_KEY needs legacy-assets:manage).
//   2. `rojo syncback` runs with WORKSPACE anchored to a scratch directory,
//      which makes every Workspace child — including Map — serialize as one
//      opaque .rbxm file (no naming constraints INSIDE Map this way; rojo
//      only requires unique names among instances it maps to project nodes,
//      and here that's just Workspace's direct children). The script then
//      keeps Map.rbxm as roblox/maps/<name>.rbxm and Terrain.rbxm (the
//      hand-sculpted voxel terrain + its material tints) as
//      roblox/maps/<name>.terrain.rbxm, discarding the rest (Baseplate, …).
//      The per-place projects mount both files back as Workspace.Map /
//      Workspace.Terrain, so the next build reproduces the live world exactly.
//
// A live place WITHOUT a Map folder removes roblox/maps/<name>.rbxm (the
// game then runs on the def-`spots` fallback, same as pre-map days). Maps
// are gitignored — they're pulled artifacts, not sources. Rollback for maps
// = the place's version history on the Creator Dashboard.

import fs from "node:fs";
import path from "node:path";
import { spawnSync } from "node:child_process";
import { fileURLToPath, pathToFileURL } from "node:url";

const ROOT = path.resolve(path.dirname(fileURLToPath(import.meta.url)), "..");
const ROBLOX_DIR = path.join(ROOT, "roblox");
const BUILD_DIR = path.join(ROBLOX_DIR, "build");
const MAPS_DIR = path.join(ROBLOX_DIR, "maps");

// Downloads the current live place file. Returns the path to it.
async function downloadPlace(name, placeId, apiKey) {
  const meta = await fetch(`https://apis.roblox.com/asset-delivery-api/v1/assetId/${placeId}`, {
    headers: { "x-api-key": apiKey },
  });
  if (meta.status === 401 || meta.status === 403) {
    throw new Error(
      `HTTP ${meta.status} downloading the place — the API key is missing the asset-download permission.\n` +
        "    Creator Dashboard → Open Cloud → API Keys → your key → Access Permissions →\n" +
        "    add the 'Legacy Assets' API system with its 'manage' operation (legacy-assets:manage)\n" +
        "    and save. The key value doesn't change."
    );
  }
  if (!meta.ok) {
    throw new Error(`asset-delivery HTTP ${meta.status}: ${await meta.text()}`);
  }
  const body = await meta.json();
  if (body.IsCopyrightProtected) {
    throw new Error("place is copyright-protected — cannot download");
  }
  if (!body.location) {
    throw new Error(`asset-delivery returned no download location: ${JSON.stringify(body)}`);
  }
  const file = await fetch(body.location);
  if (!file.ok) {
    throw new Error(`place download HTTP ${file.status}`);
  }
  fs.mkdirSync(BUILD_DIR, { recursive: true });
  const out = path.join(BUILD_DIR, `${name}.live.rbxl`);
  fs.writeFileSync(out, Buffer.from(await file.arrayBuffer()));
  return out;
}

// Extracts Workspace.Map from `placeFile` into roblox/maps/<name>.rbxm via
// rojo syncback. Returns "pulled" or "no-map" (live place carries no Map —
// the map file is removed so builds fall back to def spots). Throws on
// anything else.
function extractMap(name, placeFile) {
  const outDir = path.join(BUILD_DIR, `${name}.pull`);
  fs.rmSync(outDir, { recursive: true, force: true });
  fs.mkdirSync(outDir, { recursive: true });

  const project = path.join(BUILD_DIR, `${name}.pull.project.json`);
  fs.writeFileSync(
    project,
    JSON.stringify({
      name: `pull-${name}`,
      tree: {
        $className: "DataModel",
        Workspace: { $path: `${name}.pull` },
      },
    })
  );

  const result = spawnSync(
    "rojo",
    ["syncback", project, "--input", placeFile, "--non-interactive"],
    { cwd: ROBLOX_DIR, encoding: "utf8" }
  );
  if (result.error && result.error.code === "ENOENT") {
    throw new Error("rojo not found on PATH — run `rokit install` in roblox/ first");
  }
  const stderr = result.stderr || "";
  if (stderr.includes("must have a unique name")) {
    const detail = stderr
      .split("\n")
      .filter((line) => line.includes("duplicated"))
      .map((line) => line.trim())
      .join("\n    ");
    throw new Error(
      "instances sitting DIRECTLY under Workspace (outside Map) share a name — Rojo can't\n" +
        "    extract that. In Studio, delete stray objects loose in Workspace (leftover test\n" +
        "    models, unparented parts…) or move them inside Map, then Publish and retry.\n" +
        `    ${detail || stderr.trim().split("\n").slice(-2).join("\n    ")}`
    );
  }
  if (result.status !== 0 || stderr.includes("[ERROR")) {
    throw new Error(`rojo syncback failed:\n${stderr || result.stdout}`);
  }

  // Terrain: always emitted by syncback (the instance always exists) — an
  // unsculpted place just yields a tiny empty-grid rbxm. Same optional-mount
  // contract as Map.
  const pulledTerrain = path.join(outDir, "Terrain.rbxm");
  const destTerrain = path.join(MAPS_DIR, `${name}.terrain.rbxm`);
  fs.mkdirSync(MAPS_DIR, { recursive: true });
  if (fs.existsSync(pulledTerrain)) {
    fs.copyFileSync(pulledTerrain, destTerrain);
  } else {
    fs.rmSync(destTerrain, { force: true });
  }

  const pulled = path.join(outDir, "Map.rbxm");
  const dest = path.join(MAPS_DIR, `${name}.rbxm`);
  if (!fs.existsSync(pulled)) {
    // No Workspace.Map in the live place: legitimate (pre-map place, or the
    // map was deliberately deleted). Removing the file makes the optional
    // mount skip Map entirely -> services use their def-spots fallback.
    fs.rmSync(dest, { force: true });
    return "no-map";
  }
  fs.copyFileSync(pulled, dest);
  return "pulled";
}

// Pull one place's map. Returns "pulled" | "no-map"; throws on failure.
// Deploys treat a throw as fatal FOR THAT PLACE: building without the live
// map would overwrite it, which is the one thing this pipeline must never do.
export async function pullMap(name, placeId, apiKey) {
  const placeFile = await downloadPlace(name, placeId, apiKey);
  return extractMap(name, placeFile);
}

// ---- standalone CLI ---------------------------------------------------------

const isMain =
  process.argv[1] && import.meta.url === pathToFileURL(path.resolve(process.argv[1])).href;

if (isMain) {
  const envFile = path.join(ROOT, ".env");
  if (fs.existsSync(envFile)) {
    for (const line of fs.readFileSync(envFile, "utf8").split(/\r?\n/)) {
      const match = line.match(/^\s*([A-Za-z_][A-Za-z0-9_]*)\s*=\s*(.*?)\s*$/);
      if (match && process.env[match[1]] === undefined) {
        process.env[match[1]] = match[2].replace(/^["']|["']$/g, "");
      }
    }
  }
  const apiKey = process.env.ROBLOX_API_KEY;
  if (!apiKey) {
    console.error("Missing ROBLOX_API_KEY — set it in the repo-root .env.");
    process.exit(1);
  }
  const manifest = JSON.parse(fs.readFileSync(path.join(ROBLOX_DIR, "places.json"), "utf8"));
  const requested = process.argv.slice(2).filter((a) => !a.startsWith("--"));
  const names = requested.length > 0 ? requested : Object.keys(manifest.places);

  let failed = 0;
  for (const name of names) {
    const place = manifest.places[name];
    if (!place) {
      console.error(`Unknown place: ${name}`);
      failed += 1;
      continue;
    }
    process.stdout.write(`- ${name} (${place.placeId}): `);
    try {
      const status = await pullMap(name, place.placeId, apiKey);
      console.log(status === "pulled" ? `map pulled into roblox/maps/${name}.rbxm` : "live place has no Map folder");
    } catch (error) {
      failed += 1;
      console.log(`FAILED — ${error.message}`);
    }
  }
  if (failed > 0) process.exit(1);
}
