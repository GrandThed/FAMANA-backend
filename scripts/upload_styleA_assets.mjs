// Upload FAMANA Style A FBX assets to Roblox via Open Cloud Assets API.
// Usage: node scripts/upload_styleA_assets.mjs [NameFilter ...]
// Reads ROBLOX_API_KEY from .env at the repo root. Writes asset ids to
// roblox/src/assets/StyleA/roblox_asset_ids.json (+ .md table).

import { readFileSync, writeFileSync, readdirSync, existsSync } from 'node:fs';
import { join, dirname } from 'node:path';
import { fileURLToPath } from 'node:url';

const ROOT = join(dirname(fileURLToPath(import.meta.url)), '..');
const STYLE_A = join(ROOT, 'roblox', 'src', 'assets', 'StyleA');
const CREATOR_USER_ID = process.env.ROBLOX_CREATOR_USER_ID || '11217290800';

const env = readFileSync(join(ROOT, '.env'), 'utf8');
const key = env.match(/^ROBLOX_API_KEY=(.+)$/m)?.[1]?.trim();
if (!key) { console.error('ROBLOX_API_KEY not found in .env'); process.exit(1); }

const filters = process.argv.slice(2);
const names = readdirSync(STYLE_A, { withFileTypes: true })
  .filter(d => d.isDirectory() && existsSync(join(STYLE_A, d.name, d.name + '.fbx')))
  .map(d => d.name)
  .filter(n => filters.length === 0 || filters.includes(n));

const sleep = ms => new Promise(r => setTimeout(r, ms));

async function uploadOne(name) {
  const fbx = readFileSync(join(STYLE_A, name, name + '.fbx'));
  const form = new FormData();
  form.append('request', JSON.stringify({
    assetType: 'Model',
    displayName: `FAMANA ${name}`,
    description: `FAMANA Style A faceted low-poly asset: ${name}`,
    creationContext: { creator: { userId: CREATOR_USER_ID } },
  }));
  form.append('fileContent', new Blob([fbx], { type: 'model/fbx' }), name + '.fbx');

  const res = await fetch('https://apis.roblox.com/assets/v1/assets', {
    method: 'POST', headers: { 'x-api-key': key }, body: form,
  });
  const body = await res.json().catch(() => ({}));
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

const results = {};
const outJson = join(STYLE_A, 'roblox_asset_ids.json');
if (existsSync(outJson)) Object.assign(results, JSON.parse(readFileSync(outJson, 'utf8')));

for (const name of names) {
  if (results[name]) { console.log(`skip ${name} (already ${results[name]})`); continue; }
  process.stdout.write(`uploading ${name}... `);
  try {
    const id = await uploadOne(name);
    results[name] = id;
    console.log(`assetId ${id}`);
  } catch (e) {
    console.log('FAILED: ' + e.message);
  }
  writeFileSync(outJson, JSON.stringify(results, null, 2));
}

const md = ['# Roblox asset ids — Style A uploads', '', '| Asset | assetId | rbxassetid |', '|---|---|---|',
  ...Object.entries(results).map(([n, id]) => `| ${n} | ${id} | rbxassetid://${id} |`)].join('\n');
writeFileSync(join(STYLE_A, 'ROBLOX_ASSET_IDS.md'), md + '\n');
console.log(`\n${Object.keys(results).length} asset ids written to roblox_asset_ids.json / ROBLOX_ASSET_IDS.md`);
