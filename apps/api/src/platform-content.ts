import {
  Body,
  Controller,
  Get,
  Post,
  Put,
  Headers,
  Inject,
  Param,
  Query,
  Res,
  BadRequestException,
  NotFoundException,
  ConflictException,
} from "@nestjs/common";
import { Pool } from "pg";
import { randomUUID } from "node:crypto";
import { mkdir, writeFile, readFile, unlink } from "node:fs/promises";
import { resolve } from "node:path";
import { z } from "zod";
import { PlatformAuth } from "./platform-auth";
import { parse } from "./auth";
import { platformAudit, reasonInput } from "./platform";
const root = resolve(__dirname, "../../..");
export const uploadDirectory = () =>
  process.env.UPLOAD_DIR || resolve(root, ".local/platform-uploads");
const https = z.url().refine(
  (v) => {
    try {
      return new URL(v).protocol === "https:";
    } catch {
      return false;
    }
  },
  { message: "外部地址必须使用 HTTPS" },
);
const contentInput = z
  .object({
    title: z.string().trim().min(2).max(100),
    subtitle: z.string().trim().max(250).default(""),
    body: z.string().trim().max(10000).default(""),
    city: z.string().trim().min(1).max(80).default("全国"),
    startsAt: z.iso.datetime().nullable().default(null),
    endsAt: z.iso.datetime().nullable().default(null),
    assetId: z.string().max(100).default(""),
    attribution: z.string().max(500).default(""),
    sort: z.number().int().min(0).max(999).default(0),
    action: z
      .object({
        type: z.enum([
          "none",
          "video",
          "guide",
          "tournament",
          "community",
          "external",
        ]),
        id: z.string().max(100).default(""),
        url: z.union([https, z.literal("")]).default(""),
      })
      .strict(),
    sourceURL: z.union([https, z.literal("")]).default(""),
  })
  .strict()
  .refine(
    (v) =>
      !v.startsAt || !v.endsAt || Date.parse(v.startsAt) < Date.parse(v.endsAt),
    { message: "结束时间须晚于开始时间" },
  )
  .refine((v) => v.action.type !== "external" || !!v.action.url, {
    message: "请填写落地页地址",
  })
  .refine(
    (v) => !["guide", "tournament"].includes(v.action.type) || !!v.action.id,
    { message: "请选择跳转目标" },
  );
@Controller()
export class ContentController {
  constructor(
    @Inject("DB") private db: Pool,
    private auth: PlatformAuth,
  ) {}
  @Get("content") async published(@Query("city") city = "全国") {
    const rows = (
      await this.db.query(
        "SELECT id,kind,published FROM platform_content WHERE published IS NOT NULL",
      )
    ).rows;
    return rows
      .filter((r) => {
        const p = r.published;
        return (
          (p.city === "全国" || p.city === city) &&
          (!p.startsAt || Date.parse(p.startsAt) <= Date.now()) &&
          (!p.endsAt || Date.parse(p.endsAt) > Date.now())
        );
      })
      .map((r) => ({ id: r.id, kind: r.kind, ...r.published }))
      .sort((a, b) => a.sort - b.sort || a.id.localeCompare(b.id));
  }
  @Get("content/assets/:id") async asset(
    @Param("id") id: string,
    @Res() response: any,
  ) {
    const row = (
      await this.db.query("SELECT * FROM platform_assets WHERE id=$1", [id])
    ).rows[0];
    if (!row) throw new NotFoundException();
    const file =
      row.filename === "DroneSoccer.jpg" ||
      row.filename === "DroneSoccerField.jpg"
        ? resolve(root, "apps/ios/DroneMatch/Media", row.filename)
        : resolve(uploadDirectory(), row.filename);
    let bytes: Buffer;
    try {
      bytes = await readFile(file);
    } catch {
      throw new NotFoundException("素材不存在");
    }
    response.setHeader("Content-Type", row.mime);
    response.setHeader("X-Content-Type-Options", "nosniff");
    response.setHeader("Cache-Control", "public,max-age=86400");
    response.send(bytes);
  }
  @Post("platform/assets") async upload(
    @Headers("authorization") h: string | undefined,
    @Body() body: unknown,
  ) {
    const actor = await this.auth.actor(h),
      v = parse(
        z
          .object({
            data: z.string().max(14_000_000),
            attribution: z.string().trim().min(2).max(500),
            reason: reasonInput,
          })
          .strict(),
        body,
      );
    if (!/^[A-Za-z0-9+/]*={0,2}$/.test(v.data))
      throw new BadRequestException("图片编码无效");
    const bytes = Buffer.from(v.data, "base64");
    const png =
      bytes.length >= 24 &&
      bytes
        .subarray(0, 8)
        .equals(Buffer.from([137, 80, 78, 71, 13, 10, 26, 10])) &&
      bytes.toString("ascii", 12, 16) === "IHDR";
    const jpg =
      bytes.length >= 4 &&
      bytes[0] === 255 &&
      bytes[1] === 216 &&
      bytes[2] === 255 &&
      bytes[bytes.length - 2] === 255 &&
      bytes[bytes.length - 1] === 217;
    if (bytes.length > 10 * 1024 * 1024 || (!png && !jpg))
      throw new BadRequestException("请上传10MB以内的 JPEG 或 PNG 图片");
    const id = randomUUID(),
      filename = id + (png ? ".png" : ".jpg"),
      c = await this.db.connect();
    await mkdir(uploadDirectory(), { recursive: true });
    try {
      await c.query("BEGIN");
      await writeFile(resolve(uploadDirectory(), filename), bytes, {
        flag: "wx",
      });
      const row = (
        await c.query(
          "INSERT INTO platform_assets(id,filename,mime,attribution) VALUES($1,$2,$3,$4) RETURNING *",
          [id, filename, png ? "image/png" : "image/jpeg", v.attribution],
        )
      ).rows[0];
      await platformAudit(c, actor.id, "assets", id, "upload", v.reason, null, {
        id,
        attribution: v.attribution,
      });
      await c.query("COMMIT");
      return row;
    } catch (e) {
      await c.query("ROLLBACK");
      await unlink(resolve(uploadDirectory(), filename)).catch(() => {});
      throw e;
    } finally {
      c.release();
    }
  }
  @Get("platform/assets") async assets(@Headers("authorization") h?: string) {
    await this.auth.actor(h);
    return (
      await this.db.query(
        "SELECT * FROM platform_assets ORDER BY created_at DESC",
      )
    ).rows;
  }
  @Post("platform/content") async create(
    @Headers("authorization") h: string | undefined,
    @Body() body: unknown,
  ) {
    const actor = await this.auth.actor(h),
      v = parse(
        z
          .object({
            kind: z.enum(["hero", "advert", "guide", "video"]),
            reason: reasonInput,
            data: contentInput,
          })
          .strict(),
        body,
      ),
      id = randomUUID(),
      c = await this.db.connect();
    try {
      await c.query("BEGIN");
      const row = (
        await c.query(
          "INSERT INTO platform_content(id,kind,draft) VALUES($1,$2,$3) RETURNING *",
          [id, v.kind, JSON.stringify(v.data)],
        )
      ).rows[0];
      await platformAudit(
        c,
        actor.id,
        "content",
        id,
        "draft.create",
        v.reason,
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
  @Put("platform/content/:id") async save(
    @Param("id") id: string,
    @Headers("authorization") h: string | undefined,
    @Body() body: unknown,
  ) {
    const actor = await this.auth.actor(h),
      v = parse(
        z
          .object({
            version: z.number().int().positive(),
            reason: reasonInput,
            operation: z.enum(["save", "publish", "unpublish"]),
            data: contentInput.optional(),
          })
          .strict(),
        body,
      ),
      c = await this.db.connect();
    try {
      await c.query("BEGIN");
      const old = (
        await c.query("SELECT * FROM platform_content WHERE id=$1 FOR UPDATE", [
          id,
        ])
      ).rows[0];
      if (!old) throw new NotFoundException();
      if (old.version !== v.version)
        throw new ConflictException("内容已更新，请刷新");
      if (v.operation === "save" && !v.data)
        throw new BadRequestException("缺少草稿内容");
      if (v.operation === "publish") {
        const p = parse(contentInput, old.draft);
        if (["hero", "advert"].includes(old.kind) && !p.assetId)
          throw new BadRequestException("发布前请选择图片");
        if (
          p.assetId &&
          !(
            await c.query("SELECT id FROM platform_assets WHERE id=$1", [
              p.assetId,
            ])
          ).rowCount
        )
          throw new BadRequestException("素材不存在");
        if (
          ["advert", "video"].includes(old.kind) &&
          (p.action.type !== "external" || !p.action.url)
        )
          throw new BadRequestException("请填写实际外部链接");
        if (old.kind === "guide" && !p.body)
          throw new BadRequestException("指南正文不能为空");
        if (
          p.action.type === "guide" &&
          !(
            await c.query(
              "SELECT id FROM platform_content WHERE id=$1 AND kind='guide' AND published IS NOT NULL",
              [p.action.id],
            )
          ).rowCount
        )
          throw new BadRequestException("目标指南尚未发布");
        if (
          p.action.type === "tournament" &&
          !(
            await c.query(
              "SELECT id FROM tournaments WHERE id=$1 AND NOT hidden",
              [p.action.id],
            )
          ).rowCount
        )
          throw new BadRequestException("目标赛事不可公开访问");
      }
      const row = (
        await c.query(
          `UPDATE platform_content SET draft=$2,published=$3,version=version+1,updated_at=now() WHERE id=$1 RETURNING *`,
          [
            id,
            JSON.stringify(v.operation === "save" ? v.data : old.draft),
            v.operation === "publish"
              ? JSON.stringify(old.draft)
              : v.operation === "unpublish"
                ? null
                : old.published
                  ? JSON.stringify(old.published)
                  : null,
          ],
        )
      ).rows[0];
      await platformAudit(
        c,
        actor.id,
        "content",
        id,
        v.operation,
        v.reason,
        old,
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
}
export async function seedContent(db: Pool) {
  await db.query(
    `INSERT INTO platform_assets(id,filename,mime,attribution) VALUES('equipment-photo','DroneSoccer.jpg','image/jpeg','A7N8X / Wikimedia Commons / CC0'),('field-photo','DroneSoccerField.jpg','image/jpeg','A7N8X / Wikimedia Commons / CC0') ON CONFLICT DO NOTHING`,
  );
  const base = {
    subtitle: "",
    body: "",
    city: "全国",
    startsAt: null,
    endsAt: null,
    assetId: "",
    attribution: "",
    sort: 0,
    action: { type: "none", id: "", url: "" },
    sourceURL: "",
  };
  const rows = [
    {
      id: "home-replay",
      kind: "hero",
      title: "感受空中对抗的魅力",
      subtitle: "观看官方回放",
      assetId: "field-photo",
      attribution: "项目实拍资料图 · A7N8X / CC0",
      action: { type: "video", id: "", url: "" },
    },
    {
      id: "home-equipment",
      kind: "hero",
      title: "认识你的第一颗飞行球",
      subtitle: "器材与参赛准备",
      assetId: "equipment-photo",
      sort: 1,
      attribution: "项目实拍资料图 · A7N8X / CC0",
      action: { type: "guide", id: "equipment", url: "" },
    },
    {
      id: "equipment",
      kind: "guide",
      title: "无人机足球入门",
      subtitle: "器材、场地与参赛准备",
      assetId: "equipment-photo",
      attribution: "A7N8X / Wikimedia Commons / CC0",
      body: "无人机足球让两支队伍在网笼内协作对抗。球形保护罩包裹无人机，飞手在场外操纵，指定进攻球穿过对方球门得分。具体人数、器材和计分方式以所参加赛事的规程为准。\n\n先确认赛事要求的设备级别、适合训练的封闭场地、队伍名单与现场组织方式。",
      sourceURL:
        "https://www.fai.org/event/2026-fai-drone-soccer-international-series",
    },
    {
      id: "participation",
      kind: "guide",
      title: "参赛指南",
      body: "1. 创建或选择自己管理的队伍。\n2. 阅读赛事规程，确认设备级别、时间与报名名单。\n3. 提交报名，等待主办方审核。\n4. 在我的报名中查看进度，赛程公布后查看队伍安排。\n\n当前演示规则仅用于本地成年测试资料，不替代真实赛事规程。",
    },
    {
      id: "world-championship-2025",
      kind: "video",
      title: "2025 无人机足球世界锦标赛",
      subtitle: "上海 · 2025.11.15 – 11.18",
      body: "在官方 YouTube 页面观看，播放与网络可用性由来源平台提供。",
      attribution: "FAI 世界航空运动联合会",
      action: {
        type: "external",
        id: "",
        url: "https://youtube.com/playlist?list=PLyXQtZ_gjrxDK_6U2JK1KTlFKIckwwJ7i",
      },
      sourceURL: "https://www-2025.fai.org/wdsc2025-livestream",
    },
  ];
  for (const { id, kind, ...data } of rows) {
    const p = JSON.stringify({ ...base, ...data });
    await db.query(
      "INSERT INTO platform_content(id,kind,draft,published) VALUES($1,$2,$3,$3) ON CONFLICT DO NOTHING",
      [id, kind, p],
    );
  }
}
