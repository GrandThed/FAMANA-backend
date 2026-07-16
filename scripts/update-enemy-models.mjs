// Push new file content to the already-created enemy Model assets (same ids).
// Usage: node scripts/update-enemy-models.mjs

import { readFileSync } from 'node:fs';
import { join, dirname } from 'node:path';
import { fileURLToPath } from 'node:url';

const ROOT = join(dirname(fileURLToPath(import.meta.url)), '..');
const SRC = join(ROOT, 'new_art_style', 'roblox', 'opencloud');

const env = readFileSync(join(ROOT, '.env'), 'utf8');
const key = env.match(/^ROBLOX_API_KEY=(.+)$/m)?.[1]?.trim();
if (!key) { console.error('ROBLOX_API_KEY not found in .env'); process.exit(1); }

const ids = JSON.parse(readFileSync(join(SRC, 'roblox_asset_ids.json'), 'utf8'));
const sleep = ms => new Promise(r => setTimeout(r, ms));

for (const enemy of ['Goblin', 'Golem', 'Spider']) {
  const name = `${enemy}_Model`;
  const assetId = ids[name];
  process.stdout.write(`updating ${name} (${assetId})... `);
  const form = new FormData();
  form.append('request', JSON.stringify({ assetId }));
  form.append('fileContent', new Blob([readFileSync(join(SRC, `${enemy}_Model.fbx`))], { type: 'model/fbx' }), `${enemy}_Model.fbx`);
  const res = await fetch(`https://apis.roblox.com/assets/v1/assets/${assetId}`, {
    method: 'PATCH', headers: { 'x-api-key': key }, body: form,
  });
  const body = await res.json().catch(() => ({}));
  if (!res.ok) { console.log(`FAILED ${res.status}: ${JSON.stringify(body)}`); continue; }
  const opPath = body.path || (body.operationId ? `operations/${body.operationId}` : null);
  let done = false;
  for (let i = 0; i < 30 && !done; i++) {
    await sleep(2000);
    const op = await fetch(`https://apis.roblox.com/assets/v1/${opPath}`, { headers: { 'x-api-key': key } });
    const opBody = await op.json().catch(() => ({}));
    if (opBody.done) {
      done = true;
      console.log(opBody.error ? 'FAILED: ' + JSON.stringify(opBody.error) : 'ok (new version live)');
    }
  }
  if (!done) console.log('timed out polling');
}
