// Applies schema.sql. Run with `npm run migrate`.
import { readFile } from "node:fs/promises";
import { fileURLToPath } from "node:url";
import { dirname, join } from "node:path";
import { pool } from "./db.js";

const __dirname = dirname(fileURLToPath(import.meta.url));

async function main() {
  const sql = await readFile(join(__dirname, "schema.sql"), "utf8");
  await pool.query(sql);
  console.log("Migration applied successfully.");
  await pool.end();
}

main().catch((err) => {
  console.error("Migration failed:", err);
  process.exit(1);
});
