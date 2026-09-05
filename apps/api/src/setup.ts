import { Pool } from "pg";
import { databaseURL, migrate, seed } from "./database";
async function main() {
  if (process.env.NODE_ENV === "production")
    throw new Error("Demo database setup is local-only.");
  const pool = new Pool({ connectionString: databaseURL() });
  try {
    await migrate(pool);
    await seed(pool);
    console.log("Local database ready. Existing records preserved.");
  } finally {
    await pool.end();
  }
}
main().catch((error) => {
  console.error(error.message);
  process.exitCode = 1;
});
