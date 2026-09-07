import "reflect-metadata";
import { MatchesController, matchSelect } from "./matches";
import { CommunityController } from "./community";
import {
  Body,
  Controller,
  Delete,
  Get,
  Headers,
  Inject,
  Module,
  NotFoundException,
  Param,
  Patch,
  Post,
  Put,
  Query,
} from "@nestjs/common";
import { NestFactory } from "@nestjs/core";
import { Pool } from "pg";
import { z } from "zod";
import { Auth, actorSelect, parse, requireRole, tokenHash } from "./auth";
import { Registrations } from "./registrations";
import { randomUUID } from "node:crypto";
import { demoRules, teamInput, tournamentInput } from "./validation";

const tournamentSelect = `SELECT t.id,t.title,t.city,t.venue,t.category,t.starts_at AS "startsAt",t.deadline,
  t.capacity,t.description,t.rules,o.name AS "organizerName",t.organization_id AS "organizationId",
  (SELECT count(*)::int FROM registrations r WHERE r.tournament_id=t.id AND r.status='approved') AS approved,
  CASE WHEN t.deadline <= now() THEN 'closed' ELSE 'open' END AS status
  FROM tournaments t JOIN organizations o ON o.id=t.organization_id`;

@Controller()
class ApiController {
  constructor(
    @Inject("DB") private readonly db: Pool,
    private readonly auth: Auth,
    private readonly registrations: Registrations,
    @Inject("DEMO") private readonly demo: boolean,
  ) {}
  @Get("health") async health() {
    await this.db.query("SELECT 1");
    return { status: "ok" };
  }
  @Get("dev/accounts") async accounts() {
    if (!this.demo) throw new NotFoundException();
    return (await this.db.query(`${actorSelect} ORDER BY a.role,a.id`)).rows;
  }
  @Post("dev/sessions") async session(@Body() body: unknown) {
    if (!this.demo) throw new NotFoundException();
    const { accountId } = parse(
      z.object({ accountId: z.string().min(1).max(100) }).strict(),
      body,
    );
    return this.auth.session(accountId);
  }
  @Get("me") me(@Headers("authorization") header?: string) {
    return this.auth.actor(header);
  }
  @Patch("me") async updateMe(
    @Headers("authorization") header: string | undefined,
    @Body() body: unknown,
  ) {
    const actor = await this.auth.actor(header);
    const v = parse(
      z.object({ name: z.string().trim().min(2).max(40) }).strict(),
      body,
    );
    await this.db.query("UPDATE accounts SET name=$2 WHERE id=$1", [
      actor.id,
      v.name,
    ]);
    return this.auth.actor(header);
  }
  @Get("me/matches") async myMatches(
    @Headers("authorization") header?: string,
  ) {
    const actor = await this.auth.actor(header);
    return (
      await this.db.query(
        `${matchSelect} WHERE ($2='organizer' AND t.organization_id=$3)
      OR EXISTS(SELECT 1 FROM teams team WHERE team.id IN (a.team_id,b.team_id) AND (team.owner_id=$1 OR EXISTS(SELECT 1 FROM team_members member WHERE member.team_id=team.id AND member.account_id=$1))) ORDER BY m.starts_at DESC,m.id`,
        [actor.id, actor.role, actor.organizationId],
      )
    ).rows;
  }
  @Get("feedback") async feedback(@Headers("authorization") header?: string) {
    const actor = await this.auth.actor(header);
    return (
      await this.db.query(
        'SELECT id,category,body,status,created_at AS "createdAt" FROM feedback WHERE account_id=$1 ORDER BY created_at DESC',
        [actor.id],
      )
    ).rows;
  }
  @Post("feedback") async sendFeedback(
    @Headers("authorization") header: string | undefined,
    @Body() body: unknown,
  ) {
    const actor = await this.auth.actor(header);
    const v = parse(
      z
        .object({
          category: z.enum(["功能问题", "使用建议", "内容举报"]),
          body: z.string().trim().min(8).max(2000),
        })
        .strict(),
      body,
    );
    return (
      await this.db.query(
        'INSERT INTO feedback(id,account_id,category,body) VALUES($1,$2,$3,$4) RETURNING id,category,body,status,created_at AS "createdAt"',
        [randomUUID(), actor.id, v.category, v.body],
      )
    ).rows[0];
  }
  @Get("tournaments/:id/participants") async participants(
    @Param("id") id: string,
  ) {
    await this.tournament(id);
    return (
      await this.db.query(
        `SELECT r.id,r.team_id AS "teamId",r.team_name AS name,t.city,t.category,o.name AS "organizationName" FROM registrations r JOIN teams t ON t.id=r.team_id JOIN organizations o ON o.id=t.organization_id WHERE r.tournament_id=$1 AND r.status='approved' ORDER BY r.reviewed_at,r.id`,
        [id],
      )
    ).rows;
  }
  @Delete("auth/session") async logout(
    @Headers("authorization") header?: string,
  ) {
    await this.auth.actor(header);
    await this.db.query("DELETE FROM sessions WHERE token_hash=$1", [
      tokenHash(header!.slice(7)),
    ]);
    return { ok: true };
  }
  @Get("teams") async teams(@Headers("authorization") header?: string) {
    const actor = await this.auth.actor(header);
    return (
      await this.db.query(
        `SELECT id,name,city,category,roster FROM teams WHERE owner_id=$1 ORDER BY created_at`,
        [actor.id],
      )
    ).rows;
  }
  @Post("teams") async createTeam(
    @Body() body: unknown,
    @Headers("authorization") header?: string,
  ) {
    const actor = await this.auth.actor(header);
    requireRole(actor, "captain");
    const value = parse(teamInput, body);
    return (
      await this.db.query(
        `INSERT INTO teams(id,name,city,owner_id,organization_id,category,roster)
      VALUES($1,$2,$3,$4,$5,$6,$7) RETURNING id,name,city,category,roster`,
        [
          randomUUID(),
          value.name,
          value.city,
          actor.id,
          actor.organizationId,
          value.category,
          JSON.stringify(value.roster),
        ],
      )
    ).rows[0];
  }
  @Put("teams/:id") async updateTeam(
    @Param("id") id: string,
    @Body() body: unknown,
    @Headers("authorization") header?: string,
  ) {
    const actor = await this.auth.actor(header);
    requireRole(actor, "captain");
    const value = parse(teamInput, body);
    const result = await this.db.query(
      `UPDATE teams SET name=$3,city=$4,category=$5,roster=$6
       WHERE id=$1 AND owner_id=$2 RETURNING id,name,city,category,roster`,
      [
        id,
        actor.id,
        value.name,
        value.city,
        value.category,
        JSON.stringify(value.roster),
      ],
    );
    if (!result.rows[0])
      throw new NotFoundException({
        code: "NOT_FOUND",
        message: "队伍不存在或无权修改",
      });
    return result.rows[0];
  }
  @Get("admin/tournaments") async managedTournaments(
    @Headers("authorization") header?: string,
  ) {
    const actor = await this.auth.actor(header);
    requireRole(actor, "organizer");
    return (
      await this.db.query(
        `${tournamentSelect} WHERE t.organization_id=$1 ORDER BY t.starts_at`,
        [actor.organizationId],
      )
    ).rows;
  }
  @Post("admin/tournaments") async createTournament(
    @Body() body: unknown,
    @Headers("authorization") header?: string,
  ) {
    const actor = await this.auth.actor(header);
    requireRole(actor, "organizer");
    const v = parse(tournamentInput, body);
    const id = randomUUID();
    await this.db.query(
      `INSERT INTO tournaments(id,title,city,venue,organization_id,category,starts_at,deadline,capacity,description,rules)
      VALUES($1,$2,$3,$4,$5,$6,$7,$8,$9,$10,$11)`,
      [
        id,
        v.title,
        v.city,
        v.venue,
        actor.organizationId,
        v.category,
        v.startsAt,
        v.deadline,
        v.capacity,
        v.description,
        demoRules,
      ],
    );
    return this.tournament(id);
  }
  @Get("registrations") async registrationList(
    @Headers("authorization") header?: string,
  ) {
    return this.registrations.list(await this.auth.actor(header));
  }
  @Post("admin/registrations/:id/review") async review(
    @Param("id") id: string,
    @Body() body: unknown,
    @Headers("authorization") header?: string,
  ) {
    const actor = await this.auth.actor(header);
    const input = parse(
      z
        .object({
          status: z.enum(["approved", "rejected"]),
          version: z.number().int().positive(),
          note: z.string().trim().max(500),
        })
        .strict()
        .refine((v) => v.status !== "rejected" || v.note.length > 0, {
          path: ["note"],
          message: "驳回时请填写原因",
        }),
      body,
    );
    return this.registrations.review(actor, id, input);
  }
  @Post("tournaments/:id/registrations") async submit(
    @Param("id") id: string,
    @Body() body: unknown,
    @Headers("authorization") header?: string,
  ) {
    const actor = await this.auth.actor(header);
    const { teamId } = parse(
      z
        .object({
          teamId: z.string().min(1).max(100),
          acceptRules: z.literal(true),
        })
        .strict(),
      body,
    );
    return this.registrations.submit(actor, id, teamId);
  }
  @Get("tournaments") async tournaments(@Query("q") q = "") {
    return (
      await this.db.query(
        `${tournamentSelect} WHERE t.title ILIKE $1 OR t.city ILIKE $1 ORDER BY t.starts_at`,
        [`%${q.slice(0, 100)}%`],
      )
    ).rows;
  }
  @Get("tournaments/:id") async tournament(@Param("id") id: string) {
    const row = (await this.db.query(`${tournamentSelect} WHERE t.id=$1`, [id]))
      .rows[0];
    if (!row)
      throw new NotFoundException({ code: "NOT_FOUND", message: "赛事不存在" });
    return row;
  }
}

export async function createApplication(pool: Pool, demoMode = false) {
  if (demoMode && process.env.NODE_ENV === "production")
    throw new Error("Demo authentication is forbidden in production");
  @Module({
    controllers: [ApiController, CommunityController, MatchesController],
    providers: [
      Auth,
      Registrations,
      { provide: "DB", useValue: pool },
      { provide: "DEMO", useValue: demoMode },
    ],
  })
  class AppModule {}
  const app = await NestFactory.create(AppModule, { logger: false });
  app.setGlobalPrefix("api/v1");
  app.enableCors({
    origin: ["http://127.0.0.1:5173", "http://localhost:5173"],
  });
  return app;
}
