import { Pool } from "pg";
import { databaseURL, migrate } from "./database";
import { createPlatformAdmin } from "./platform-auth";
async function main() {
  if (process.env.NODE_ENV === "production")
    throw new Error("此初始化命令仅用于本地联调");
  const db = new Pool({ connectionString: databaseURL() });
  try {
    await migrate(db);
    await createPlatformAdmin(
      db,
      process.env.PLATFORM_USERNAME ?? "",
      process.env.PLATFORM_PASSWORD ?? "",
    );
    console.log("平台管理员已创建");
  } finally {
    await db.end();
  }
}
main().catch((e) => {
  console.error(e.message);
  process.exitCode = 1;
});
