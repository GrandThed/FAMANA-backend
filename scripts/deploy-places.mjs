// Builds every place from the repo with Rojo and publishes it to Roblox via
// the Open Cloud Place Publishing API — code changes reach ALL places in one
// command, no Studio session needed. Which places exist (and their per-place
// project files + authored maps) is driven by roblox/places.json. Full
// pipeline design: docs/DEPLOYMENT.md.
//
// A deploy REPLACES the whole place file — but the authored map survives:
// right before building, each place's live Map folder is PULLED down from
// Roblox (scripts/pull-maps.mjs) into roblox/maps/<name>/ and built back in.
// Studio is the source of truth for maps; git is the source of truth for
// code and place settings (the per-place *.project.json). See
// docs/MAP_AUTHORING.md.
//
// What a run does:
//   1. Guards: repo must be clean (--force overrides; drafts only warn) and
//      Secret.lua must exist (the built place needs the backend key).
//   2. Stamps src/shared/BuildInfo.lua with the git commit + timestamp for
//      the duration of the build, restoring the checked-in version after.
//   3. Pulls each place's live map (skippable with --no-pull). A FAILED pull
//      fails that place's deploy — building without the live map would
//      overwrite it, the one thing this pipeline must never do.
//   4. rojo-builds each place and POSTs it to Open Cloud.
//   5. Records each publish in the backend deploy ledger (POST /deploys) and
//      notes when Roblox's version number jumped more than +1 since the last
//      recorded deploy (Studio sessions — normal for map work, which was
//      just pulled into this very build).
//   6. With --restart (and zero failures): one restartServers call migrates
//      live servers that run outdated versions to the newest one.
//
// Keys: ROBLOX_API_KEY (Open Cloud: universe-places:write, asset-delivery
// read for the map pull, plus universe write for --restart) in a repo-root
// .env file (gitignored) or the env. The backend ledger authenticates with
// FAMANA_API_KEY if set, else the key is read from roblox/src/server/Secret.lua.
//
// Usage:
//   node scripts/deploy-places.mjs            # build + publish everything
//   node scripts/deploy-places.mjs cellA      # only the named place(s)
//   node scripts/deploy-places.mjs --draft    # upload as Saved, not Published
//   node scripts/deploy-places.mjs --restart  # migrate live servers after
//   node scripts/deploy-places.mjs --force    # deploy despite a dirty tree
//   node scripts/deploy-places.mjs --no-pull  # build with maps already on disk
//
// Requires Node 18+ and rojo on PATH (rokit install in roblox/).

import fs from "node:fs";
import path from "node:path";
import { spawnSync } from "node:child_process";
import { fileURLToPath } from "node:url";
import { pullMap } from "./pull-maps.mjs";

const ROOT = path.resolve(path.dirname(fileURLToPath(import.meta.url)), "..");
const ROBLOX_DIR = path.join(ROOT, "roblox");
const BUILD_DIR = path.join(ROBLOX_DIR, "build");
const MANIFEST = path.join(ROBLOX_DIR, "places.json");
const SECRET = path.join(ROBLOX_DIR, "src", "server", "Secret.lua");
const BUILDINFO = path.join(ROBLOX_DIR, "src", "shared", "BuildInfo.lua");

// Load the repo-root .env (gitignored) so keys survive across terminal
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

// The backend ledger authenticates with the game's API key: FAMANA_API_KEY
// env if set (CI), else parsed out of Secret.lua (local).
const FAMANA_API_KEY =
  process.env.FAMANA_API_KEY ||
  (fs.readFileSync(SECRET, "utf8").match(/return\s*"([^"]+)"/) || [])[1] ||
  null;

const manifest = JSON.parse(fs.readFileSync(MANIFEST, "utf8"));
if (!manifest.universeId) {
  console.error(
    "universeId is 0 in roblox/places.json — set it first (Studio command bar: print(game.GameId))."
  );
  process.exit(1);
}

const args = process.argv.slice(2);
const draft = args.includes("--draft");
const restart = args.includes("--restart");
const force = args.includes("--force");
const noPull = args.includes("--no-pull");
const requested = args.filter((arg) => !arg.startsWith("--"));
const unknown = requested.filter((name) => !manifest.places[name]);
if (unknown.length > 0) {
  console.error(
    `Unknown place(s): ${unknown.join(", ")} — names in roblox/places.json: ${Object.keys(manifest.places).join(", ")}`
  );
  process.exit(1);
}
const selected = requested.length > 0 ? requested : Object.keys(manifest.places);
const versionType = draft ? "Saved" : "Published";

function git(...gitArgs) {
  const result = spawnSync("git", gitArgs, { cwd: ROOT, encoding: "utf8" });
  return result.status === 0 ? result.stdout.trim() : null;
}

// Deploy what git has, not whatever happens to be on disk: a dirty tree means
// the published build can't be reproduced from a commit.
const dirty = git("status", "--porcelain", "--", "roblox", "scripts");
if (dirty) {
  if (draft || force) {
    console.warn("! Working tree is dirty — this build is not reproducible from a commit:");
    console.warn(dirty.split("\n").slice(0, 10).map((l) => `    ${l}`).join("\n"));
  } else {
    console.error(
      "Working tree has uncommitted changes under roblox/ or scripts/ — commit first\n" +
        "(a published build must be reproducible from a commit), or pass --force / --draft."
    );
    process.exit(1);
  }
}

const gitCommit = git("rev-parse", "--short", "HEAD") || "unknown";

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

// ---- Deploy ledger (backend Postgres) --------------------------------------
// Best-effort: a ledger outage must never block a deploy, it just costs the
// drift check + the record. Warn once and move on.

let ledgerDown = false;
function ledgerUnavailable(error) {
  if (!ledgerDown) {
    ledgerDown = true;
    console.warn(`! Deploy ledger unavailable (${error.message}) — continuing without drift check/records.`);
  }
}

async function ledgerLatest(placeId) {
  if (!FAMANA_API_KEY || ledgerDown) return null;
  try {
    const response = await fetch(`${manifest.backendUrl}/deploys/latest?placeId=${placeId}`, {
      headers: { "X-Api-Key": FAMANA_API_KEY },
    });
    if (!response.ok) throw new Error(`HTTP ${response.status}`);
    return (await response.json()).latest;
  } catch (error) {
    ledgerUnavailable(error);
    return null;
  }
}

async function ledgerRecord(record) {
  if (!FAMANA_API_KEY || ledgerDown) return;
  try {
    const response = await fetch(`${manifest.backendUrl}/deploys`, {
      method: "POST",
      headers: { "X-Api-Key": FAMANA_API_KEY, "Content-Type": "application/json" },
      body: JSON.stringify(record),
    });
    if (!response.ok) throw new Error(`HTTP ${response.status}`);
  } catch (error) {
    ledgerUnavailable(error);
  }
}

// ---- Build + publish --------------------------------------------------------

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

// "Restart servers for updates" — only touches servers running an outdated
// version, exactly like the Creator Dashboard button.
async function restartServers() {
  const response = await robloxFetch(
    `https://apis.roblox.com/cloud/v2/universes/${manifest.universeId}:restartServers`,
    { method: "POST", headers: { "Content-Type": "application/json" }, body: "{}" }
  );
  if (response.status === 401 || response.status === 403) {
    throw new Error(
      `HTTP ${response.status} — the API key is missing the Universe write scope ` +
        "(add the 'universe' system with Write in the key's Access Permissions)."
    );
  }
  if (!response.ok) {
    throw new Error(`HTTP ${response.status}: ${await response.text()}`);
  }
}

// ---- Run --------------------------------------------------------------------

fs.mkdirSync(BUILD_DIR, { recursive: true });

// Stamp BuildInfo for the whole run; ALWAYS restore the checked-in version.
const buildInfoOriginal = fs.readFileSync(BUILDINFO, "utf8");
fs.writeFileSync(
  BUILDINFO,
  `-- GENERATED by scripts/deploy-places.mjs — do not commit this version.\n` +
    `return {\n\tcommit = "${gitCommit}",\n\tbuiltAt = ${Math.floor(Date.now() / 1000)},\n}\n`
);

let failed = 0;
try {
  for (const name of selected) {
    const { placeId, project } = manifest.places[name];
    try {
      const latest = await ledgerLatest(placeId);
      process.stdout.write(`- ${name} (${placeId}): `);
      if (!noPull) {
        process.stdout.write("pulling map… ");
        const pulled = await pullMap(name, placeId, API_KEY);
        process.stdout.write(pulled === "pulled" ? "ok, " : "none, ");
      }
      process.stdout.write(`building… `);
      const file = build(name, project);
      process.stdout.write(`${versionType.toLowerCase()}… `);
      const version = await publish(placeId, file);
      console.log(`v${version} (${gitCommit})`);
      if (latest && version !== latest.version_number + 1) {
        console.log(
          `  · version jumped ${latest.version_number} → ${version}: the place was saved/published\n` +
            "    outside the pipeline since the last deploy — normal for Studio map sessions\n" +
            "    (their Map folder was pulled into this very build, nothing lost)."
        );
      }
      await ledgerRecord({
        placeName: name,
        placeId,
        universeId: manifest.universeId,
        versionNumber: version,
        versionType,
        gitCommit,
      });
    } catch (error) {
      failed += 1;
      console.log(`FAILED — ${error.message}`);
    }
  }
} finally {
  fs.writeFileSync(BUILDINFO, buildInfoOriginal);
}

console.log(`\nDone: ${selected.length - failed} deployed, ${failed} failed.`);

if (restart) {
  if (draft) {
    console.log("--restart ignored for drafts (nothing was published).");
  } else if (failed > 0) {
    console.log("--restart skipped: not migrating servers after a partial deploy.");
  } else {
    try {
      await restartServers();
      console.log("Restart requested: servers on outdated versions are migrating to the new one.");
    } catch (error) {
      console.error(`Restart FAILED — ${error.message}`);
      process.exit(1);
    }
  }
} else if (!draft && failed === 0) {
  console.log(
    "Live servers keep the old version until they empty — pass --restart to migrate them now."
  );
}

if (failed > 0) {
  process.exit(1);
}
