import { Pool } from "pg";
import { createApplication } from "./app";
import { databaseURL } from "./database";

async function main() {
  const pool = new Pool({ connectionString: databaseURL() });
  await pool.query("SELECT 1");
  const app = await createApplication(pool, process.env.DEMO_MODE === "true");
  await app.listen(Number(process.env.PORT || 3001), "127.0.0.1");
  console.log(`Drone Match API: ${await app.getUrl()}/api/v1`);
  let closing = false;
  const close = async () => {
    if (closing) return;
    closing = true;
    await app.close();
    await pool.end();
  };
  process.once("SIGTERM", close);
  process.once("SIGINT", close);
}
main().catch((error) => {
  console.error(error.message);
  process.exitCode = 1;
});
