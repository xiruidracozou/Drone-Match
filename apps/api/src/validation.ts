import { z } from "zod";
const label = z.string().trim().min(2).max(80);
export const teamInput = z
  .object({
    name: label,
    city: label,
    category: z.enum(["20cm", "40cm"]),
    roster: z
      .array(z.string().trim().min(1).max(40))
      .min(1)
      .max(10)
      .refine((items) => new Set(items).size === items.length),
    adultOnly: z.literal(true),
  })
  .strict();
export const tournamentInput = z
  .object({
    title: label,
    city: label,
    venue: label,
    category: z.enum(["20cm", "40cm"]),
    capacity: z.number().int().min(1).max(128),
    startsAt: z.iso.datetime(),
    deadline: z.iso.datetime(),
    description: z.string().trim().min(4).max(2000),
  })
  .strict()
  .refine(
    (value) =>
      Date.parse(value.deadline) > Date.now() &&
      Date.parse(value.startsAt) > Date.parse(value.deadline),
    {
      message: "报名截止须晚于现在，比赛开始须晚于报名截止",
      path: ["deadline"],
    },
  );
export const demoRules =
  "本地演示报名规则：仅供成年飞手测试，每队 1–10 人，设备级别须与赛事一致。审核通过后占用名额。本规则不适用于真实竞赛；正式规则确认后另行接入。";
