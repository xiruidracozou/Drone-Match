import { Pool } from "pg";
import { readFile } from "node:fs/promises";
import { resolve } from "node:path";

export const databaseURL = () =>
  process.env.DATABASE_URL || "postgresql://localhost:55432/drone_match";

export async function migrate(pool: Pool) {
  await pool.query(await readFile(resolve(__dirname, "../schema.sql"), "utf8"));
}

export async function seed(pool: Pool) {
  const client = await pool.connect();
  try {
    await client.query("BEGIN");
    await client.query(`INSERT INTO organizations VALUES
      ('org-east','青空飞行俱乐部','上海'), ('org-west','远山航空运动中心','杭州') ON CONFLICT DO NOTHING`);
    await client.query(`INSERT INTO accounts VALUES
      ('captain-east','林教练','captain','org-east'),
      ('captain-west','陈教练','captain','org-west'),
      ('organizer-east','青空赛事运营','organizer','org-east'),
      ('organizer-west','远山赛事运营','organizer','org-west') ON CONFLICT DO NOTHING`);
    await client.query(`INSERT INTO teams(id,name,city,owner_id,organization_id,category,roster) VALUES
      ('team-east','青空一队','上海','captain-east','org-east','20cm','["林越（演示）","周航（演示）","王宁（演示）"]'),
      ('team-west','远山飞行队','杭州','captain-west','org-west','20cm','["陈立（演示）","吴远（演示）","李川（演示）"]') ON CONFLICT DO NOTHING`);
    const rules =
      "本地演示报名规则：仅供成年飞手测试，每队 1–10 人，设备级别须与赛事一致。审核通过后占用名额。本规则不适用于真实竞赛；正式规则确认后另行接入。";
    const events = [
      [
        "event-sky",
        "青空杯 · 无人机足球邀请赛",
        "上海",
        "浦东飞行运动馆",
        "org-east",
        "20cm",
        21,
        16,
        "从训练场走向赛场。与来自不同俱乐部的飞手相遇，在空中完成一次默契的配合。",
      ],
      [
        "event-mountain",
        "远山计划 · 城市交流赛",
        "杭州",
        "滨江航空运动中心",
        "org-west",
        "20cm",
        35,
        12,
        "一场连接城市与俱乐部的飞行交流。相互切磋，共同进步。",
      ],
      [
        "event-open",
        "周末飞行 · 公开体验赛",
        "上海",
        "青空训练基地",
        "org-east",
        "40cm",
        48,
        8,
        "面向成年飞手的公开体验活动，探索更大球体的协作飞行。",
      ],
    ];
    for (const [
      id,
      title,
      city,
      venue,
      org,
      category,
      days,
      capacity,
      description,
    ] of events) {
      await client.query(
        `INSERT INTO tournaments(id,title,city,venue,organization_id,category,starts_at,deadline,capacity,description,rules)
        VALUES($1,$2,$3,$4,$5,$6,now()+$7*interval '1 day',now()+($7-7)*interval '1 day',$8,$9,$10) ON CONFLICT DO NOTHING`,
        [
          id,
          title,
          city,
          venue,
          org,
          category,
          days,
          capacity,
          description,
          rules,
        ],
      );
    }
    await client.query("COMMIT");
  } catch (error) {
    await client.query("ROLLBACK");
    throw error;
  } finally {
    client.release();
  }
}
