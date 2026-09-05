const { test, before, after } = require("node:test");
const assert = require("node:assert/strict");
const { Pool } = require("pg");
const { randomUUID } = require("node:crypto");
const { createApplication } = require("../dist/app");
const { migrate, seed } = require("../dist/database");
const connectionString =
  process.env.DATABASE_URL || "postgresql://localhost:55432/drone_match";
const schema = `test_${randomUUID().replaceAll("-", "")}`;
let pool, admin, app, base;
before(async () => {
  admin = new Pool({ connectionString });
  await admin.query(`CREATE SCHEMA "${schema}"`);
  pool = new Pool({ connectionString, options: `-c search_path=${schema}` });
  await migrate(pool);
  await seed(pool);
  app = await createApplication(pool, true);
  await app.listen(0, "127.0.0.1");
  base = `${await app.getUrl()}/api/v1`;
});
after(async () => {
  if (app) await app.close();
  if (pool) await pool.end();
  if (admin) {
    await admin.query(`DROP SCHEMA IF EXISTS "${schema}" CASCADE`);
    await admin.end();
  }
});
async function request(path, { token, method = "GET", body } = {}) {
  const response = await fetch(base + path, {
    method,
    headers: {
      "Content-Type": "application/json",
      ...(token ? { Authorization: `Bearer ${token}` } : {}),
    },
    ...(body ? { body: JSON.stringify(body) } : {}),
  });
  return { status: response.status, data: await response.json() };
}
test("游客可以查看公开赛事与详情", async () => {
  const response = await request("/tournaments");
  assert.equal(response.status, 200);
  assert.equal(response.data.length, 3);
  assert.equal(response.data[0].title, "青空杯 · 无人机足球邀请赛");
  assert.equal((await request("/tournaments/event-sky")).data.capacity, 16);
});
async function login(accountId) {
  const response = await request("/dev/sessions", {
    method: "POST",
    body: { accountId },
  });
  assert.equal(response.status, 201);
  return response.data.token;
}
test("会话控制队伍读取范围，退出后旧令牌不可再用", async () => {
  assert.equal((await request("/teams")).status, 401);
  const token = await login("captain-east");
  const teams = await request("/teams", { token });
  assert.equal(teams.status, 200);
  assert.deepEqual(
    teams.data.map((t) => t.id),
    ["team-east"],
  );
  assert.equal((await request("/me", { token })).data.id, "captain-east");
  assert.equal(
    (await request("/auth/session", { token, method: "DELETE" })).status,
    200,
  );
  assert.equal((await request("/teams", { token })).status, 401);
});
test("队长提交真实名单，重复提交只保留一条，并禁止借用其他队伍", async () => {
  const token = await login("captain-east");
  const foreign = await request("/tournaments/event-sky/registrations", {
    token,
    method: "POST",
    body: { teamId: "team-west", acceptRules: true },
  });
  assert.equal(foreign.status, 403);
  const first = await request("/tournaments/event-sky/registrations", {
    token,
    method: "POST",
    body: { teamId: "team-east", acceptRules: true },
  });
  assert.equal(first.status, 201);
  assert.equal(first.data.status, "pending");
  const second = await request("/tournaments/event-sky/registrations", {
    token,
    method: "POST",
    body: { teamId: "team-east", acceptRules: true },
  });
  assert.equal(second.data.id, first.data.id);
  assert.equal((await request("/registrations", { token })).data.length, 1);
  assert.deepEqual(first.data.roster, [
    "林越（演示）",
    "周航（演示）",
    "王宁（演示）",
  ]);
});
async function createEvent(token, capacity = 1) {
  const response = await request("/admin/tournaments", {
    token,
    method: "POST",
    body: {
      title: "并发审核验证赛事",
      city: "上海",
      venue: "测试飞行馆",
      category: "20cm",
      capacity,
      startsAt: new Date(Date.now() + 14 * 86400000).toISOString(),
      deadline: new Date(Date.now() + 7 * 86400000).toISOString(),
      description: "用于验证报名流程的本地演示赛事。",
    },
  });
  assert.equal(response.status, 201);
  return response.data;
}
test("主办方可以发布本机构赛事，队长可以创建自己的成人演示队伍", async () => {
  const organizer = await login("organizer-east");
  const captain = await login("captain-east");
  const event = await createEvent(organizer);
  assert.equal(
    (await request(`/tournaments/${event.id}`)).data.organizationId,
    "org-east",
  );
  const own = await request("/admin/tournaments", { token: organizer });
  assert.ok(own.data.every((t) => t.organizationId === "org-east"));
  assert.equal(
    (await request("/admin/tournaments", { token: captain })).status,
    403,
  );
  const team = await request("/teams", {
    token: captain,
    method: "POST",
    body: {
      name: "新增测试队",
      city: "上海",
      category: "20cm",
      roster: ["成年飞手A", "成年飞手B"],
      adultOnly: true,
    },
  });
  assert.equal(team.status, 201);
  assert.ok(
    (await request("/teams", { token: captain })).data.some(
      (t) => t.id === team.data.id,
    ),
  );
});
test("审核隔离机构，并发争抢最后一个名额时只有一队通过", async () => {
  const organizer = await login("organizer-east");
  const outsider = await login("organizer-west");
  const east = await login("captain-east");
  const west = await login("captain-west");
  const event = await createEvent(organizer, 1);
  const r1 = (
    await request(`/tournaments/${event.id}/registrations`, {
      token: east,
      method: "POST",
      body: { teamId: "team-east", acceptRules: true },
    })
  ).data;
  const r2 = (
    await request(`/tournaments/${event.id}/registrations`, {
      token: west,
      method: "POST",
      body: { teamId: "team-west", acceptRules: true },
    })
  ).data;
  const review = (id, token) =>
    request(`/admin/registrations/${id}/review`, {
      token,
      method: "POST",
      body: { status: "approved", version: 1, note: "" },
    });
  assert.equal((await review(r1.id, outsider)).status, 403);
  const responses = await Promise.all([
    review(r1.id, organizer),
    review(r2.id, organizer),
  ]);
  assert.deepEqual(responses.map((r) => r.status).sort(), [201, 409]);
  assert.equal(
    responses.find((r) => r.status === 409).data.code,
    "DIVISION_FULL",
  );
  assert.equal((await request(`/tournaments/${event.id}`)).data.approved, 1);
  const winner = responses.find((r) => r.status === 201).data;
  assert.equal((await review(winner.id, organizer)).status, 409);
  assert.equal(
    (await request("/registrations", { token: outsider })).data.some(
      (r) => r.tournamentId === event.id,
    ),
    false,
  );
});
test("非法名单、未确认规则、级别不符和截止报名由服务端拒绝", async () => {
  const captain = await login("captain-east");
  assert.equal(
    (
      await request("/teams", {
        token: captain,
        method: "POST",
        body: {
          name: "错误队伍",
          city: "上海",
          category: "20cm",
          roster: [],
          adultOnly: true,
        },
      })
    ).status,
    400,
  );
  assert.equal(
    (
      await request("/teams", {
        token: captain,
        method: "POST",
        body: {
          name: "重复人员",
          city: "上海",
          category: "20cm",
          roster: ["同名", "同名"],
          adultOnly: true,
        },
      })
    ).status,
    400,
  );
  assert.equal(
    (
      await request("/tournaments/event-open/registrations", {
        token: captain,
        method: "POST",
        body: { teamId: "team-east", acceptRules: true },
      })
    ).data.code,
    "CATEGORY_MISMATCH",
  );
  assert.equal(
    (
      await request("/tournaments/event-open/registrations", {
        token: captain,
        method: "POST",
        body: { teamId: "team-east", acceptRules: false },
      })
    ).status,
    400,
  );
  const organizer = await login("organizer-east");
  const event = await createEvent(organizer);
  await pool.query(
    `UPDATE tournaments SET deadline=now()-interval '1 minute' WHERE id=$1`,
    [event.id],
  );
  assert.equal(
    (
      await request(`/tournaments/${event.id}/registrations`, {
        token: captain,
        method: "POST",
        body: { teamId: "team-east", acceptRules: true },
      })
    ).data.code,
    "REGISTRATION_CLOSED",
  );
});
test("禁用开发模式后演示登录入口不可访问，生产模式拒绝演示鉴权", async () => {
  const locked = await createApplication(pool, false);
  try {
    await locked.listen(0, "127.0.0.1");
    assert.equal(
      (await fetch(`${await locked.getUrl()}/api/v1/dev/accounts`)).status,
      404,
    );
    assert.equal(
      (
        await fetch(`${await locked.getUrl()}/api/v1/dev/sessions`, {
          method: "POST",
          headers: { "Content-Type": "application/json" },
          body: JSON.stringify({ accountId: "captain-east" }),
        })
      ).status,
      404,
    );
  } finally {
    await locked.close();
  }
  const old = process.env.NODE_ENV;
  process.env.NODE_ENV = "production";
  try {
    await assert.rejects(
      () => createApplication(pool, true),
      /forbidden in production/,
    );
  } finally {
    if (old === undefined) delete process.env.NODE_ENV;
    else process.env.NODE_ENV = old;
  }
});
