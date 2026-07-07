// Uploads the UI glyphs in assets/icons_png to Roblox via the Open Cloud
// Assets API and writes the returned asset ids straight into
// roblox/src/shared/Icons.lua.
//
// Setup (once): create an API key at create.roblox.com → Open Cloud →
// API Keys, add the "Assets" system with Read + Write, and allow your IP
// (or 0.0.0.0/0). The key is a SECRET — pass it via env, never commit it.
//
// Usage (PowerShell):
//   $env:ROBLOX_API_KEY = "<key>"
//   $env:ROBLOX_USER_ID = "<your numeric user id>"   # or ROBLOX_GROUP_ID
//   node scripts/upload-icons.mjs
//
// Idempotent: names whose id in Icons.lua is already non-zero are skipped,
// and Icons.lua is rewritten after every successful upload, so an
// interrupted run resumes where it left off. Requires Node 18+.

import fs from "node:fs";
import path from "node:path";
import { fileURLToPath } from "node:url";

const ROOT = path.resolve(path.dirname(fileURLToPath(import.meta.url)), "..");
const ICONS_DIR = path.join(ROOT, "assets", "icons_png");
const ICONS_LUA = path.join(ROOT, "roblox", "src", "shared", "Icons.lua");

const API_KEY = process.env.ROBLOX_API_KEY;
const USER_ID = process.env.ROBLOX_USER_ID;
const GROUP_ID = process.env.ROBLOX_GROUP_ID;

if (!API_KEY || (!USER_ID && !GROUP_ID)) {
  console.error(
    "Missing env: set ROBLOX_API_KEY and ROBLOX_USER_ID (or ROBLOX_GROUP_ID)."
  );
  process.exit(1);
}

const creator = GROUP_ID
  ? { groupId: Number(GROUP_ID) }
  : { userId: Number(USER_ID) };

const sleep = (ms) => new Promise((resolve) => setTimeout(resolve, ms));

// Current `Name = <id>` entries in Icons.lua (0 = not uploaded yet).
function readIds(luaSource) {
  const ids = new Map();
  for (const match of luaSource.matchAll(/^\t(\w+) = (\d+),/gm)) {
    ids.set(match[1], Number(match[2]));
  }
  return ids;
}

function writeId(name, assetId) {
  const source = fs.readFileSync(ICONS_LUA, "utf8");
  const pattern = new RegExp(`(\\t${name} = )0(,)`, "m");
  if (!pattern.test(source)) {
    console.warn(`  ! ${name}: no "${name} = 0" line in Icons.lua — paste ${assetId} manually`);
    return;
  }
  fs.writeFileSync(ICONS_LUA, source.replace(pattern, `$1${assetId}$2`));
}

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
  return response;
}

// POST the image, then poll the returned long-running operation until the
// asset id materializes. Returns the numeric asset id.
async function upload(name, filePath) {
  const form = new FormData();
  form.append(
    "request",
    JSON.stringify({
      assetType: "Image",
      displayName: `FAMANA UI ${name}`,
      description: "FAMANA design-system UI glyph (docs/UI.md)",
      creationContext: { creator },
    })
  );
  form.append(
    "fileContent",
    new Blob([fs.readFileSync(filePath)], { type: "image/png" }),
    `${name}.png`
  );

  const response = await robloxFetch("https://apis.roblox.com/assets/v1/assets", {
    method: "POST",
    body: form,
  });
  if (!response.ok) {
    throw new Error(`upload HTTP ${response.status}: ${await response.text()}`);
  }
  const { operationId, path: operationPath } = await response.json();
  const opUrl = `https://apis.roblox.com/assets/v1/${operationPath || `operations/${operationId}`}`;

  for (let poll = 0; poll < 30; poll++) {
    await sleep(poll === 0 ? 1500 : 3000);
    const opResponse = await robloxFetch(opUrl, { method: "GET" });
    if (!opResponse.ok) {
      throw new Error(`poll HTTP ${opResponse.status}: ${await opResponse.text()}`);
    }
    const operation = await opResponse.json();
    if (operation.done) {
      if (operation.error) {
        throw new Error(`operation failed: ${JSON.stringify(operation.error)}`);
      }
      return Number(operation.response.assetId);
    }
  }
  throw new Error("operation timed out (asset may still appear — check the dashboard)");
}

const ids = readIds(fs.readFileSync(ICONS_LUA, "utf8"));
const files = fs
  .readdirSync(ICONS_DIR)
  .filter((file) => file.endsWith(".png"))
  .map((file) => path.basename(file, ".png"))
  .sort();

const missing = [...ids.keys()].filter((name) => !files.includes(name));
if (missing.length > 0) {
  console.warn(`No PNG for Icons.lua entries: ${missing.join(", ")}`);
}

let uploaded = 0;
let failed = 0;
for (const name of files) {
  if (!ids.has(name)) {
    console.log(`- ${name}: not referenced by Icons.lua, skipping`);
    continue;
  }
  if (ids.get(name) > 0) {
    console.log(`- ${name}: already ${ids.get(name)}, skipping`);
    continue;
  }
  try {
    process.stdout.write(`- ${name}: uploading… `);
    const assetId = await upload(name, path.join(ICONS_DIR, `${name}.png`));
    writeId(name, assetId);
    console.log(`rbxassetid://${assetId}`);
    uploaded += 1;
    await sleep(500); // stay well under the write rate limit
  } catch (error) {
    failed += 1;
    console.log(`FAILED — ${error.message}`);
  }
}

console.log(`\nDone: ${uploaded} uploaded, ${failed} failed.`);
if (uploaded > 0) {
  console.log("Icons.lua updated — rojo will sync it; the tracker badges go live immediately.");
}
if (failed > 0) {
  process.exit(1);
}
