// Upload the new-art-style enemy assets (rigged model FBXs + KeyframeSequence
// rbxmx animations) to Roblox via the Open Cloud Assets API.
// Usage: node scripts/upload-enemy-assets.mjs [NameFilter ...]
// Reads ROBLOX_API_KEY from .env at the repo root. Writes asset ids to
// new_art_style/roblox/opencloud/roblox_asset_ids.json (+ .md table).

import { readFileSync, writeFileSync, existsSync } from 'node:fs';
import { join, dirname } from 'node:path';
import { fileURLToPath } from 'node:url';

const ROOT = join(dirname(fileURLToPath(import.meta.url)), '..');
const SRC = join(ROOT, 'new_art_style', 'roblox', 'opencloud');
const CREATOR_USER_ID = process.env.ROBLOX_CREATOR_USER_ID || '11217290800';

const env = readFileSync(join(ROOT, '.env'), 'utf8');
const key = env.match(/^ROBLOX_API_KEY=(.+)$/m)?.[1]?.trim();
if (!key) { console.error('ROBLOX_API_KEY not found in .env'); process.exit(1); }

const ENEMIES = ['Goblin', 'Golem', 'Spider'];
const CLIPS = ['Idle', 'Walk', 'Attack'];
const jobs = [];
for (const e of ENEMIES) {
  jobs.push({ name: `${e}_Model`, file: `${e}_Model.fbx`, assetType: 'Model', mimes: ['model/fbx'] });
  for (const c of CLIPS) {
    jobs.push({ name: `${e}_Anim_${c}`, file: `${e}_Anim_${c}.rbxm`, assetType: 'Animation', mimes: ['model/x-rbxm', 'application/octet-stream'] });
  }
}

const filters = process.argv.slice(2);
const selected = jobs.filter(j => filters.length === 0 || filters.some(f => j.name.includes(f)));

const sleep = ms => new Promise(r => setTimeout(r, ms));

async function uploadOne(job) {
  const buf = readFileSync(join(SRC, job.file));
  let res, body;
  for (const mime of job.mimes) {
    const form = new FormData();
    form.append('request', JSON.stringify({
      assetType: job.assetType,
      displayName: `FAMANA ${job.name.replace(/_/g, ' ')}`,
      description: `FAMANA enemy asset: ${job.name}`,
      creationContext: { creator: { userId: CREATOR_USER_ID } },
    }));
    form.append('fileContent', new Blob([buf], { type: mime }), job.file);
    res = await fetch('https://apis.roblox.com/assets/v1/assets', {
      method: 'POST', headers: { 'x-api-key': key }, body: form,
    });
    body = await res.json().catch(() => ({}));
    if (res.ok || !/not supported/i.test(body?.message || '')) break;
  }
  if (!res.ok) throw new Error(`create ${res.status}: ${JSON.stringify(body)}`);

  const opPath = body.path || (body.operationId ? `operations/${body.operationId}` : null);
  if (!opPath) throw new Error('no operation in response: ' + JSON.stringify(body));

  for (let i = 0; i < 30; i++) {
    await sleep(2000);
    const op = await fetch(`https://apis.roblox.com/assets/v1/${opPath}`, { headers: { 'x-api-key': key } });
    const opBody = await op.json().catch(() => ({}));
    if (!op.ok) throw new Error(`poll ${op.status}: ${JSON.stringify(opBody)}`);
    if (opBody.done) {
      if (opBody.error) throw new Error('operation failed: ' + JSON.stringify(opBody.error));
      return opBody.response?.assetId;
    }
  }
  throw new Error('operation timed out: ' + opPath);
}

const outJson = join(SRC, 'roblox_asset_ids.json');
const results = existsSync(outJson) ? JSON.parse(readFileSync(outJson, 'utf8')) : {};

for (const job of selected) {
  if (results[job.name]) { console.log(`skip ${job.name} (already ${results[job.name]})`); continue; }
  process.stdout.write(`uploading ${job.name} (${job.assetType})... `);
  try {
    const id = await uploadOne(job);
    results[job.name] = id;
    console.log(`assetId ${id}`);
  } catch (e) {
    console.log('FAILED: ' + e.message);
  }
  writeFileSync(outJson, JSON.stringify(results, null, 2));
}

const md = ['# Roblox asset ids — new-art-style enemies', '', '| Asset | assetId | rbxassetid |', '|---|---|---|',
  ...Object.entries(results).map(([n, id]) => `| ${n} | ${id} | rbxassetid://${id} |`)].join('\n');
writeFileSync(join(SRC, 'ROBLOX_ASSET_IDS.md'), md + '\n');
console.log(`\n${Object.keys(results).length} asset ids written to roblox_asset_ids.json / ROBLOX_ASSET_IDS.md`);
