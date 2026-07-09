// Place registry + deploy ledger (docs/DEPLOYMENT.md). Written to by
// scripts/deploy-places.mjs on every deploy; read back for the drift check
// ("did someone publish outside the pipeline since last time?") and, later,
// the admin dashboard's Places screen.

import { pool } from "./db.js";

// Upsert a place from the deploy manifest. Names/universes may change
// (places.json is the source of truth); place_id never does.
export async function upsertPlace({ placeId, universeId, name }) {
  await pool.query(
    `INSERT INTO places (place_id, universe_id, name)
     VALUES ($1, $2, $3)
     ON CONFLICT (place_id)
     DO UPDATE SET universe_id = $2, name = $3, updated_at = now()`,
    [placeId, universeId, name]
  );
}

export async function recordDeploy({ placeId, versionNumber, versionType, gitCommit }) {
  await pool.query(
    `INSERT INTO deploys (place_id, version_number, version_type, git_commit)
     VALUES ($1, $2, $3, $4)`,
    [placeId, versionNumber, versionType, gitCommit || null]
  );
}

export async function latestDeploy(placeId) {
  const { rows } = await pool.query(
    `SELECT place_id, version_number, version_type, git_commit, deployed_at
     FROM deploys WHERE place_id = $1 ORDER BY id DESC LIMIT 1`,
    [placeId]
  );
  return rows[0] || null;
}

// Every known place with its latest deploy folded in — the dashboard's
// eventual Places listing.
export async function listPlaces() {
  const { rows } = await pool.query(
    `SELECT p.place_id, p.universe_id, p.name, p.created_at, p.updated_at,
            d.version_number AS latest_version, d.version_type AS latest_version_type,
            d.git_commit AS latest_commit, d.deployed_at AS last_deployed_at
     FROM places p
     LEFT JOIN LATERAL (
       SELECT version_number, version_type, git_commit, deployed_at
       FROM deploys WHERE place_id = p.place_id ORDER BY id DESC LIMIT 1
     ) d ON true
     ORDER BY p.name`
  );
  return rows;
}
