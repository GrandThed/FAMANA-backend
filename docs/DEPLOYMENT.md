# Deployment pipeline

How code and maps reach every published place, automatically. Map *authoring*
(Studio workflow, markers, exporting) is [`MAP_AUTHORING.md`](MAP_AUTHORING.md);
this doc is the pipeline that ships it.

## Principles

1. **The pipeline is the only writer of CODE to live places.** Maps are the
   exception: they're authored AND published from Studio, and the pipeline
   preserves them — every deploy pulls the live place's `Map` folder down
   (`scripts/pull-maps.mjs`) and builds it back in. A Studio publish still
   shows up as a version jump in the ledger check (see §Ledger), now as an
   informational note rather than a warning.
2. **Git is the source of truth for code.** A published build's code is
   always reproducible from a commit: the deploy script refuses dirty trees
   (`--force` to override, drafts only warn), and every build is stamped.
   The map layered on top comes from the live place at deploy time — its
   history lives in the place's version history, not git.
3. **Every deploy is recorded.** `BuildInfo.lua` inside the place says which
   commit it runs; the backend ledger says which version every place got,
   when, from which commit.
4. **Places update; servers migrate separately.** Publishing never kicks
   players — live servers keep the old version until they empty. Migration
   (`restartServers`) is an explicit action.

## The normal flow

```
commit code → push to main                 map work: build in Studio → Publish
  → GitHub Actions (.github/workflows/deploy-places.yml)
      1. rebuild Secret.lua from the FAMANA_API_KEY repo secret
      2. stamp src/shared/BuildInfo.lua with commit + timestamp
      3. pull each live place's Map folder → roblox/maps/<name>/
         (a failed pull FAILS that place — never build over a live map)
      4. rojo build each place in roblox/places.json → publish via Open Cloud
      5. record each publish in the backend ledger (POST /deploys)
      6. note version drift (Studio map sessions — expected, nothing lost)
```

Path-filtered: only pushes touching `roblox/**` (or the script/workflow)
deploy. Backend-only pushes deploy only Railway, as before. One deploy runs
at a time (concurrency group).

**Migrating live servers:** run the workflow manually (Actions → Deploy
places → Run workflow) with `restart: true`, or locally
`node scripts/deploy-places.mjs --restart`. Restart only touches servers on
outdated versions (same as the dashboard's "Restart servers for updates");
players get Roblox's reconnect flow and their state is already saved
(60s autosave + save-on-leave).

**Local runs** still work and take the same guards:

| Command | Effect |
| --- | --- |
| `node scripts/deploy-places.mjs` | build + publish all places |
| `… cellB` | only named place(s) |
| `… --draft` | upload as Saved — test in Studio without going live |
| `… --restart` | after a 100%-successful publish, migrate live servers |
| `… --force` | deploy a dirty tree (breaks reproducibility — avoid) |
| `… --no-pull` | skip the map pull — build with `roblox/maps/` as-is |
| `node scripts/pull-maps.mjs [names…]` | refresh `roblox/maps/` from the live places, no deploy |

Keys for local runs live in the repo-root `.env` (gitignored):
`ROBLOX_API_KEY=<open cloud key>`. The backend ledger key is read from
`Secret.lua` automatically.

## CI setup (already done, for reference)

- Repo secrets `ROBLOX_API_KEY` + `FAMANA_API_KEY`
  (Settings → Secrets and variables → Actions).
- The Open Cloud key needs: **universe-places → Write** (publishing),
  **universe → Write** (restarts), **Legacy Assets → manage**
  (`legacy-assets:manage`, the map pull's place download), and its IP
  allowlist set to `0.0.0.0/0` (GitHub runners have changing IPs).

## The ledger

Backend tables (`backend/src/schema.sql`): `places` — the registry, upserted
from `roblox/places.json` on every deploy, so **every place the pipeline
touches is tracked automatically**; `deploys` — append-only history
(version, type, commit, time). Endpoints behind `X-Api-Key`: `POST /deploys`,
`GET /deploys/latest?placeId=`, `GET /places` (registry + latest deploy —
the future dashboard's Places source).

**Drift check:** Roblox increments a place's version on every save/publish.
If a publish comes back more than +1 above the last *recorded* version,
something else wrote to the place since the pipeline last did — almost
always a Studio map session, which is now a normal part of the workflow
(the session's published Map was pulled into this very build), so the
deploy prints an informational note rather than a warning. Ledger outages
never block a deploy; you just lose the check for that run.

## Rollback

**Code:** `git revert` the bad commit and push — CI redeploys the previous
code, with the current live map pulled in as always. **Maps:** the place's
version history on the Creator Dashboard (maps aren't in git); restore the
version there, then re-run the deploy so code and ledger catch up.

## Adding a new place

1. Studio → File → Publish to Roblox → into the FAMANA experience → new place.
2. Register the PlaceId: `GridConfig.cells` (grid cell) or `GridConfig.places`
   (instance place, with a `role`).
3. Copy `roblox/cellA.project.json` → `<name>.project.json`, point its Map
   mount at `maps/<name>.rbxm`.
4. Add it to `roblox/places.json`.
5. Commit + push — CI deploys it, and the ledger starts tracking it.

## When something fails

- **Partial deploy** (some places FAILED): fixed versions stay live nowhere —
  the failed places just keep their previous version. Re-run the workflow
  (or `node scripts/deploy-places.mjs <failed places>`). `--restart` refuses
  to run after partial deploys, so versions never migrate half-updated.
- **409 Server is busy** after retries: the place is open in Studio — close
  it and re-run.
- **Failed map pull** (place deploy FAILED at "pulling map"): usually the
  API key lacks the **Legacy Assets → manage** permission, or same-named
  instances sit directly under Workspace outside `Map`. Debug with
  `node scripts/pull-maps.mjs <place>`; `--no-pull` ships whatever
  `roblox/maps/` already holds if you must deploy NOW.
