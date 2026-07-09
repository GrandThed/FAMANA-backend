// Builds every place from the repo with Rojo and publishes it to Roblox via
// the Open Cloud Place Publishing API — code changes reach ALL places in one
// command, no Studio session needed. Which places exist (and their per-place
// project files + authored maps) is driven by roblox/places.json.
//
// A deploy REPLACES the whole place file. Everything a place needs must
// therefore live in the repo: code (src/), the authored map
// (roblox/maps/<name>.rbxm — see docs/MAP_AUTHORING.md) and place settings
// (the per-place *.project.json). Anything edited only in Studio and never
// exported is overwritten.
//
// Setup (once): create an API key at create.roblox.com → Open Cloud →
// API Keys, add the "universe-places" system with the Write operation for
// this experience (scope universe-places:write), and allow your IP (or
// 0.0.0.0/0). Set universeId in roblox/places.json (Studio command bar:
// print(game.GameId)).
//
// The key: put `ROBLOX_API_KEY=<key>` in a `.env` file at the repo root
// (gitignored — never committed), or set it per session in PowerShell:
//   $env:ROBLOX_API_KEY = "<key>"
//
// Usage:
//   node scripts/deploy-places.mjs            # build + publish everything
//   node scripts/deploy-places.mjs cellA      # only the named place(s)
//   node scripts/deploy-places.mjs --draft    # upload as Saved, not Published
//
// Requires Node 18+ and rojo on PATH (rokit install in roblox/).

import fs from "node:fs";
import path from "node:path";
import { spawnSync } from "node:child_process";
import { fileURLToPath } from "node:url";

const ROOT = path.resolve(path.dirname(fileURLToPath(import.meta.url)), "..");
const ROBLOX_DIR = path.join(ROOT, "roblox");
const BUILD_DIR = path.join(ROBLOX_DIR, "build");
const MANIFEST = path.join(ROBLOX_DIR, "places.json");
const SECRET = path.join(ROBLOX_DIR, "src", "server", "Secret.lua");

// Load the repo-root .env (gitignored) so the key survives across terminal
// sessions; real environment variables win over the file.
const envFile = path.join(ROOT, ".env");
if (fs.existsSync(envFile)) {
  for (const line of fs.readFileSync(envFile, "utf8").split(/\r?\n/)) {
    const match = line.match(/^\s*([A-Za-z_][A-Za-z0-9_]*)\s*=\s*(.*?)\s*$/);
    if (match && process.env[match[1]] === undefined) {
      process.env[match[1]] = match[2].replace(/^["']|["']$/g, "");
    }
  }
}

const API_KEY = process.env.ROBLOX_API_KEY;
if (!API_KEY) {
  console.error(
    "Missing ROBLOX_API_KEY (Open Cloud key with universe-places:write) — " +
      "put ROBLOX_API_KEY=<key> in a .env file at the repo root, or set the env var."
  );
  process.exit(1);
}

// Secret.lua is gitignored but required — a place built without it can't
// reach the backend and every player would get a temporary profile.
if (!fs.existsSync(SECRET)) {
  console.error(`Missing ${SECRET} — recreate it before deploying (see CLAUDE.md gotchas).`);
  process.exit(1);
}

const manifest = JSON.parse(fs.readFileSync(MANIFEST, "utf8"));
if (!manifest.universeId) {
  console.error(
    "universeId is 0 in roblox/places.json — set it first (Studio command bar: print(game.GameId))."
  );
  process.exit(1);
}

const args = process.argv.slice(2);
const draft = args.includes("--draft");
const requested = args.filter((arg) => !arg.startsWith("--"));
const unknown = requested.filter((name) => !manifest.places[name]);
if (unknown.length > 0) {
  console.error(`Unknown place(s): ${unknown.join(", ")} — names in roblox/places.json: ${Object.keys(manifest.places).join(", ")}`);
  process.exit(1);
}
const selected = requested.length > 0 ? requested : Object.keys(manifest.places);
const versionType = draft ? "Saved" : "Published";

const sleep = (ms) => new Promise((resolve) => setTimeout(resolve, ms));

async function robloxFetch(url, options, attempt = 0) {
  const response = await fetch(url, {
    ...options,
    headers: { "x-api-key": API_KEY, ...(options.headers || {}) },
  });
  if (response.status === 429 && attempt < 5) {
    const wait = Number(response.headers.get("retry-after") || 5) * 1000;
    console.log(`  … rate limited, retrying in ${wait / 1000}s`);
    await sleep(wait);
    return robloxFetch(url, options, attempt + 1);
  }
  // 409 "Server is busy" is transient (often right after a Studio session on
  // the place) — Roblox itself says to retry in a couple of minutes.
  if (response.status === 409 && attempt < 3) {
    console.log("  … server busy (409), retrying in 45s");
    await sleep(45000);
    return robloxFetch(url, options, attempt + 1);
  }
  return response;
}

function build(name, project) {
  const output = path.join(BUILD_DIR, `${name}.rbxl`);
  const result = spawnSync("rojo", ["build", project, "--output", output], {
    cwd: ROBLOX_DIR,
    encoding: "utf8",
  });
  if (result.error && result.error.code === "ENOENT") {
    throw new Error("rojo not found on PATH — run `rokit install` in roblox/ first");
  }
  if (result.status !== 0) {
    throw new Error(`rojo build failed:\n${result.stderr || result.stdout}`);
  }
  return output;
}

async function publish(placeId, file) {
  const url =
    `https://apis.roblox.com/universes/v1/${manifest.universeId}` +
    `/places/${placeId}/versions?versionType=${versionType}`;
  const response = await robloxFetch(url, {
    method: "POST",
    headers: { "Content-Type": "application/octet-stream" },
    body: fs.readFileSync(file),
  });
  if (!response.ok) {
    throw new Error(`publish HTTP ${response.status}: ${await response.text()}`);
  }
  const { versionNumber } = await response.json();
  return versionNumber;
}

fs.mkdirSync(BUILD_DIR, { recursive: true });

let failed = 0;
for (const name of selected) {
  const { placeId, project } = manifest.places[name];
  try {
    process.stdout.write(`- ${name} (${placeId}): building… `);
    const file = build(name, project);
    process.stdout.write(`${versionType.toLowerCase()}… `);
    const version = await publish(placeId, file);
    console.log(`v${version}`);
  } catch (error) {
    failed += 1;
    console.log(`FAILED — ${error.message}`);
  }
}

console.log(`\nDone: ${selected.length - failed} deployed, ${failed} failed.`);
if (!draft && failed === 0) {
  console.log("Live servers keep running the old version until they empty; new servers get the new one.");
}
if (failed > 0) {
  process.exit(1);
}
