import {
  Body,
  Controller,
  Get,
  Post,
  Patch,
  Headers,
  Inject,
  Param,
  Query,
  ConflictException,
  NotFoundException,
  BadRequestException,
} from "@nestjs/common";
import { Pool, PoolClient } from "pg";
import { randomUUID } from "node:crypto";
import { z } from "zod";
import { PlatformAuth } from "./platform-auth";
import { parse } from "./auth";
import { teamInput, demoRules } from "./validation";
import { matchFields, validMatch } from "./matches";
import { capacityAvailable, matchRules } from "./business-rules";
export const reasonInput = z.string().trim().min(2).max(500);
export async function platformAudit(
  c: PoolClient,
  adminId: string,
  type: string,
  id: string,
  action: string,
  reason: string,
  before: unknown,
  after: unknown,
) {
  await c.query(
    "INSERT INTO platform_audit(id,admin_id,resource_type,resource_id,action,reason,before_data,after_data) VALUES($1,$2,$3,$4,$5,$6,$7,$8)",
    [
      randomUUID(),
      adminId,
      type,
      id,
      action,
      reason,
      JSON.stringify(before),
      JSON.stringify(after),
    ],
  );
}
const resources = {
  organizations: "organizations",
  teams: "teams",
  tournaments: "tournaments",
  registrations: "registrations",
  matches: "matches",
  posts: "community_posts",
  applications: "community_applications",
  users: "accounts",
  feedback: "feedback",
  audit: "platform_audit",
  content: "platform_content",
} as const;
type Resource = keyof typeof resources;
function resource(value: string): Resource {
  if (!Object.hasOwn(resources, value)) throw new NotFoundException();
  return value as Resource;
}
const label = z.string().trim().min(2).max(80);
const roster = teamInput.shape.roster;
export const tournamentEdit = z
  .object({
    title: label,
    city: label,
    venue: label,
    organization_id: z.string().min(1),
    category: z.enum(["20cm", "40cm"]),
    capacity: z.number().int().min(1).max(128),
    starts_at: z.iso.datetime(),
    deadline: z.iso.datetime(),
    description: z.string().trim().min(4).max(2000),
    rules: z.string().trim().min(4).max(5000),
  })
  .strict()
  .refine((v) => Date.parse(v.starts_at) > Date.parse(v.deadline), {
    message: "比赛开始必须晚于报名截止",
  });
const moderation = z.object({ hidden: z.boolean() }).strict();
@Controller("platform")
export class PlatformController {
  constructor(
    @Inject("DB") private db: Pool,
    private auth: PlatformAuth,
  ) {}
  @Get("overview") async overview(@Headers("authorization") h?: string) {
    await this.auth.actor(h);
    const row = (
      await this.db.query(
        `SELECT (SELECT count(*)::int FROM tournaments) AS tournaments,(SELECT count(*)::int FROM registrations WHERE status='pending') AS pending,(SELECT count(*)::int FROM accounts WHERE NOT disabled) AS users,(SELECT count(*)::int FROM feedback WHERE status<>'resolved') AS feedback,(SELECT count(*)::int FROM community_posts WHERE NOT hidden AND status='open') AS posts`,
      )
    ).rows[0];
    return {
      ...row,
      recentContent: (
        await this.db.query(
          "SELECT id,kind,published,updated_at FROM platform_content WHERE published IS NOT NULL ORDER BY updated_at DESC LIMIT 5",
        )
      ).rows,
    };
  }
  @Get("lookups") async lookups(@Headers("authorization") h?: string) {
    await this.auth.actor(h);
    return {
      organizations: (
        await this.db.query(
          "SELECT id,name,city FROM organizations ORDER BY name",
        )
      ).rows,
      teams: (
        await this.db.query(
          "SELECT id,name,organization_id FROM teams ORDER BY name",
        )
      ).rows,
      tournaments: (
        await this.db.query(
          "SELECT id,title FROM tournaments ORDER BY starts_at DESC",
        )
      ).rows,
    };
  }
  @Get(":resource") async list(
    @Param("resource") r: string,
    @Query() query: Record<string, string>,
    @Headers("authorization") h?: string,
  ) {
    await this.auth.actor(h);
    const key = resource(r),
      table = resources[key];
    const q = parse(
      z.object({
        q: z.string().max(100).default(""),
        offset: z.coerce.number().int().min(0).default(0),
        limit: z.coerce.number().int().min(1).max(100).default(30),
        parent: z.string().max(100).default(""),
        status: z.string().max(40).default(""),
      }),
      query,
    );
    const parentColumn =
      key === "registrations" || key === "matches"
        ? "tournament_id"
        : key === "applications"
          ? "post_id"
          : key === "audit"
            ? "resource_id"
            : ["organizations"].includes(key)
              ? null
              : ["teams", "users", "tournaments"].includes(key)
                ? "organization_id"
                : null;
    const statusColumn = [
      "registrations",
      "matches",
      "posts",
      "applications",
      "feedback",
    ].includes(key)
      ? "status"
      : null;
    const where = `($1='' OR (${key === "applications" ? "to_jsonb(t)-'message'" : "to_jsonb(t)"})::text ILIKE $1) AND ($2='' OR ${parentColumn ? "t." + parentColumn : "''"}=$2) AND ($3='' OR ${statusColumn ? "t." + statusColumn : "''"}=$3)`;
    const args = [q.q ? `%${q.q}%` : "", q.parent, q.status];
    const projection =
      key === "applications" ? "to_jsonb(t)-'message'" : "to_jsonb(t)";
    const rows = (
      await this.db.query(
        `SELECT ${projection} AS data FROM ${table} t WHERE ${where} ORDER BY ${["audit", "posts", "applications", "feedback"].includes(key) ? "t.created_at DESC," : ""}t.id LIMIT $4 OFFSET $5`,
        [...args, q.limit, q.offset],
      )
    ).rows.map((x) => x.data);
    const total = (
      await this.db.query(
        `SELECT count(*)::int AS n FROM ${table} t WHERE ${where}`,
        args,
      )
    ).rows[0].n;
    return { rows, total };
  }
  @Get("teams/:id/members") async members(
    @Param("id") id: string,
    @Headers("authorization") h?: string,
  ) {
    await this.auth.actor(h);
    return (
      await this.db.query(
        `SELECT a.id,a.name,a.id=t.owner_id AS is_owner FROM teams t JOIN accounts a ON a.id=t.owner_id OR EXISTS(SELECT 1 FROM team_members m WHERE m.team_id=t.id AND m.account_id=a.id) WHERE t.id=$1 ORDER BY (a.id=t.owner_id) DESC,a.name`,
        [id],
      )
    ).rows;
  }
  @Post("teams/:id/remove-member") async removeMember(
    @Param("id") id: string,
    @Headers("authorization") h: string | undefined,
    @Body() body: unknown,
  ) {
    const actor = await this.auth.actor(h),
      v = parse(
        z.object({ accountId: z.string(), reason: reasonInput }).strict(),
        body,
      );
    const c = await this.db.connect();
    try {
      await c.query("BEGIN");
      const t = (
        await c.query("SELECT * FROM teams WHERE id=$1 FOR UPDATE", [id])
      ).rows[0];
      if (!t) throw new NotFoundException();
      if (t.owner_id === v.accountId)
        throw new ConflictException("不能移除队伍负责人");
      const old = (
        await c.query(
          "DELETE FROM team_members WHERE team_id=$1 AND account_id=$2 RETURNING *",
          [id, v.accountId],
        )
      ).rows[0];
      if (!old) throw new NotFoundException("成员不存在");
      await platformAudit(
        c,
        actor.id,
        "teams",
        id,
        "member.remove",
        v.reason,
        old,
        null,
      );
      await c.query("COMMIT");
      return { ok: true };
    } catch (e) {
      await c.query("ROLLBACK");
      throw e;
    } finally {
      c.release();
    }
  }
  @Post("applications/:id/inspect") async inspect(
    @Param("id") id: string,
    @Headers("authorization") h: string | undefined,
    @Body() body: unknown,
  ) {
    const actor = await this.auth.actor(h),
      v = parse(z.object({ reason: reasonInput }).strict(), body);
    const c = await this.db.connect();
    try {
      await c.query("BEGIN");
      const application = (
        await c.query("SELECT * FROM community_applications WHERE id=$1", [id])
      ).rows[0];
      if (!application) throw new NotFoundException();
      const messages = (
        await c.query(
          "SELECT m.*,a.name AS sender_name FROM community_messages m JOIN accounts a ON a.id=m.sender_id WHERE application_id=$1 ORDER BY created_at,id",
          [id],
        )
      ).rows;
      await platformAudit(
        c,
        actor.id,
        "applications",
        id,
        "conversation.inspect",
        v.reason,
        null,
        { messageCount: messages.length },
      );
      await c.query("COMMIT");
      return { application, messages };
    } catch (e) {
      await c.query("ROLLBACK");
      throw e;
    } finally {
      c.release();
    }
  }
  @Post(":resource") async create(
    @Param("resource") r: string,
    @Headers("authorization") h: string | undefined,
    @Body() body: unknown,
  ) {
    const actor = await this.auth.actor(h),
      key = resource(r);
    const envelope = parse(
      z
        .object({
          reason: reasonInput,
          values: z.record(z.string(), z.unknown()),
        })
        .strict(),
      body,
    );
    if (key !== "organizations" && key !== "tournaments" && key !== "matches")
      throw new BadRequestException("此模块不支持新增");
    const c = await this.db.connect(),
      id = randomUUID();
    try {
      await c.query("BEGIN");
      if (key === "organizations") {
        const v = parse(
          z.object({ name: label, city: label }).strict(),
          envelope.values,
        );
        await c.query(
          "INSERT INTO organizations(id,name,city) VALUES($1,$2,$3)",
          [id, v.name, v.city],
        );
      }
      if (key === "tournaments") {
        const v = parse(tournamentEdit, envelope.values);
        if (Date.parse(v.deadline) <= Date.now())
          throw new BadRequestException("新赛事报名截止须晚于现在");
        await this.saveTournament(c, id, v);
      }
      if (key === "matches") {
        const v = parse(
          z
            .object({ ...matchFields, tournamentId: z.string().min(1) })
            .strict()
            .refine(validMatch, { message: "请核对队伍、时间、比分" }),
          envelope.values,
        );
        await this.saveMatch(c, id, v, true);
      }
      const row = (
        await c.query(`SELECT * FROM ${resources[key]} WHERE id=$1`, [id])
      ).rows[0];
      await platformAudit(
        c,
        actor.id,
        key,
        id,
        "create",
        envelope.reason,
        null,
        row,
      );
      await c.query("COMMIT");
      return row;
    } catch (e) {
      await c.query("ROLLBACK");
      throw e;
    } finally {
      c.release();
    }
  }
  @Patch(":resource/:id") async update(
    @Param("resource") r: string,
    @Param("id") id: string,
    @Headers("authorization") h: string | undefined,
    @Body() body: unknown,
  ) {
    const actor = await this.auth.actor(h),
      key = resource(r);
    if (["audit", "applications", "content"].includes(key))
      throw new BadRequestException("请使用专用操作");
    const v = parse(
        z
          .object({
            version: z.number().int().positive(),
            reason: reasonInput,
            values: z.record(z.string(), z.unknown()),
          })
          .strict(),
        body,
      ),
      c = await this.db.connect();
    try {
      await c.query("BEGIN");
      // The same tournament lock order as mobile review / match publication prevents cross-client races.
      if (key === "registrations" || key === "matches") {
        const ref = (
          await c.query(
            `SELECT tournament_id FROM ${resources[key]} WHERE id=$1`,
            [id],
          )
        ).rows[0];
        if (!ref) throw new NotFoundException();
        await c.query("SELECT id FROM tournaments WHERE id=$1 FOR UPDATE", [
          ref.tournament_id,
        ]);
      }
      const old = (
        await c.query(
          `SELECT * FROM ${resources[key]} WHERE id=$1 FOR UPDATE`,
          [id],
        )
      ).rows[0];
      if (!old) throw new NotFoundException();
      if (old.version !== v.version)
        throw new ConflictException("内容已被修改，请刷新后重试");
      let values: Record<string, unknown> = {};
      if (key === "users") {
        values = parse(
          z.object({ name: label, disabled: z.boolean() }).strict(),
          v.values,
        );
        if (values.disabled)
          await c.query("DELETE FROM sessions WHERE account_id=$1", [id]);
      }
      if (key === "organizations")
        values = parse(
          z.object({ name: label, city: label }).strict(),
          v.values,
        );
      if (key === "teams") {
        const d = parse(teamInput, v.values);
        values = {
          name: d.name,
          city: d.city,
          category: d.category,
          roster: JSON.stringify(d.roster),
        };
      }
      if (key === "feedback")
        values = parse(
          z
            .object({
              status: z.enum(["received", "processing", "resolved"]),
              reply: z.string().trim().min(2).max(2000),
            })
            .strict(),
          v.values,
        );
      if (
        key === "posts" ||
        (key === "tournaments" && Object.hasOwn(v.values, "hidden"))
      ) {
        const d = parse(moderation, v.values);
        values = { hidden: d.hidden, moderation_reason: v.reason };
      } else if (key === "tournaments") {
        const d = parse(tournamentEdit, v.values);
        if (d.organization_id !== old.organization_id)
          throw new ConflictException("已有赛事不能更换所属机构");
        if (
          d.category !== old.category &&
          (
            await c.query(
              "SELECT id FROM registrations WHERE tournament_id=$1 LIMIT 1",
              [id],
            )
          ).rowCount
        )
          throw new ConflictException("已有报名，不能更换设备级别");
        const occupied = (
          await c.query(
            "SELECT count(*)::int AS n FROM registrations WHERE tournament_id=$1 AND status='approved'",
            [id],
          )
        ).rows[0].n;
        if (d.capacity < occupied)
          throw new ConflictException("名额不能少于已通过报名数");
        values = d;
      }
      if (key === "registrations") {
        const d = parse(
          z
            .object({
              status: z.enum(["pending", "approved", "rejected"]),
              review_note: z.string().trim().max(500),
              roster,
            })
            .strict(),
          v.values,
        );
        if (
          old.status === "approved" &&
          d.status !== "approved" &&
          (
            await c.query(
              "SELECT id FROM matches WHERE status<>'cancelled' AND (home_registration_id=$1 OR away_registration_id=$1) LIMIT 1",
              [id],
            )
          ).rowCount
        )
          throw new ConflictException("请先取消或调整关联赛程，再撤销参赛资格");
        if (d.status === "approved") {
          const t = (
            await c.query("SELECT * FROM tournaments WHERE id=$1", [
              old.tournament_id,
            ])
          ).rows[0];
          const team = (
            await c.query("SELECT category FROM teams WHERE id=$1", [
              old.team_id,
            ])
          ).rows[0];
          if (team.category !== t.category)
            throw new ConflictException("设备级别与赛事不一致");
          await capacityAvailable(c, t.id, t.capacity, id);
        }
        values = {
          status: d.status,
          review_note: d.review_note,
          roster: JSON.stringify(d.roster),
          reviewer_id: null,
          platform_reviewer_id: actor.id,
          reviewed_at: new Date(),
        };
      }
      if (key === "matches") {
        const d = parse(
          z
            .object(matchFields)
            .strict()
            .refine(validMatch, { message: "请核对队伍、时间、比分" }),
          v.values,
        );
        await this.saveMatch(
          c,
          id,
          { ...d, tournamentId: old.tournament_id },
          false,
        );
      } else {
        const entries = Object.entries(values);
        if (!entries.length) throw new BadRequestException("没有可修改字段");
        await c.query(
          `UPDATE ${resources[key]} SET ${entries.map(([k], i) => `${k}=$${i + 2}`).join(",")},version=version+1 WHERE id=$1`,
          [id, ...entries.map(([, value]) => value)],
        );
      }
      const row = (
        await c.query(`SELECT * FROM ${resources[key]} WHERE id=$1`, [id])
      ).rows[0];
      await platformAudit(c, actor.id, key, id, "update", v.reason, old, row);
      await c.query("COMMIT");
      return row;
    } catch (e) {
      await c.query("ROLLBACK");
      throw e;
    } finally {
      c.release();
    }
  }
  private async saveTournament(
    c: PoolClient,
    id: string,
    v: z.infer<typeof tournamentEdit>,
  ) {
    if (
      !(
        await c.query("SELECT id FROM organizations WHERE id=$1", [
          v.organization_id,
        ])
      ).rowCount
    )
      throw new BadRequestException("机构不存在");
    await c.query(
      "INSERT INTO tournaments(id,title,city,venue,organization_id,category,capacity,starts_at,deadline,description,rules) VALUES($1,$2,$3,$4,$5,$6,$7,$8,$9,$10,$11)",
      [
        id,
        v.title,
        v.city,
        v.venue,
        v.organization_id,
        v.category,
        v.capacity,
        v.starts_at,
        v.deadline,
        v.description,
        v.rules || demoRules,
      ],
    );
  }
  private async saveMatch(
    c: PoolClient,
    id: string,
    v: z.infer<typeof zMatch>,
    create: boolean,
  ) {
    if (
      !(
        await c.query("SELECT id FROM tournaments WHERE id=$1 FOR UPDATE", [
          v.tournamentId,
        ])
      ).rowCount
    )
      throw new NotFoundException("赛事不存在");
    await matchRules(c, v.tournamentId, create ? null : id, v);
    await c.query(
      `INSERT INTO matches(id,tournament_id,home_registration_id,away_registration_id,starts_at,ends_at,venue,stage,status,home_score,away_score,note) VALUES($1,$2,$3,$4,$5,$6,$7,$8,$9,$10,$11,$12) ON CONFLICT(id) DO UPDATE SET home_registration_id=$3,away_registration_id=$4,starts_at=$5,ends_at=$6,venue=$7,stage=$8,status=$9,home_score=$10,away_score=$11,note=$12,version=matches.version+1`,
      [
        id,
        v.tournamentId,
        v.homeRegistrationId,
        v.awayRegistrationId,
        v.startsAt,
        v.endsAt,
        v.venue,
        v.stage,
        v.status,
        v.homeScore,
        v.awayScore,
        v.note,
      ],
    );
  }
}
const zMatch = z.object({ ...matchFields, tournamentId: z.string() });
