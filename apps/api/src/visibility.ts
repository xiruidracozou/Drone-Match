import { NotFoundException } from "@nestjs/common";
import { Pool } from "pg";
import { Auth } from "./auth";
export async function tournamentReadable(
  db: Pool,
  auth: Auth,
  id: string,
  header?: string,
) {
  const t = (
    await db.query(
      "SELECT hidden,organization_id FROM tournaments WHERE id=$1",
      [id],
    )
  ).rows[0];
  if (!t) throw new NotFoundException("赛事不存在");
  if (!t.hidden) return;
  let actor;
  try {
    actor = await auth.actor(header);
  } catch {
    throw new NotFoundException("赛事已下架");
  }
  if (actor.role === "organizer" && actor.organizationId === t.organization_id)
    return;
  const allowed = (
    await db.query(
      `SELECT r.id FROM registrations r JOIN teams t ON t.id=r.team_id WHERE r.tournament_id=$1 AND (r.applicant_id=$2 OR t.owner_id=$2 OR EXISTS(SELECT 1 FROM team_members m WHERE m.team_id=t.id AND m.account_id=$2)) LIMIT 1`,
      [id, actor.id],
    )
  ).rowCount;
  if (!allowed) throw new NotFoundException("赛事已下架");
}
