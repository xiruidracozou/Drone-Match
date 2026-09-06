import {
  BadRequestException,
  Body,
  ConflictException,
  Controller,
  ForbiddenException,
  Get,
  Headers,
  Inject,
  NotFoundException,
  Param,
  Patch,
  Post,
  Query,
} from "@nestjs/common";
import { randomUUID } from "node:crypto";
import { Pool, PoolClient } from "pg";
import { z } from "zod";
import { Auth, parse } from "./auth";

const label = z.string().trim().min(2).max(80);
const postInput = z
  .object({
    kind: z.enum(["recruit", "seeking", "friendly", "volunteer"]),
    title: label,
    city: label,
    category: z.enum(["20cm", "40cm"]),
    level: label,
    availability: label,
    venue: z.string().trim().max(120),
    body: z.string().trim().min(8).max(2000),
    teamId: z.string().min(1).max(100).optional(),
    startsAt: z.iso.datetime().optional(),
  })
  .strict()
  .superRefine((v, c) => {
    if ((v.kind === "recruit" || v.kind === "friendly") && !v.teamId)
      c.addIssue({ code: "custom", message: "请选择队伍", path: ["teamId"] });
    if (
      (v.kind === "friendly" || v.kind === "volunteer") &&
      (!v.startsAt || Date.parse(v.startsAt) <= Date.now())
    )
      c.addIssue({
        code: "custom",
        message: "请选择未来的活动时间",
        path: ["startsAt"],
      });
    if ((v.kind === "friendly" || v.kind === "volunteer") && v.venue.length < 2)
      c.addIssue({ code: "custom", message: "请填写场地", path: ["venue"] });
  });
const selection = `SELECT p.id,p.author_id AS "authorId",a.name AS "authorName",o.name AS "organizationName",p.kind,p.title,p.city,p.category,p.level,p.availability,p.venue,p.body,p.team_id AS "teamId",t.name AS "teamName",p.starts_at AS "startsAt",p.status,p.created_at AS "createdAt",
 (SELECT count(*)::int FROM community_applications ca WHERE ca.post_id=p.id AND ca.status IN ('pending','accepted')) AS "applicationCount"
 FROM community_posts p JOIN accounts a ON a.id=p.author_id JOIN organizations o ON o.id=a.organization_id LEFT JOIN teams t ON t.id=p.team_id`;
const applicationSelection = `SELECT ca.id,ca.post_id AS "postId",ca.applicant_id AS "applicantId",a.name AS "applicantName",ca.team_id AS "teamId",t.name AS "teamName",ca.message,ca.status,ca.created_at AS "createdAt",p.author_id AS "authorId",p.title AS "postTitle",p.kind,p.status AS "postStatus",p.city,p.category
 FROM community_applications ca JOIN community_posts p ON p.id=ca.post_id JOIN accounts a ON a.id=ca.applicant_id LEFT JOIN teams t ON t.id=ca.team_id`;
const missing = () =>
  new NotFoundException({ code: "NOT_FOUND", message: "信息不存在或无权修改" });
const conflict = (message: string) =>
  new ConflictException({ code: "STATE_CONFLICT", message });
async function ownedTeam(
  db: Pool | PoolClient,
  id: string,
  owner: string,
  category: string,
) {
  const team = (
    await db.query("SELECT category FROM teams WHERE id=$1 AND owner_id=$2", [
      id,
      owner,
    ])
  ).rows[0];
  if (!team)
    throw new ForbiddenException({
      code: "FORBIDDEN",
      message: "只能使用自己管理的队伍",
    });
  if (team.category !== category)
    throw new BadRequestException({
      code: "CATEGORY_MISMATCH",
      message: "队伍级别与活动不一致",
    });
}
@Controller("community")
export class CommunityController {
  constructor(
    @Inject("DB") private readonly db: Pool,
    private readonly auth: Auth,
  ) {}
  @Get("posts") async list(
    @Query("kind") kind = "",
    @Query("q") q = "",
    @Query("city") city = "",
  ) {
    return (
      await this.db.query(
        `${selection} WHERE ($1='' OR p.kind=$1) AND ($2='' OR p.title ILIKE $2 OR p.body ILIKE $2) AND ($3='' OR p.city=$3) ORDER BY p.created_at DESC LIMIT 100`,
        [kind, q ? `%${q.slice(0, 80)}%` : "", city],
      )
    ).rows;
  }
  @Get("posts/:id") async detail(@Param("id") id: string) {
    const row = (await this.db.query(`${selection} WHERE p.id=$1`, [id]))
      .rows[0];
    if (!row) throw missing();
    return row;
  }
  @Post("posts") async publish(
    @Headers("authorization") header: string | undefined,
    @Body() body: unknown,
  ) {
    const actor = await this.auth.actor(header),
      v = parse(postInput, body);
    if (v.teamId) await ownedTeam(this.db, v.teamId, actor.id, v.category);
    const id = randomUUID();
    await this.db.query(
      `INSERT INTO community_posts(id,author_id,kind,title,city,category,level,availability,venue,body,team_id,starts_at) VALUES($1,$2,$3,$4,$5,$6,$7,$8,$9,$10,$11,$12)`,
      [
        id,
        actor.id,
        v.kind,
        v.title,
        v.city,
        v.category,
        v.level,
        v.availability,
        v.venue,
        v.body,
        v.teamId ?? null,
        v.startsAt ?? null,
      ],
    );
    return this.detail(id);
  }
  @Patch("posts/:id") async close(
    @Param("id") id: string,
    @Headers("authorization") header: string | undefined,
    @Body() body: unknown,
  ) {
    const actor = await this.auth.actor(header),
      v = parse(
        z.object({ status: z.enum(["closed", "cancelled"]) }).strict(),
        body,
      );
    const result = await this.db.query(
      "UPDATE community_posts SET status=$3 WHERE id=$1 AND author_id=$2 RETURNING id",
      [id, actor.id, v.status],
    );
    if (!result.rowCount) throw missing();
    return this.detail(id);
  }
  @Post("posts/:id/applications") async apply(
    @Param("id") id: string,
    @Headers("authorization") header: string | undefined,
    @Body() body: unknown,
  ) {
    const actor = await this.auth.actor(header),
      v = parse(
        z
          .object({
            message: z.string().trim().min(2).max(500),
            teamId: z.string().min(1).max(100).optional(),
          })
          .strict(),
        body,
      );
    const client = await this.db.connect();
    try {
      await client.query("BEGIN");
      const p = (
        await client.query(
          "SELECT * FROM community_posts WHERE id=$1 FOR UPDATE",
          [id],
        )
      ).rows[0];
      if (!p) throw missing();
      if (p.author_id === actor.id)
        throw new BadRequestException({
          code: "SELF_APPLICATION",
          message: "不能申请自己发布的信息",
        });
      if (
        p.status !== "open" ||
        (p.starts_at && new Date(p.starts_at).getTime() <= Date.now())
      )
        throw conflict("活动已结束或不再接受申请");
      if (p.kind === "friendly" && !v.teamId)
        throw new BadRequestException({
          code: "TEAM_REQUIRED",
          message: "请选择应约队伍",
        });
      if (v.teamId) await ownedTeam(client, v.teamId, actor.id, p.category);
      const inserted = await client.query(
        `INSERT INTO community_applications(id,post_id,applicant_id,team_id,message) VALUES($1,$2,$3,$4,$5) ON CONFLICT(post_id,applicant_id) DO UPDATE SET message=community_applications.message RETURNING id`,
        [randomUUID(), id, actor.id, v.teamId ?? null, v.message],
      );
      const result = (
        await client.query(`${applicationSelection} WHERE ca.id=$1`, [
          inserted.rows[0].id,
        ])
      ).rows[0];
      await client.query("COMMIT");
      return result;
    } catch (e) {
      await client.query("ROLLBACK");
      throw e;
    } finally {
      client.release();
    }
  }
  @Get("applications") async applications(
    @Headers("authorization") header: string | undefined,
  ) {
    const actor = await this.auth.actor(header);
    return (
      await this.db.query(
        `${applicationSelection} WHERE ca.applicant_id=$1 OR p.author_id=$1 ORDER BY ca.created_at DESC`,
        [actor.id],
      )
    ).rows;
  }
  @Patch("applications/:id") async review(
    @Param("id") id: string,
    @Headers("authorization") header: string | undefined,
    @Body() body: unknown,
  ) {
    const actor = await this.auth.actor(header),
      v = parse(
        z
          .object({ status: z.enum(["accepted", "rejected", "withdrawn"]) })
          .strict(),
        body,
      );
    const client = await this.db.connect();
    try {
      await client.query("BEGIN");
      const ref = (
        await client.query(
          "SELECT post_id FROM community_applications WHERE id=$1",
          [id],
        )
      ).rows[0];
      if (!ref) throw missing();
      const p = (
        await client.query(
          "SELECT * FROM community_posts WHERE id=$1 FOR UPDATE",
          [ref.post_id],
        )
      ).rows[0];
      const a = (
        await client.query(
          "SELECT * FROM community_applications WHERE id=$1 FOR UPDATE",
          [id],
        )
      ).rows[0];
      if (
        (v.status === "withdrawn" ? a.applicant_id : p.author_id) !== actor.id
      )
        throw new ForbiddenException({
          code: "FORBIDDEN",
          message: "无权处理该申请",
        });
      if (a.status !== "pending") throw conflict("申请已处理，请刷新查看");
      if (
        v.status !== "withdrawn" &&
        (p.status !== "open" ||
          (p.starts_at && new Date(p.starts_at).getTime() <= Date.now()))
      )
        throw conflict("活动已结束或已关闭");
      await client.query(
        "UPDATE community_applications SET status=$2,reviewed_at=now() WHERE id=$1",
        [id, v.status],
      );
      if (v.status === "accepted" && p.kind === "recruit")
        await client.query(
          "INSERT INTO team_members(team_id,account_id) VALUES($1,$2) ON CONFLICT DO NOTHING",
          [p.team_id, a.applicant_id],
        );
      if (v.status === "accepted" && p.kind === "friendly") {
        await client.query(
          "UPDATE community_posts SET status='matched' WHERE id=$1",
          [p.id],
        );
        await client.query(
          "UPDATE community_applications SET status='rejected',reviewed_at=now() WHERE post_id=$1 AND status='pending'",
          [p.id],
        );
      }
      await client.query(
        "INSERT INTO audit_log(id,actor_id,action,resource_id,detail) VALUES($1,$2,'community.review',$3,$4)",
        [randomUUID(), actor.id, id, JSON.stringify(v)],
      );
      const result = (
        await client.query(`${applicationSelection} WHERE ca.id=$1`, [id])
      ).rows[0];
      await client.query("COMMIT");
      return result;
    } catch (e) {
      await client.query("ROLLBACK");
      throw e;
    } finally {
      client.release();
    }
  }
  private async participant(id: string, actorId: string) {
    const row = (
      await this.db.query(
        `SELECT ca.id FROM community_applications ca JOIN community_posts p ON p.id=ca.post_id WHERE ca.id=$1 AND (ca.applicant_id=$2 OR p.author_id=$2)`,
        [id, actorId],
      )
    ).rows[0];
    if (!row) throw missing();
  }
  @Get("applications/:id/messages") async messages(
    @Param("id") id: string,
    @Headers("authorization") header: string | undefined,
  ) {
    const actor = await this.auth.actor(header);
    await this.participant(id, actor.id);
    return (
      await this.db.query(
        `SELECT m.id,m.sender_id AS "senderId",a.name AS "senderName",m.body,m.created_at AS "createdAt" FROM community_messages m JOIN accounts a ON a.id=m.sender_id WHERE m.application_id=$1 ORDER BY m.created_at,m.id`,
        [id],
      )
    ).rows;
  }
  @Post("applications/:id/messages") async sendMessage(
    @Param("id") id: string,
    @Headers("authorization") header: string | undefined,
    @Body() body: unknown,
  ) {
    const actor = await this.auth.actor(header);
    await this.participant(id, actor.id);
    const value = parse(
      z.object({ body: z.string().trim().min(1).max(1000) }).strict(),
      body,
    );
    await this.db.query(
      "INSERT INTO community_messages(id,application_id,sender_id,body) VALUES($1,$2,$3,$4)",
      [randomUUID(), id, actor.id, value.body],
    );
    return { ok: true };
  }
  @Get("teams") async publicTeams(@Query("q") q = "") {
    return (
      await this.db.query(
        `SELECT t.id,t.name,t.city,t.category,t.organization_id AS "organizationId",o.name AS "organizationName",jsonb_array_length(t.roster) AS "rosterCount",(SELECT count(*)::int FROM team_members m WHERE m.team_id=t.id) AS "memberCount" FROM teams t JOIN organizations o ON o.id=t.organization_id WHERE t.name ILIKE $1 OR t.city ILIKE $1 ORDER BY t.created_at DESC LIMIT 100`,
        [`%${q.slice(0, 80)}%`],
      )
    ).rows;
  }
  @Get("organizations") async organizations(@Query("q") q = "") {
    return (
      await this.db.query(
        `SELECT o.id,o.name,o.city,(SELECT count(*)::int FROM teams t WHERE t.organization_id=o.id) AS "teamCount" FROM organizations o WHERE o.name ILIKE $1 OR o.city ILIKE $1 ORDER BY o.name LIMIT 100`,
        [`%${q.slice(0, 80)}%`],
      )
    ).rows;
  }
  @Get("memberships") async memberships(
    @Headers("authorization") header: string | undefined,
  ) {
    const actor = await this.auth.actor(header);
    return (
      await this.db.query(
        `SELECT m.team_id AS "teamId",t.name AS "teamName",t.city,t.category,m.joined_at AS "joinedAt" FROM team_members m JOIN teams t ON t.id=m.team_id WHERE m.account_id=$1 ORDER BY m.joined_at DESC`,
        [actor.id],
      )
    ).rows;
  }
}
