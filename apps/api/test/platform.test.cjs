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
  await require("../dist/platform-auth").createPlatformAdmin(
    pool,
    "operator-test",
    "Platform-Test-Only-2026!",
  );
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
test("平台接口独立鉴权，普通移动端会话不能进入", async () => {
  assert.equal((await request("/platform/me")).status, 401);
  const login = await request("/dev/sessions", {
    method: "POST",
    body: { accountId: "organizer-east" },
  });
  assert.equal(
    (await request("/platform/me", { token: login.data.token })).status,
    401,
  );
});

async function platformLogin() {
  const r = await request("/platform/sessions", {
    method: "POST",
    body: { username: "operator-test", password: "Platform-Test-Only-2026!" },
  });
  assert.equal(r.status, 201);
  return r.data.token;
}
async function businessLogin(accountId) {
  return (
    await request("/dev/sessions", { method: "POST", body: { accountId } })
  ).data.token;
}
const reason = "本地平台回归验证";
const future = (days) => new Date(Date.now() + days * 86400000).toISOString();
async function event(token, capacity = 2) {
  const r = await request("/platform/tournaments", {
    token,
    method: "POST",
    body: {
      reason,
      values: {
        title: "平台回归赛事",
        city: "上海",
        venue: "验证场馆",
        organization_id: "org-east",
        category: "20cm",
        capacity,
        starts_at: future(14),
        deadline: future(7),
        description: "验证平台与移动端共用业务校验",
        rules: "本地成年演示规则",
      },
    },
  });
  assert.equal(r.status, 201, JSON.stringify(r.data));
  return r.data;
}
async function update(token, type, row, values) {
  return request(`/platform/${type}/${row.id}`, {
    token,
    method: "PATCH",
    body: { version: row.version, reason, values },
  });
}
test("平台身份不能混用移动端身份，退出后会话失效", async () => {
  const token = await platformLogin();
  assert.equal((await request("/platform/me", { token })).status, 200);
  assert.equal((await request("/me", { token })).status, 401);
  assert.equal(
    (await request("/platform/session", { token, method: "DELETE" })).status,
    200,
  );
  assert.equal((await request("/platform/overview", { token })).status, 401);
});
test("内容草稿与发布隔离，城市与时间过滤，版本冲突及空发布结果", async () => {
  const token = await platformLogin();
  const data = {
    title: "运营回归内容",
    subtitle: "测试说明",
    body: "测试正文",
    city: "上海",
    startsAt: future(-1),
    endsAt: future(1),
    assetId: "field-photo",
    attribution: "CC0",
    sort: 5,
    action: { type: "external", id: "", url: "https://example.com/event" },
    sourceURL: "",
  };
  const draft = await request("/platform/content", {
    token,
    method: "POST",
    body: { kind: "advert", reason, data },
  });
  assert.equal(draft.status, 201);
  let row = draft.data;
  assert(
    !(await request("/content?city=上海")).data.some((r) => r.id === row.id),
  );
  let pub = await request("/platform/content/" + row.id, {
    token,
    method: "PUT",
    body: { version: row.version, reason, operation: "publish" },
  });
  assert.equal(pub.status, 200);
  row = pub.data;
  assert(
    (await request("/content?city=上海")).data.some((r) => r.id === row.id),
  );
  assert(
    !(await request("/content?city=杭州")).data.some((r) => r.id === row.id),
  );
  assert(
    !(await request("/content?city=全国")).data.some((r) => r.id === row.id),
  );
  const save = await request("/platform/content/" + row.id, {
    token,
    method: "PUT",
    body: {
      version: row.version,
      reason,
      operation: "save",
      data: { ...data, title: "尚未发布的修改" },
    },
  });
  assert.equal(save.status, 200);
  assert.equal(
    (await request("/content?city=上海")).data.find((r) => r.id === row.id)
      .title,
    data.title,
  );
  assert.equal(
    (
      await request("/platform/content/" + row.id, {
        token,
        method: "PUT",
        body: { version: row.version, reason, operation: "publish" },
      })
    ).status,
    409,
  );
  row = save.data;
  assert.equal(
    (
      await request("/platform/content/" + row.id, {
        token,
        method: "PUT",
        body: { version: row.version, reason, operation: "unpublish" },
      })
    ).status,
    200,
  );
  assert(
    !(await request("/content?city=上海")).data.some((r) => r.id === row.id),
  );
  assert.equal(
    (
      await request("/platform/content", {
        token,
        method: "POST",
        body: {
          kind: "advert",
          reason,
          data: {
            ...data,
            action: { type: "external", id: "", url: "javascript:alert(1)" },
          },
        },
      })
    ).status,
    400,
  );
  const expired = await request("/platform/content", {
    token,
    method: "POST",
    body: {
      kind: "advert",
      reason,
      data: { ...data, startsAt: future(-2), endsAt: future(-1) },
    },
  });
  await request("/platform/content/" + expired.data.id, {
    token,
    method: "PUT",
    body: { version: 1, reason, operation: "publish" },
  });
  assert(
    !(await request("/content?city=上海")).data.some(
      (r) => r.id === expired.data.id,
    ),
  );
});
test("素材上传验证内容类型，拒绝伪装图片，保留来源及审计", async () => {
  const token = await platformLogin();
  assert.equal(
    (
      await request("/platform/assets", {
        token,
        method: "POST",
        body: {
          data: Buffer.from("<script>bad</script>").toString("base64"),
          attribution: "测试",
          reason,
        },
      })
    ).status,
    400,
  );
  const r = await request("/platform/assets", {
    token,
    method: "POST",
    body: {
      data: "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mP8/x8AAwMCAO+a7yoAAAAASUVORK5CYII=",
      attribution: "本地测试图",
      reason,
    },
  });
  assert.equal(r.status, 201);
  const response = await fetch(base + "/content/assets/" + r.data.id);
  assert.equal(response.status, 200);
  assert.equal(response.headers.get("content-type"), "image/png");
  const audit = (
    await request("/platform/audit?parent=" + r.data.id, { token })
  ).data.rows;
  assert.equal(audit[0].action, "upload");
  await require("node:fs/promises").unlink(
    require("node:path").join(
      require("../dist/platform-content").uploadDirectory(),
      r.data.filename,
    ),
  );
});
test("平台与主办方并发审核不能超额，纠错保留旧名单与历史版本", async () => {
  const token = await platformLogin(),
    captain = await businessLogin("captain-east"),
    other = await businessLogin("captain-west"),
    organizer = await businessLogin("organizer-east");
  const t = await event(token, 1);
  const a = (
    await request("/tournaments/" + t.id + "/registrations", {
      token: captain,
      method: "POST",
      body: { teamId: "team-east", acceptRules: true },
    })
  ).data;
  const b = (
    await request("/tournaments/" + t.id + "/registrations", {
      token: other,
      method: "POST",
      body: { teamId: "team-west", acceptRules: true },
    })
  ).data;
  const results = await Promise.all([
    update(token, "registrations", a, {
      status: "approved",
      review_note: "通过",
      roster: a.roster,
    }),
    request("/admin/registrations/" + b.id + "/review", {
      token: organizer,
      method: "POST",
      body: { status: "approved", note: "通过", version: b.version },
    }),
  ]);
  assert.equal(results.filter((r) => [200, 201].includes(r.status)).length, 1);
  assert.equal(results.filter((r) => r.status === 409).length, 1);
  const current = (
    await request("/platform/registrations?parent=" + t.id, { token })
  ).data.rows.find((r) => r.id === a.id);
  const corrected = await update(token, "registrations", current, {
    status: current.status,
    review_note: "核对名单",
    roster: ["纠错后的成年演示人员"],
  });
  assert.equal(corrected.status, 200, JSON.stringify(corrected.data));
  const logs = (await request("/platform/audit?parent=" + a.id, { token })).data
    .rows;
  assert.deepEqual(logs[0].before_data.roster, a.roster);
  assert.deepEqual(logs[0].after_data.roster, ["纠错后的成年演示人员"]);
  assert.equal(
    (
      await update(token, "registrations", current, {
        status: "pending",
        review_note: "过期版本",
        roster: a.roster,
      })
    ).status,
    409,
  );
});
test("平台代排赛共用冲突检查，撤销资格必须先处理赛程，比分可留痕纠错", async () => {
  const token = await platformLogin(),
    t = await event(token),
    aToken = await businessLogin("captain-east"),
    bToken = await businessLogin("captain-west");
  const regs = [];
  for (const [bt, teamId] of [
    [aToken, "team-east"],
    [bToken, "team-west"],
  ]) {
    const r = (
      await request("/tournaments/" + t.id + "/registrations", {
        token: bt,
        method: "POST",
        body: { teamId, acceptRules: true },
      })
    ).data;
    regs.push(
      (
        await update(token, "registrations", r, {
          status: "approved",
          review_note: "通过",
          roster: r.roster,
        })
      ).data,
    );
  }
  const values = {
    tournamentId: t.id,
    homeRegistrationId: regs[0].id,
    awayRegistrationId: regs[1].id,
    startsAt: future(-2),
    endsAt: future(-1),
    venue: "回归场馆",
    stage: "决赛",
    status: "final",
    homeScore: 2,
    awayScore: 1,
    note: "",
  };
  let r = await request("/platform/matches", {
    token,
    method: "POST",
    body: { reason, values },
  });
  assert.equal(r.status, 201, JSON.stringify(r.data));
  const old = r.data;
  assert.equal(
    (
      await request("/platform/matches", {
        token,
        method: "POST",
        body: { reason, values },
      })
    ).status,
    409,
  );
  assert.equal(
    (
      await update(token, "registrations", regs[0], {
        status: "rejected",
        review_note: "撤销",
        roster: regs[0].roster,
      })
    ).status,
    409,
  );
  const { tournamentId, ...matchValues } = values;
  r = await update(token, "matches", old, { ...matchValues, homeScore: 3 });
  assert.equal(r.status, 200);
  assert.equal(
    (await request("/tournaments/" + t.id + "/matches")).data[0].homeScore,
    3,
  );
  const log = (await request("/platform/audit?parent=" + old.id, { token }))
    .data.rows[0];
  assert.equal(log.before_data.home_score, 2);
  assert.equal(log.after_data.home_score, 3);
});
test("平台下架赛事退出公开访问，保留参与者历史，拒绝新增报名", async () => {
  const token = await platformLogin(),
    t = await event(token),
    captain = await businessLogin("captain-east"),
    other = await businessLogin("captain-west");
  await request("/tournaments/" + t.id + "/registrations", {
    token: captain,
    method: "POST",
    body: { teamId: "team-east", acceptRules: true },
  });
  const hidden = await update(token, "tournaments", t, { hidden: true });
  assert.equal(hidden.status, 200);
  assert(!(await request("/tournaments")).data.some((r) => r.id === t.id));
  assert.equal((await request("/tournaments/" + t.id)).status, 404);
  assert.equal(
    (await request("/tournaments/" + t.id, { token: captain })).data.hidden,
    true,
  );
  assert.equal(
    (
      await request("/tournaments/" + t.id + "/registrations", {
        token: other,
        method: "POST",
        body: { teamId: "team-west", acceptRules: true },
      })
    ).status,
    409,
  );
  assert.equal(
    (await update(token, "tournaments", hidden.data, { hidden: false })).status,
    200,
  );
});
test("反馈回复移动端可见，停用账号撤销旧会话，恢复不复活旧会话", async () => {
  const token = await platformLogin(),
    user = await businessLogin("captain-third");
  const feedback = (
    await request("/feedback", {
      token: user,
      method: "POST",
      body: { category: "功能问题", body: "这是平台反馈回复的回归测试内容" },
    })
  ).data;
  const current = (
    await request("/platform/feedback?parent=", { token })
  ).data.rows.find((r) => r.id === feedback.id);
  assert.equal(
    (
      await update(token, "feedback", current, {
        status: "resolved",
        reply: "已核查并修复",
      })
    ).status,
    200,
  );
  assert.equal(
    (await request("/feedback", { token: user })).data[0].reply,
    "已核查并修复",
  );
  let account = (await request("/platform/users?q=captain-third", { token }))
    .data.rows[0];
  const disabled = await update(token, "users", account, {
    name: account.name,
    disabled: true,
  });
  assert.equal(disabled.status, 200);
  assert.equal((await request("/me", { token: user })).status, 401);
  assert.equal(
    (
      await request("/dev/sessions", {
        method: "POST",
        body: { accountId: "captain-third" },
      })
    ).status,
    401,
  );
  await update(token, "users", disabled.data, {
    name: account.name,
    disabled: false,
  });
  assert.equal((await request("/me", { token: user })).status, 401);
});
test("社区下架与私有会话调阅隔离，调阅不改变未读数", async () => {
  const token = await platformLogin(),
    author = await businessLogin("captain-east"),
    applicant = await businessLogin("captain-west");
  const p = (
    await request("/community/posts", {
      token: author,
      method: "POST",
      body: {
        kind: "recruit",
        title: "平台巡查回归招募",
        city: "上海",
        category: "20cm",
        level: "入门",
        availability: "周末",
        venue: "本地场馆",
        body: "仅限本地测试资料的招募说明",
        teamId: "team-east",
      },
    })
  ).data;
  assert.ok(p.id);
  const a = (
    await request("/community/posts/" + p.id + "/applications", {
      token: applicant,
      method: "POST",
      body: { message: "申请加入测试队伍" },
    })
  ).data;
  await request("/community/applications/" + a.id + "/messages", {
    token: applicant,
    method: "POST",
    body: { body: "用于验证平台调阅的私有留言" },
  });
  const before = (
    await request("/community/applications", { token: author })
  ).data.find((r) => r.id === a.id).unreadCount;
  assert.equal(
    (
      await request("/platform/applications/" + a.id + "/inspect", {
        token,
        method: "POST",
        body: { reason: "" },
      })
    ).status,
    400,
  );
  const read = await request("/platform/applications/" + a.id + "/inspect", {
    token,
    method: "POST",
    body: { reason: "处理本地测试投诉" },
  });
  assert.equal(read.status, 201);
  assert.equal(read.data.messages.length, 1);
  assert.equal(
    (await request("/community/applications", { token: author })).data.find(
      (r) => r.id === a.id,
    ).unreadCount,
    before,
  );
  assert.equal(
    (await request("/platform/applications?parent=" + p.id, { token })).data
      .rows[0].message,
    undefined,
  );
  const post = (await request("/platform/posts?q=" + p.id, { token })).data
    .rows[0];
  assert.equal(
    (await update(token, "posts", post, { hidden: true })).status,
    200,
  );
  assert.equal((await request("/community/posts/" + p.id)).status, 404);
  assert.equal(
    (await request("/community/posts/" + p.id, { token: applicant })).data
      .hidden,
    true,
  );
  assert(!(await request("/community/posts")).data.some((r) => r.id === p.id));
  assert.equal(
    (
      await request("/community/applications/" + a.id, {
        token: author,
        method: "PATCH",
        body: { status: "accepted" },
      })
    ).status,
    409,
  );
  const log = (await request("/platform/audit?parent=" + a.id, { token })).data
    .rows[0];
  assert.equal(log.action, "conversation.inspect");
});

test("发布前拒绝不存在的指南与已下架赛事目标", async () => {
  const token = await platformLogin();
  for (const type of ["guide", "tournament"]) {
    const draft = await request("/platform/content", {
      token,
      method: "POST",
      body: {
        kind: "hero",
        reason,
        data: {
          title: "无效目标回归",
          assetId: "field-photo",
          action: { type, id: "missing-target", url: "" },
        },
      },
    });
    assert.equal(draft.status, 201);
    const published = await request("/platform/content/" + draft.data.id, {
      token,
      method: "PUT",
      body: { version: 1, reason, operation: "publish" },
    });
    assert.equal(published.status, 400);
    assert(
      !(await request("/content")).data.some((x) => x.id === draft.data.id),
    );
  }
});

test("移除成员保留历史报名，禁止移除负责人，机构关联可筛选", async () => {
  const token = await platformLogin();
  await pool.query(
    "INSERT INTO team_members(team_id,account_id) VALUES('team-east','captain-third') ON CONFLICT DO NOTHING",
  );
  const before = (
    await pool.query(
      "SELECT id,roster FROM registrations WHERE team_id='team-east' ORDER BY id",
    )
  ).rows;
  assert.equal(
    (
      await request("/platform/teams/team-east/remove-member", {
        token,
        method: "POST",
        body: { accountId: "captain-east", reason },
      })
    ).status,
    409,
  );
  assert.equal(
    (
      await request("/platform/teams/team-east/remove-member", {
        token,
        method: "POST",
        body: { accountId: "captain-third", reason },
      })
    ).status,
    201,
  );
  assert.deepEqual(
    (
      await pool.query(
        "SELECT id,roster FROM registrations WHERE team_id='team-east' ORDER BY id",
      )
    ).rows,
    before,
  );
  assert(
    (
      await request("/platform/teams?parent=org-east", { token })
    ).data.rows.every((x) => x.organization_id === "org-east"),
  );
  const logs = (await request("/platform/audit?parent=team-east", { token }))
    .data.rows;
  assert(
    logs.some(
      (x) =>
        x.action === "member.remove" &&
        x.before_data.account_id === "captain-third",
    ),
  );
});
