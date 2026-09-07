import {
  Body,
  ConflictException,
  ForbiddenException,
  Controller,
  Get,
  Headers,
  Inject,
  NotFoundException,
  Param,
  Post,
  Put,
} from "@nestjs/common";
import { Pool } from "pg";
import { randomUUID } from "node:crypto";
import { z } from "zod";
import { Auth, parse, requireRole } from "./auth";

const fields = {
  homeRegistrationId: z.string().min(1).max(100),
  awayRegistrationId: z.string().min(1).max(100),
  startsAt: z.iso.datetime(),
  endsAt: z.iso.datetime(),
  venue: z.string().trim().min(2).max(120),
  stage: z.string().trim().min(2).max(80),
  status: z.enum(["scheduled", "final", "cancelled"]),
  homeScore: z.number().int().min(0).max(999).nullable().default(null),
  awayScore: z.number().int().min(0).max(999).nullable().default(null),
  note: z.string().trim().max(1000),
};
const shape = z.object(fields).strict();
const valid = (v: z.infer<typeof shape>) =>
  v.homeRegistrationId !== v.awayRegistrationId &&
  Date.parse(v.endsAt) > Date.parse(v.startsAt) &&
  (v.status === "final"
    ? Date.parse(v.endsAt) <= Date.now() &&
      v.homeScore !== null &&
      v.awayScore !== null
    : v.homeScore === null && v.awayScore === null);
export const matchSelect = `SELECT t.title AS "tournamentTitle",m.id,m.tournament_id AS "tournamentId",m.home_registration_id AS "homeRegistrationId",m.away_registration_id AS "awayRegistrationId",a.team_name AS "homeName",b.team_name AS "awayName",m.starts_at AS "startsAt",m.ends_at AS "endsAt",m.venue,m.stage,m.status,m.home_score AS "homeScore",m.away_score AS "awayScore",m.note,m.version FROM matches m JOIN tournaments t ON t.id=m.tournament_id JOIN registrations a ON a.id=m.home_registration_id JOIN registrations b ON b.id=m.away_registration_id`;
@Controller("tournaments/:tournamentId/matches")
export class MatchesController {
  constructor(
    @Inject("DB") private readonly db: Pool,
    private readonly auth: Auth,
  ) {}
  @Get() async list(@Param("tournamentId") tournamentId: string) {
    if (
      !(
        await this.db.query("SELECT id FROM tournaments WHERE id=$1", [
          tournamentId,
        ])
      ).rowCount
    )
      throw new NotFoundException();
    return (
      await this.db.query(
        `${matchSelect} WHERE m.tournament_id=$1 ORDER BY m.starts_at,m.id`,
        [tournamentId],
      )
    ).rows;
  }
  @Post() async create(
    @Param("tournamentId") tournamentId: string,
    @Headers("authorization") header: string | undefined,
    @Body() body: unknown,
  ) {
    return this.save(tournamentId, null, header, body);
  }
  @Put(":id") async update(
    @Param("tournamentId") tournamentId: string,
    @Param("id") id: string,
    @Headers("authorization") header: string | undefined,
    @Body() body: unknown,
  ) {
    return this.save(tournamentId, id, header, body);
  }
  private async save(
    tournamentId: string,
    id: string | null,
    header: string | undefined,
    body: unknown,
  ) {
    const actor = await this.auth.actor(header);
    requireRole(actor, "organizer");
    const tournament = (
      await this.db.query(
        "SELECT organization_id FROM tournaments WHERE id=$1",
        [tournamentId],
      )
    ).rows[0];
    if (!tournament) throw new NotFoundException();
    if (tournament.organization_id !== actor.organizationId) {
      throw new ForbiddenException({ message: "只能管理本机构赛事的赛程" });
    }
    const v = parse(
      z
        .object({ ...fields, version: z.number().int().min(1).optional() })
        .strict()
        .refine(valid, { message: "请核对队伍、起止时间及比分" }),
      body,
    );
    const client = await this.db.connect();
    try {
      await client.query("BEGIN");
      await client.query("SELECT id FROM tournaments WHERE id=$1 FOR UPDATE", [
        tournamentId,
      ]);
      if (id) {
        const current = (
          await client.query(
            "SELECT version FROM matches WHERE id=$1 AND tournament_id=$2",
            [id, tournamentId],
          )
        ).rows[0];
        if (!current) throw new NotFoundException();
        if (current.version !== v.version)
          throw new ConflictException({
            message: "赛程已更新，请刷新后再修改",
          });
      }
      const teams = await client.query(
        "SELECT id FROM registrations WHERE tournament_id=$1 AND status='approved' AND id=ANY($2::text[])",
        [tournamentId, [v.homeRegistrationId, v.awayRegistrationId]],
      );
      if (teams.rowCount !== 2)
        throw new ConflictException({ message: "请选择两支已通过审核的队伍" });
      if (v.status !== "cancelled") {
        const collision = await client.query(
          `SELECT id FROM matches WHERE tournament_id=$1 AND id<>$2 AND status<>'cancelled' AND starts_at<$4 AND ends_at>$3 AND (venue=$5 OR home_registration_id=ANY($6::text[]) OR away_registration_id=ANY($6::text[]))`,
          [
            tournamentId,
            id ?? "",
            v.startsAt,
            v.endsAt,
            v.venue,
            [v.homeRegistrationId, v.awayRegistrationId],
          ],
        );
        if (collision.rowCount)
          throw new ConflictException({
            message: "该时段的队伍或场地已有比赛，请调整时间",
          });
      }
      const matchId = id ?? randomUUID();
      const values = [
        matchId,
        tournamentId,
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
      ];
      await client.query(
        `INSERT INTO matches(id,tournament_id,home_registration_id,away_registration_id,starts_at,ends_at,venue,stage,status,home_score,away_score,note) VALUES($1,$2,$3,$4,$5,$6,$7,$8,$9,$10,$11,$12)
        ON CONFLICT(id) DO UPDATE SET home_registration_id=$3,away_registration_id=$4,starts_at=$5,ends_at=$6,venue=$7,stage=$8,status=$9,home_score=$10,away_score=$11,note=$12,version=matches.version+1`,
        values,
      );
      await client.query(
        "INSERT INTO audit_log(id,actor_id,action,resource_id,detail) VALUES($1,$2,'match.publish',$3,$4)",
        [randomUUID(), actor.id, matchId, JSON.stringify(v)],
      );
      const result = (
        await client.query(`${matchSelect} WHERE m.id=$1`, [matchId])
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
}
