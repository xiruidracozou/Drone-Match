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
  await pool.query(
    "INSERT INTO accounts VALUES ('captain-third','第三队长','captain','org-west')",
  );
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

test("队伍资料修改持久化，限制本人操作并保留已提交的报名快照", async () => {
  const captain = await login("captain-east");
  const outsider = await login("captain-west");
  const organizer = await login("organizer-east");
  const original = {
    name: "名单快照测试队",
    city: "上海",
    category: "20cm",
    roster: ["飞手甲", "飞手乙"],
    adultOnly: true,
  };
  const team = (
    await request("/teams", { token: captain, method: "POST", body: original })
  ).data;
  const event = await createEvent(organizer, 8);
  const entry = (
    await request(`/tournaments/${event.id}/registrations`, {
      token: captain,
      method: "POST",
      body: { teamId: team.id, acceptRules: true },
    })
  ).data;
  const changed = {
    ...original,
    name: "更新后的测试队",
    city: "杭州",
    roster: ["飞手乙", "飞手丙"],
  };
  const path = `/teams/${team.id}`;
  assert.equal(
    (await request(path, { token: captain, method: "PUT", body: changed }))
      .status,
    200,
  );
  const saved = (await request("/teams", { token: captain })).data.find(
    (t) => t.id === team.id,
  );
  assert.equal(saved.name, changed.name);
  assert.equal(saved.city, changed.city);
  assert.deepEqual(saved.roster, changed.roster);
  const historical = (
    await request("/registrations", { token: captain })
  ).data.find((r) => r.id === entry.id);
  assert.deepEqual(historical.roster, original.roster);
  assert.equal(historical.teamName, original.name);
  assert.equal(
    (await request(path, { method: "PUT", body: original })).status,
    401,
  );
  assert.equal(
    (await request(path, { token: outsider, method: "PUT", body: original }))
      .status,
    404,
  );
  assert.equal(
    (await request(path, { token: organizer, method: "PUT", body: original }))
      .status,
    403,
  );
  assert.equal(
    (
      await request(path, {
        token: captain,
        method: "PUT",
        body: { ...changed, roster: ["重复", "重复"] },
      })
    ).status,
    400,
  );
  assert.equal(
    (
      await request(path, {
        token: captain,
        method: "PUT",
        body: { ...changed, roster: [] },
      })
    ).status,
    400,
  );
  assert.deepEqual(
    (await request("/teams", { token: captain })).data.find(
      (t) => t.id === team.id,
    ).roster,
    changed.roster,
  );
});

test("招募申请真实保存，重复申请幂等，仅发布人可审核，接受后加入队伍", async () => {
  const east = await login("captain-east");
  const west = await login("captain-west");
  const created = await request("/community/posts", {
    token: east,
    method: "POST",
    body: {
      kind: "recruit",
      title: "周末训练招募飞手",
      city: "上海",
      category: "20cm",
      level: "入门",
      availability: "周六下午",
      venue: "飞行训练馆",
      body: "招募愿意定期训练的飞手，一起报名城市交流赛。",
      teamId: "team-east",
    },
  });
  assert.equal(created.status, 201);
  const post = created.data;
  assert.equal(
    (await request("/community/posts?kind=recruit")).data.some(
      (p) => p.id === post.id,
    ),
    true,
  );
  const payload = { message: "希望加入周末训练" };
  const apply = await request(`/community/posts/${post.id}/applications`, {
    token: west,
    method: "POST",
    body: payload,
  });
  assert.equal(apply.status, 201);
  const duplicate = await request(`/community/posts/${post.id}/applications`, {
    token: west,
    method: "POST",
    body: payload,
  });
  assert.equal(duplicate.data.id, apply.data.id);
  assert.equal(
    (
      await request(`/community/applications/${apply.data.id}`, {
        token: west,
        method: "PATCH",
        body: { status: "accepted" },
      })
    ).status,
    403,
  );
  assert.equal(
    (
      await request(`/community/applications/${apply.data.id}`, {
        token: east,
        method: "PATCH",
        body: { status: "accepted" },
      })
    ).status,
    200,
  );
  assert.equal(
    (await request("/community/memberships", { token: west })).data.some(
      (m) => m.teamId === "team-east",
    ),
    true,
  );
  assert.equal(
    (await request("/community/applications", { token: west })).data.find(
      (a) => a.id === apply.data.id,
    ).status,
    "accepted",
  );
  assert.equal(
    (
      await request(`/community/posts/${post.id}`, {
        token: west,
        method: "PATCH",
        body: { status: "closed" },
      })
    ).status,
    404,
  );
  assert.equal(
    (
      await request(`/community/posts/${post.id}`, {
        token: east,
        method: "PATCH",
        body: { status: "closed" },
      })
    ).status,
    200,
  );
  assert.equal(
    (
      await request(`/community/posts/${post.id}/applications`, {
        token: west,
        method: "POST",
        body: payload,
      })
    ).status,
    409,
  );
});

test("约赛只能确认一个对手，拒绝自我应约和越权队伍，并保留处理记录", async () => {
  const east = await login("captain-east"),
    west = await login("captain-west");
  const data = {
    kind: "friendly",
    title: "周日友谊训练赛",
    city: "上海",
    category: "20cm",
    level: "不限",
    availability: "周日",
    venue: "训练馆",
    body: "按本次约定规则进行免费训练赛。",
    teamId: "team-east",
    startsAt: new Date(Date.now() + 86400000).toISOString(),
  };
  assert.equal(
    (
      await request("/community/posts", {
        token: west,
        method: "POST",
        body: data,
      })
    ).status,
    403,
  );
  const post = (
    await request("/community/posts", {
      token: east,
      method: "POST",
      body: data,
    })
  ).data;
  assert.equal(
    (
      await request(`/community/posts/${post.id}/applications`, {
        token: east,
        method: "POST",
        body: { message: "自我应约", teamId: "team-east" },
      })
    ).status,
    400,
  );
  const application = (
    await request(`/community/posts/${post.id}/applications`, {
      token: west,
      method: "POST",
      body: { message: "希望应约", teamId: "team-west" },
    })
  ).data;
  assert.equal(
    (
      await request(`/community/applications/${application.id}`, {
        token: east,
        method: "PATCH",
        body: { status: "accepted" },
      })
    ).status,
    200,
  );
  assert.equal(
    (await request(`/community/posts/${post.id}`)).data.status,
    "matched",
  );
  assert.equal(
    (
      await request(`/community/posts/${post.id}`, {
        token: east,
        method: "PATCH",
        body: { status: "cancelled" },
      })
    ).status,
    200,
  );
  assert.equal(
    (await request("/community/applications", { token: west })).data.find(
      (a) => a.id === application.id,
    ).postStatus,
    "cancelled",
  );
  assert.equal((await request("/community/applications")).status, 401);
});

test("两队并发应约只确认一队，其他申请保留为未接受", async () => {
  const east = await login("captain-east"),
    west = await login("captain-west"),
    third = await login("captain-third");
  const team = (
    await request("/teams", {
      token: third,
      method: "POST",
      body: {
        name: "第三测试队",
        city: "上海",
        category: "20cm",
        roster: ["第三飞手"],
        adultOnly: true,
      },
    })
  ).data;
  const post = (
    await request("/community/posts", {
      token: east,
      method: "POST",
      body: {
        kind: "friendly",
        title: "并发应约测试",
        city: "上海",
        category: "20cm",
        level: "不限",
        availability: "周末",
        venue: "训练馆",
        body: "并发测试使用虚构数据。",
        teamId: "team-east",
        startsAt: new Date(Date.now() + 172800000).toISOString(),
      },
    })
  ).data;
  const apps = await Promise.all(
    [
      [west, "team-west"],
      [third, team.id],
    ].map(([token, teamId]) =>
      request(`/community/posts/${post.id}/applications`, {
        token,
        method: "POST",
        body: { message: "应约申请", teamId },
      }),
    ),
  );
  const results = await Promise.all(
    apps.map((a) =>
      request(`/community/applications/${a.data.id}`, {
        token: east,
        method: "PATCH",
        body: { status: "accepted" },
      }),
    ),
  );
  assert.deepEqual(results.map((r) => r.status).sort(), [200, 409]);
  const rows = (
    await request("/community/applications", { token: east })
  ).data.filter((a) => a.postId === post.id);
  assert.deepEqual(rows.map((a) => a.status).sort(), ["accepted", "rejected"]);
});

test("找队和志愿者发布可申请和撤回，私有申请不会向其他账号泄露", async () => {
  const east = await login("captain-east"),
    west = await login("captain-west"),
    third = await login("captain-third");
  for (const kind of ["seeking", "volunteer"]) {
    const post = (
      await request("/community/posts", {
        token: east,
        method: "POST",
        body: {
          kind,
          title: "活动申请验收",
          city: "上海",
          category: "20cm",
          level: "不限",
          availability: "周末",
          venue: "活动场馆",
          body: "用于验证申请撤回的活动。",
          ...(kind === "volunteer"
            ? { startsAt: new Date(Date.now() + 86400000).toISOString() }
            : {}),
        },
      })
    ).data;
    const app = (
      await request(`/community/posts/${post.id}/applications`, {
        token: west,
        method: "POST",
        body: {
          message: "仅参与双方可见的留言",
          ...(kind === "seeking" ? { teamId: "team-west" } : {}),
        },
      })
    ).data;
    assert.equal(
      (await request("/community/applications", { token: third })).data.some(
        (a) => a.id === app.id,
      ),
      false,
    );
    assert.equal(
      (
        await request(`/community/applications/${app.id}`, {
          token: west,
          method: "PATCH",
          body: { status: "withdrawn" },
        })
      ).status,
      200,
    );
    assert.equal(
      (
        await request(`/community/applications/${app.id}`, {
          token: east,
          method: "PATCH",
          body: { status: "accepted" },
        })
      ).status,
      409,
    );
  }
});

test("申请双方可持续留言，第三方不能读取或发送", async () => {
  const east = await login("captain-east"),
    west = await login("captain-west"),
    third = await login("captain-third");
  const post = (
    await request("/community/posts", {
      token: east,
      method: "POST",
      body: {
        kind: "seeking",
        title: "寻找周末训练队伍",
        city: "上海",
        category: "20cm",
        level: "入门",
        availability: "周末",
        venue: "",
        body: "希望在周末参与稳定的队伍训练。",
      },
    })
  ).data;
  const app = (
    await request(`/community/posts/${post.id}/applications`, {
      token: west,
      method: "POST",
      body: { message: "可以来试训", teamId: "team-west" },
    })
  ).data;
  const path = `/community/applications/${app.id}/messages`;
  assert.equal(
    (
      await request(path, {
        token: east,
        method: "POST",
        body: { body: "请问集合时间？" },
      })
    ).status,
    201,
  );
  assert.equal(
    (
      await request(path, {
        token: west,
        method: "POST",
        body: { body: "周六上午十点集合" },
      })
    ).status,
    201,
  );
  assert.deepEqual(
    (await request(path, { token: east })).data.map((m) => m.body),
    ["请问集合时间？", "周六上午十点集合"],
  );
  assert.equal((await request(path, { token: third })).status, 404);
  assert.equal(
    (
      await request(path, {
        token: third,
        method: "POST",
        body: { body: "不应发送成功" },
      })
    ).status,
    404,
  );
});

test("公开目录可查询队伍和机构，不公开队员名单和账号会话", async () => {
  const teams = await request("/community/teams?q=青空");
  assert.equal(teams.status, 200);
  assert.ok(teams.data.length >= 1);
  assert.ok(
    teams.data.every((t) =>
      (t.name + t.city + t.organizationName).includes("青空"),
    ),
  );
  assert.equal("roster" in teams.data[0], false);
  assert.equal("token" in teams.data[0], false);
  await pool.query(
    "INSERT INTO teams(id,organization_id,owner_id,name,city,category,roster) VALUES('directory-org-match','org-east','captain-east','机构关联测试队','南京','20cm','[]')",
  );
  const byOrganization = await request("/community/teams?q=青空");
  assert.ok(byOrganization.data.some((t) => t.id === "directory-org-match"));
  assert.ok(
    byOrganization.data.every((t) => !("roster" in t) && !("token" in t)),
  );
  const orgs = await request("/community/organizations");
  assert.equal(orgs.status, 200);
  assert.ok(orgs.data.some((o) => o.id === "org-east"));
});

test("社区按发布人和队伍查询并分页，旧记录不会被首页100条截断", async () => {
  const east = await login("captain-east");
  await pool.query(`INSERT INTO community_posts(id,author_id,kind,title,city,category,level,availability,venue,body,team_id,created_at)
    SELECT 'page-'||n,'captain-west','recruit','分页新记录'||n,'杭州','20cm','入门','周末','场馆','分页检索验证记录','team-west',now()+n*interval '1 second' FROM generate_series(1,105) n`);
  const mine = await request("/community/posts?mine=true", { token: east });
  assert.ok(mine.data.length > 0);
  assert.ok(mine.data.every((p) => p.authorId === "captain-east"));
  assert.equal((await request("/community/posts?mine=true")).status, 401);
  const scoped = await request("/community/posts?teamId=team-east");
  assert.ok(scoped.data.length > 0);
  assert.ok(scoped.data.every((p) => p.teamId === "team-east"));
  const p1 = (
    await request("/community/posts?kind=recruit&city=杭州&limit=50&offset=0")
  ).data;
  const p2 = (
    await request("/community/posts?kind=recruit&city=杭州&limit=50&offset=50")
  ).data;
  assert.equal(p1.length, 50);
  assert.equal(p2.length, 50);
  assert.equal(new Set([...p1, ...p2].map((p) => p.id)).size, 100);
  assert.equal((await request("/community/posts?offset=-1")).status, 400);
});

test("撤回后可重新申请并保留同一会话，已接受申请不会被重置", async () => {
  const east = await login("captain-east"),
    west = await login("captain-west");
  const p = await request("/community/posts", {
    token: east,
    method: "POST",
    body: {
      kind: "seeking",
      title: "重提申请验证",
      city: "上海",
      category: "20cm",
      level: "入门",
      availability: "周末",
      venue: "",
      body: "寻找可以一起训练的队伍",
    },
  });
  const first = await request(`/community/posts/${p.data.id}/applications`, {
    token: west,
    method: "POST",
    body: { message: "第一次联系", teamId: "team-west" },
  });
  await request(`/community/applications/${first.data.id}`, {
    token: west,
    method: "PATCH",
    body: { status: "withdrawn" },
  });
  const second = await request(`/community/posts/${p.data.id}/applications`, {
    token: west,
    method: "POST",
    body: { message: "重新申请联系", teamId: "team-west" },
  });
  assert.equal(second.data.id, first.data.id);
  assert.equal(second.data.status, "pending");
  assert.equal(second.data.message, "重新申请联系");
  await request(`/community/applications/${first.data.id}`, {
    token: east,
    method: "PATCH",
    body: { status: "accepted" },
  });
  assert.equal(
    (
      await request(`/community/posts/${p.data.id}/applications`, {
        token: west,
        method: "POST",
        body: { message: "再次点击", teamId: "team-west" },
      })
    ).data.status,
    "accepted",
  );
});

test("队伍成员可查看成员并退出，其他账号不能读取，退出不更改报名名单", async () => {
  const east = await login("captain-east"),
    west = await login("captain-west"),
    third = await login("captain-third");
  await pool.query(
    "INSERT INTO team_members(team_id,account_id) VALUES('team-east','captain-west') ON CONFLICT DO NOTHING",
  );
  const before = (await request("/teams", { token: east })).data.find(
    (t) => t.id === "team-east",
  ).roster;
  assert.ok(
    (
      await request("/community/teams/team-east/members", { token: west })
    ).data.some((m) => m.id === "captain-west"),
  );
  assert.equal(
    (await request("/community/teams/team-east/members", { token: third }))
      .status,
    404,
  );
  assert.equal(
    (
      await request("/community/teams/team-east/members/captain-west", {
        token: third,
        method: "DELETE",
      })
    ).status,
    403,
  );
  assert.equal(
    (
      await request("/community/teams/team-east/members/captain-west", {
        token: west,
        method: "DELETE",
      })
    ).status,
    200,
  );
  assert.ok(
    !(await request("/community/memberships", { token: west })).data.some(
      (m) => m.teamId === "team-east",
    ),
  );
  assert.deepEqual(
    (await request("/teams", { token: east })).data.find(
      (t) => t.id === "team-east",
    ).roster,
    before,
  );
});

test("留言未读按接收者隔离，已读只标记实际查看消息", async () => {
  const east = await login("captain-east"),
    west = await login("captain-west"),
    third = await login("captain-third");
  const a = (
    await request("/community/applications", { token: west })
  ).data.find((a) => a.authorId === "captain-east");
  await request(`/community/applications/${a.id}/messages`, {
    token: east,
    method: "POST",
    body: { body: "未读测试消息" },
  });
  assert.ok(
    (await request("/community/applications", { token: west })).data.find(
      (x) => x.id === a.id,
    ).unreadCount > 0,
  );
  const messages = (
    await request(`/community/applications/${a.id}/messages`, { token: west })
  ).data;
  assert.equal(
    (
      await request(`/community/applications/${a.id}/read`, {
        token: third,
        method: "POST",
        body: { messageIds: messages.map((m) => m.id) },
      })
    ).status,
    404,
  );
  assert.equal(
    (
      await request(`/community/applications/${a.id}/read`, {
        token: west,
        method: "POST",
        body: { messageIds: messages.map((m) => m.id) },
      })
    ).status,
    201,
  );
  assert.equal(
    (await request("/community/applications", { token: west })).data.find(
      (x) => x.id === a.id,
    ).unreadCount,
    0,
  );
});

test("个人资料与反馈持久化且反馈仅本人可见，公开参赛队伍不暴露名单", async () => {
  const east = await login("captain-east"),
    west = await login("captain-west");
  assert.equal(
    (
      await request("/me", {
        token: east,
        method: "PATCH",
        body: { name: "测试队长新昵称" },
      })
    ).data.name,
    "测试队长新昵称",
  );
  assert.equal(
    (await request("/me", { token: east })).data.name,
    "测试队长新昵称",
  );
  const f = await request("/feedback", {
    token: east,
    method: "POST",
    body: { category: "使用建议", body: "希望在赛事详情查看交通信息" },
  });
  assert.equal(f.status, 201);
  assert.ok(
    (await request("/feedback", { token: east })).data.some(
      (x) => x.id === f.data.id,
    ),
  );
  assert.ok(
    !(await request("/feedback", { token: west })).data.some(
      (x) => x.id === f.data.id,
    ),
  );
  assert.equal((await request("/feedback")).status, 401);
  const participants = await request("/tournaments/event-sky/participants");
  assert.equal(participants.status, 200);
  assert.ok(
    participants.data.every((x) => !("roster" in x) && !("applicantId" in x)),
  );
});

test("找队邀请必须关联自己的队伍，接受后飞手成为受邀队伍成员", async () => {
  const east = await login("captain-east"),
    west = await login("captain-west");
  const p = await request("/community/posts", {
    token: east,
    method: "POST",
    body: {
      kind: "seeking",
      title: "寻找长期训练队伍",
      city: "上海",
      category: "20cm",
      level: "进阶",
      availability: "周末",
      venue: "",
      body: "希望每周与固定队伍一起训练",
    },
  });
  assert.equal(
    (
      await request(`/community/posts/${p.data.id}/applications`, {
        token: west,
        method: "POST",
        body: { message: "欢迎加入" },
      })
    ).status,
    400,
  );
  const a = await request(`/community/posts/${p.data.id}/applications`, {
    token: west,
    method: "POST",
    body: { teamId: "team-west", message: "邀请你加入我们的队伍" },
  });
  assert.equal(a.status, 201);
  assert.equal(
    (
      await request(`/community/applications/${a.data.id}`, {
        token: east,
        method: "PATCH",
        body: { status: "accepted" },
      })
    ).status,
    200,
  );
  assert.ok(
    (await request("/community/memberships", { token: east })).data.some(
      (x) => x.teamId === "team-west",
    ),
  );
});

test("赛事赛程只允许本机构主办方发布，拒绝冲突，比分更新受版本保护", async () => {
  const host = await login("organizer-east"),
    other = await login("organizer-west"),
    captain = await login("captain-east");
  await pool.query(`INSERT INTO registrations(id,tournament_id,team_id,applicant_id,team_name,roster,status) VALUES
 ('schedule-a','event-open','team-east','captain-east','赛程测试甲队','[]','approved'),
 ('schedule-b','event-open','team-west','captain-west','赛程测试乙队','[]','approved') ON CONFLICT DO NOTHING`);
  const body = {
    homeRegistrationId: "schedule-a",
    awayRegistrationId: "schedule-b",
    startsAt: "2099-01-01T08:00:00Z",
    endsAt: "2099-01-01T08:30:00Z",
    venue: "测试场地A",
    stage: "小组赛",
    status: "scheduled",
    homeScore: null,
    awayScore: null,
    note: "",
  };
  assert.equal(
    (
      await request("/tournaments/event-open/matches", {
        token: captain,
        method: "POST",
        body,
      })
    ).status,
    403,
  );
  assert.equal(
    (
      await request("/tournaments/event-open/matches", {
        token: other,
        method: "POST",
        body,
      })
    ).status,
    403,
  );
  const created = await request("/tournaments/event-open/matches", {
    token: host,
    method: "POST",
    body,
  });
  assert.equal(created.status, 201);
  assert.equal(
    (
      await request("/tournaments/event-open/matches", {
        token: host,
        method: "POST",
        body,
      })
    ).status,
    409,
  );
  const listed = (await request("/tournaments/event-open/matches")).data;
  assert.equal(listed[0].homeName, "赛程测试甲队");
  assert.ok(!("roster" in listed[0]));
  const result = {
    ...body,
    startsAt: "2020-01-01T08:00:00Z",
    endsAt: "2020-01-01T08:30:00Z",
    status: "final",
    homeScore: 2,
    awayScore: 1,
    note: "主办方确认的比赛结果",
    version: created.data.version,
  };
  const saved = await request(
    `/tournaments/event-open/matches/${created.data.id}`,
    { token: host, method: "PUT", body: result },
  );
  assert.equal(saved.status, 200);
  assert.equal(saved.data.homeScore, 2);
  assert.equal(
    (
      await request(`/tournaments/event-open/matches/${created.data.id}`, {
        token: host,
        method: "PUT",
        body: result,
      })
    ).status,
    409,
  );
  const invalid = {
    ...body,
    homeRegistrationId: "schedule-b",
    awayRegistrationId: "schedule-b",
  };
  assert.equal(
    (
      await request("/tournaments/event-open/matches", {
        token: host,
        method: "POST",
        body: invalid,
      })
    ).status,
    400,
  );
});

test("队伍赛程按当前成员关系查询，不暴露无关比赛", async () => {
  const east = await login("captain-east"),
    third = await login("captain-third"),
    host = await login("organizer-east");
  assert.equal((await request("/me/matches")).status, 401);
  assert.ok(
    (await request("/me/matches", { token: east })).data.some(
      (m) => m.homeRegistrationId === "schedule-a",
    ),
  );
  assert.ok(
    !(await request("/me/matches", { token: third })).data.some(
      (m) => m.homeRegistrationId === "schedule-a",
    ),
  );
  assert.ok(
    (await request("/me/matches", { token: host })).data.some(
      (m) => m.homeRegistrationId === "schedule-a",
    ),
  );
});

test("并发排赛只能占用一次队伍时段，未来比赛不能直接发布结束比分", async () => {
  const host = await login("organizer-east");
  const body = {
    homeRegistrationId: "schedule-a",
    awayRegistrationId: "schedule-b",
    startsAt: "2099-01-02T08:00:00Z",
    endsAt: "2099-01-02T08:30:00Z",
    venue: "并发场地",
    stage: "交流赛",
    status: "scheduled",
    note: "",
  };
  const results = await Promise.all(
    [1, 2].map(() =>
      request("/tournaments/event-open/matches", {
        token: host,
        method: "POST",
        body,
      }),
    ),
  );
  assert.deepEqual(results.map((x) => x.status).sort(), [201, 409]);
  const futureResult = await request("/tournaments/event-open/matches", {
    token: host,
    method: "POST",
    body: { ...body, status: "final", homeScore: 2, awayScore: 1 },
  });
  assert.equal(futureResult.status, 400);
});
