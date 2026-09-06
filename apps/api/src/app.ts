import "reflect-metadata";
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
    controllers: [ApiController, CommunityController],
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
