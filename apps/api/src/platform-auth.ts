import {
  Injectable,
  Inject,
  UnauthorizedException,
  Body,
  Controller,
  Post,
  Delete,
  Get,
  Headers,
} from "@nestjs/common";
import { Pool } from "pg";
import {
  randomBytes,
  randomUUID,
  scryptSync,
  timingSafeEqual,
} from "node:crypto";
import { z } from "zod";
import { parse, tokenHash } from "./auth";
export function passwordHash(
  password: string,
  salt = randomBytes(16).toString("hex"),
) {
  return salt + ":" + scryptSync(password, salt, 64).toString("hex");
}
export async function createPlatformAdmin(
  db: Pool,
  username: string,
  password: string,
) {
  if (!/^[a-zA-Z0-9_-]{3,40}$/.test(username) || password.length < 12)
    throw new Error("用户名3–40位，密码至少12位");
  await db.query(
    "INSERT INTO platform_admins(id,username,password_hash) VALUES($1,$2,$3)",
    [randomUUID(), username, passwordHash(password)],
  );
}
@Injectable()
export class PlatformAuth {
  constructor(@Inject("DB") private db: Pool) {}
  async actor(header?: string) {
    const token = header?.startsWith("Bearer ") ? header.slice(7) : "";
    const row = (
      await this.db.query(
        `SELECT a.id,a.username FROM platform_admins a JOIN platform_sessions s ON s.admin_id=a.id WHERE s.token_hash=$1 AND s.expires_at>now()`,
        [tokenHash(token)],
      )
    ).rows[0];
    if (!token || !row)
      throw new UnauthorizedException("请使用平台管理员账号登录");
    return row as { id: string; username: string };
  }
}
@Controller("platform")
export class PlatformSessionController {
  constructor(
    @Inject("DB") private db: Pool,
    private auth: PlatformAuth,
  ) {}
  @Get("me") me(@Headers("authorization") h?: string) {
    return this.auth.actor(h);
  }
  @Post("sessions") async login(@Body() body: unknown) {
    const v = parse(
      z
        .object({
          username: z.string().trim().min(3).max(40),
          password: z.string().min(1).max(200),
        })
        .strict(),
      body,
    );
    const client = await this.db.connect();
    try {
      await client.query("BEGIN");
      const row = (
        await client.query(
          "SELECT * FROM platform_admins WHERE username=$1 FOR UPDATE",
          [v.username],
        )
      ).rows[0];
      const [salt, hash] = (
        row?.password_hash ?? passwordHash("invalid")
      ).split(":");
      const valid = timingSafeEqual(
        Buffer.from(hash, "hex"),
        scryptSync(v.password, salt, 64),
      );
      if (
        !row ||
        (row.locked_until && new Date(row.locked_until) > new Date()) ||
        !valid
      ) {
        if (row)
          await client.query(
            "UPDATE platform_admins SET failed_attempts=failed_attempts+1,locked_until=CASE WHEN failed_attempts>=4 THEN now()+interval '15 minutes' ELSE locked_until END WHERE id=$1",
            [row.id],
          );
        await client.query("COMMIT");
        throw new UnauthorizedException("账号或密码错误，连续失败请稍后重试");
      }
      await client.query(
        "UPDATE platform_admins SET failed_attempts=0,locked_until=NULL WHERE id=$1",
        [row.id],
      );
      const token = randomBytes(32).toString("hex");
      await client.query(
        "INSERT INTO platform_sessions VALUES($1,$2,now()+interval '8 hours')",
        [tokenHash(token), row.id],
      );
      await client.query("COMMIT");
      return { token, account: { id: row.id, username: row.username } };
    } catch (e) {
      await client.query("ROLLBACK");
      throw e;
    } finally {
      client.release();
    }
  }
  @Delete("session") async logout(@Headers("authorization") h?: string) {
    await this.auth.actor(h);
    await this.db.query("DELETE FROM platform_sessions WHERE token_hash=$1", [
      tokenHash(h!.slice(7)),
    ]);
    return { ok: true };
  }
}
