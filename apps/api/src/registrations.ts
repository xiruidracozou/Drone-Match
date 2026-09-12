import {
  ConflictException,
  ForbiddenException,
  Inject,
  Injectable,
  NotFoundException,
} from "@nestjs/common";
import { capacityAvailable } from "./business-rules";
import { Pool } from "pg";
import { randomUUID } from "node:crypto";
import { Actor, requireRole } from "./auth";

const select = `SELECT r.id,r.tournament_id AS "tournamentId",r.team_id AS "teamId",r.team_name AS "teamName",
  r.roster,r.status,r.review_note AS "reviewNote",r.version,r.created_at AS "createdAt",
  t.title AS "tournamentTitle",t.city,t.category FROM registrations r JOIN tournaments t ON t.id=r.tournament_id`;

@Injectable()
export class Registrations {
  constructor(@Inject("DB") private readonly db: Pool) {}
  async list(actor: Actor) {
    const clause =
      actor.role === "organizer" ? "t.organization_id" : "r.applicant_id";
    return (
      await this.db.query(
        `${select} WHERE ${clause}=$1 ORDER BY r.created_at DESC`,
        [actor.role === "organizer" ? actor.organizationId : actor.id],
      )
    ).rows;
  }
  async review(
    actor: Actor,
    id: string,
    input: { status: "approved" | "rejected"; version: number; note: string },
  ) {
    requireRole(actor, "organizer");
    const client = await this.db.connect();
    try {
      await client.query("BEGIN");
      const registration = (
        await client.query(
          `SELECT r.tournament_id,t.organization_id FROM registrations r
        JOIN tournaments t ON t.id=r.tournament_id WHERE r.id=$1`,
          [id],
        )
      ).rows[0];
      if (!registration)
        throw new NotFoundException({
          code: "NOT_FOUND",
          message: "报名不存在",
        });
      if (registration.organization_id !== actor.organizationId)
        throw new ForbiddenException({
          code: "FORBIDDEN",
          message: "只能审核本机构举办的赛事",
        });
      const tournament = (
        await client.query("SELECT * FROM tournaments WHERE id=$1 FOR UPDATE", [
          registration.tournament_id,
        ])
      ).rows[0];
      const current = (
        await client.query(
          "SELECT * FROM registrations WHERE id=$1 FOR UPDATE",
          [id],
        )
      ).rows[0];
      if (current.version !== input.version || current.status !== "pending")
        throw new ConflictException({
          code: "VERSION_CONFLICT",
          message: "报名已被处理，请刷新后查看",
        });
      if (input.status === "approved") {
        await capacityAvailable(client, tournament.id, tournament.capacity);
      }
      await client.query(
        `UPDATE registrations SET status=$2,version=version+1,review_note=$3,reviewer_id=$4,reviewed_at=now() WHERE id=$1`,
        [id, input.status, input.note, actor.id],
      );
      await client.query(
        "INSERT INTO audit_log(id,actor_id,action,resource_id,detail) VALUES($1,$2,$3,$4,$5)",
        [
          randomUUID(),
          actor.id,
          "registration.review",
          id,
          JSON.stringify(input),
        ],
      );
      const result = (await client.query(`${select} WHERE r.id=$1`, [id]))
        .rows[0];
      await client.query("COMMIT");
      return result;
    } catch (error) {
      await client.query("ROLLBACK");
      throw error;
    } finally {
      client.release();
    }
  }
  async submit(actor: Actor, tournamentId: string, teamId: string) {
    requireRole(actor, "captain");
    const client = await this.db.connect();
    try {
      await client.query("BEGIN");
      const team = (
        await client.query("SELECT * FROM teams WHERE id=$1", [teamId])
      ).rows[0];
      if (!team || team.owner_id !== actor.id)
        throw new ForbiddenException({
          code: "FORBIDDEN",
          message: "只能为自己管理的队伍报名",
        });
      const tournament = (
        await client.query(
          "SELECT *,deadline>now() AS open FROM tournaments WHERE id=$1 FOR UPDATE",
          [tournamentId],
        )
      ).rows[0];
      if (!tournament)
        throw new NotFoundException({
          code: "NOT_FOUND",
          message: "赛事不存在",
        });
      const existing = (
        await client.query(
          `${select} WHERE r.tournament_id=$1 AND r.team_id=$2`,
          [tournamentId, teamId],
        )
      ).rows[0];
      if (existing) {
        await client.query("COMMIT");
        return existing;
      }
      if (tournament.hidden)
        throw new ConflictException("赛事已下架，不接受新增报名");
      if (!tournament.open)
        throw new ConflictException({
          code: "REGISTRATION_CLOSED",
          message: "报名已截止",
        });
      if (tournament.category !== team.category)
        throw new ConflictException({
          code: "CATEGORY_MISMATCH",
          message: "队伍设备级别与赛事不一致",
        });
      if (team.roster.length < 1 || team.roster.length > 10)
        throw new ConflictException({
          code: "INVALID_ROSTER",
          message: "演示报名名单须为 1–10 人",
        });
      await capacityAvailable(client, tournamentId, tournament.capacity);
      const id = randomUUID();
      await client.query(
        `INSERT INTO registrations(id,tournament_id,team_id,applicant_id,team_name,roster) VALUES($1,$2,$3,$4,$5,$6)`,
        [
          id,
          tournamentId,
          teamId,
          actor.id,
          team.name,
          JSON.stringify(team.roster),
        ],
      );
      const result = (await client.query(`${select} WHERE r.id=$1`, [id]))
        .rows[0];
      await client.query("COMMIT");
      return result;
    } catch (error) {
      await client.query("ROLLBACK");
      throw error;
    } finally {
      client.release();
    }
  }
}
