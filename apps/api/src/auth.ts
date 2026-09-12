import {
  BadRequestException,
  ForbiddenException,
  Injectable,
  Inject,
  UnauthorizedException,
} from "@nestjs/common";
import { createHash, randomBytes } from "node:crypto";
import { Pool } from "pg";
import { z } from "zod";

export interface Actor {
  id: string;
  name: string;
  role: "captain" | "organizer";
  organizationId: string;
  organizationName: string;
}
export const tokenHash = (token: string) =>
  createHash("sha256").update(token).digest("hex");
export function parse<T>(schema: z.ZodType<T>, body: unknown): T {
  const result = schema.safeParse(body);
  if (!result.success)
    throw new BadRequestException({
      code: "INVALID_INPUT",
      message: "请检查填写内容",
      fieldErrors: result.error.flatten(),
    });
  return result.data;
}
export function requireRole(actor: Actor, role: Actor["role"]) {
  if (actor.role !== role)
    throw new ForbiddenException({
      code: "FORBIDDEN",
      message: "当前身份无权执行此操作",
    });
}
export const actorSelect = `SELECT a.id,a.name,a.role,a.organization_id AS "organizationId",o.name AS "organizationName"
  FROM accounts a JOIN organizations o ON o.id=a.organization_id`;

@Injectable()
export class Auth {
  constructor(@Inject("DB") private readonly db: Pool) {}
  async actor(header?: string): Promise<Actor> {
    const token = header?.startsWith("Bearer ") ? header.slice(7) : "";
    if (!token)
      throw new UnauthorizedException({
        code: "UNAUTHORIZED",
        message: "请先登录",
      });
    const row = (
      await this.db.query(
        `${actorSelect} JOIN sessions s ON s.account_id=a.id
      WHERE s.token_hash=$1 AND s.expires_at > now() AND NOT a.disabled`,
        [tokenHash(token)],
      )
    ).rows[0];
    if (!row)
      throw new UnauthorizedException({
        code: "UNAUTHORIZED",
        message: "登录已过期，请重新登录",
      });
    return row;
  }
  async session(accountId: string) {
    const account = (
      await this.db.query(`${actorSelect} WHERE a.id=$1 AND NOT a.disabled`, [
        accountId,
      ])
    ).rows[0];
    if (!account)
      throw new UnauthorizedException({
        code: "UNAUTHORIZED",
        message: "演示账号不存在",
      });
    const token = randomBytes(32).toString("hex");
    await this.db.query(
      `INSERT INTO sessions VALUES($1,$2,now()+interval '8 hours')`,
      [tokenHash(token), accountId],
    );
    return { token, account };
  }
}
