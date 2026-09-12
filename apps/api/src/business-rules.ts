import { ConflictException } from "@nestjs/common";
import { PoolClient } from "pg";
export async function capacityAvailable(
  c: PoolClient,
  tournamentId: string,
  capacity: number,
  exclude = "",
) {
  const count = (
    await c.query(
      "SELECT count(*)::int AS n FROM registrations WHERE tournament_id=$1 AND status='approved' AND id<>$2",
      [tournamentId, exclude],
    )
  ).rows[0].n;
  if (count >= capacity)
    throw new ConflictException({
      code: "DIVISION_FULL",
      message: "参赛名额已满",
    });
}
export async function matchRules(
  c: PoolClient,
  tournamentId: string,
  id: string | null,
  v: {
    homeRegistrationId: string;
    awayRegistrationId: string;
    status: string;
    startsAt: string;
    endsAt: string;
    venue: string;
  },
) {
  const teams = await c.query(
    "SELECT id FROM registrations WHERE tournament_id=$1 AND status='approved' AND id=ANY($2::text[])",
    [tournamentId, [v.homeRegistrationId, v.awayRegistrationId]],
  );
  if (teams.rowCount !== 2)
    throw new ConflictException("请选择两支已通过审核的队伍");
  if (
    v.status !== "cancelled" &&
    (
      await c.query(
        `SELECT id FROM matches WHERE tournament_id=$1 AND id<>$2 AND status<>'cancelled' AND starts_at<$4 AND ends_at>$3 AND (venue=$5 OR home_registration_id=ANY($6::text[]) OR away_registration_id=ANY($6::text[]))`,
        [
          tournamentId,
          id ?? "",
          v.startsAt,
          v.endsAt,
          v.venue,
          [v.homeRegistrationId, v.awayRegistrationId],
        ],
      )
    ).rowCount
  )
    throw new ConflictException("该时段的队伍或场地已有比赛");
}
