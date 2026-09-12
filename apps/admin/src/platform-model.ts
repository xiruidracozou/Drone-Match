export type Row = Record<string, any>;
export type Field = {
  key: string;
  label: string;
  type?: "text" | "area" | "number" | "date" | "select" | "check" | "roster";
  options?: { label: string; value: string }[];
  required?: boolean;
};
export const titles: Record<string, string> = {
  overview: "工作台",
  content: "内容运营",
  tournaments: "赛事管理",
  registrations: "报名与纠错",
  matches: "赛程与比分",
  organizations: "机构管理",
  teams: "队伍管理",
  posts: "社区巡查",
  users: "用户管理",
  feedback: "反馈处理",
  audit: "操作日志",
};
export const kinds: Record<string, string> = {
  hero: "首页轮播",
  advert: "商业推广",
  guide: "指南内容",
  video: "视频来源",
};
export const statuses: Record<string, string> = {
  pending: "待审核",
  approved: "已通过",
  rejected: "未通过",
  scheduled: "待比赛",
  final: "已公布结果",
  cancelled: "已取消",
  open: "进行中",
  closed: "已关闭",
  matched: "已约定",
  accepted: "已接受",
  withdrawn: "已撤回",
  received: "待处理",
  processing: "处理中",
  resolved: "已解决",
  captain: "队长",
  organizer: "主办方",
  recruit: "战队招募",
  seeking: "飞手找队",
  friendly: "训练约赛",
  volunteer: "志愿者",
};
export const options = (values: string[]) =>
  values.map((value) => ({ value, label: statuses[value] || value }));
export const display = (v: unknown): string =>
  v == null
    ? "—"
    : typeof v === "boolean"
      ? v
        ? "是"
        : "否"
      : Array.isArray(v)
        ? v.join("、")
        : typeof v === "object"
          ? JSON.stringify(v)
          : statuses[String(v)] || String(v);
export function fieldsFor(
  resource: string,
  lookups: Row,
  registrations: Row[] = [],
): Field[] {
  const f = (
    key: string,
    label: string,
    type: Field["type"] = "text",
  ): Field => ({ key, label, type, required: true });
  const category: Field = {
    ...f("category", "设备级别", "select"),
    options: options(["20cm", "40cm"]),
  };
  const nameCity = [f("name", "名称"), f("city", "城市")];
  const eventFields = [
    f("title", "赛事名称"),
    f("city", "城市"),
    f("venue", "场地"),
    {
      ...f("organization_id", "所属机构", "select"),
      options: (lookups.organizations || []).map((r: Row) => ({
        value: r.id,
        label: r.name,
      })),
    },
    category,
    f("capacity", "参赛队伍名额", "number"),
    f("deadline", "报名截止", "date"),
    f("starts_at", "比赛开始", "date"),
    f("description", "赛事说明", "area"),
    f("rules", "赛事规程", "area"),
  ];
  const registrationOptions = registrations.map((r) => ({
    value: r.id,
    label: `${r.team_name} · ${statuses[r.status] || r.status}`,
  }));
  switch (resource) {
    case "organizations":
      return nameCity;
    case "teams":
      return [
        ...nameCity,
        category,
        f("roster", "当前名单（每行一人）", "roster"),
        f("adultOnly", "确认仅使用成年演示资料", "check"),
      ];
    case "tournaments":
      return eventFields;
    case "registrations":
      return [
        {
          ...f("status", "审核结果", "select"),
          options: options(["pending", "approved", "rejected"]),
        },
        f("review_note", "对用户展示的审核备注", "area"),
        f("roster", "本次报名名单快照（每行一人）", "roster"),
      ];
    case "matches":
      return [
        {
          ...f("tournamentId", "赛事", "select"),
          options: (lookups.tournaments || []).map((r: Row) => ({
            value: r.id,
            label: r.title,
          })),
        },
        {
          ...f("homeRegistrationId", "主队报名", "select"),
          options: registrationOptions,
        },
        {
          ...f("awayRegistrationId", "客队报名", "select"),
          options: registrationOptions,
        },
        f("startsAt", "开始时间", "date"),
        f("endsAt", "结束时间", "date"),
        f("venue", "场地"),
        f("stage", "阶段"),
        {
          ...f("status", "状态", "select"),
          options: options(["scheduled", "final", "cancelled"]),
        },
        { ...f("homeScore", "主队得分", "number"), required: false },
        { ...f("awayScore", "客队得分", "number"), required: false },
        { ...f("note", "说明", "area"), required: false },
      ];
    case "users":
      return [
        f("name", "显示名称"),
        f("disabled", "停用账号（立即失效已有登录）", "check"),
      ];
    case "feedback":
      return [
        {
          ...f("status", "处理状态", "select"),
          options: options(["received", "processing", "resolved"]),
        },
        f("reply", "回复用户", "area"),
      ];
    default:
      return [];
  }
}
export function initialValues(resource: string, row: Row): Row {
  if (resource === "matches")
    return {
      tournamentId: row.tournament_id,
      homeRegistrationId: row.home_registration_id,
      awayRegistrationId: row.away_registration_id,
      startsAt: row.starts_at,
      endsAt: row.ends_at,
      venue: row.venue,
      stage: row.stage,
      status: row.status || "scheduled",
      homeScore: row.home_score ?? null,
      awayScore: row.away_score ?? null,
      note: row.note || "",
    };
  return {
    ...row,
    adultOnly: true,
    roster: row.roster?.join("\n"),
    review_note: row.review_note || "",
  };
}
export const labels: Record<string, string> = {
  id: "记录编号",
  title: "标题",
  name: "名称",
  city: "城市",
  venue: "场地",
  category: "设备级别",
  status: "状态",
  kind: "类型",
  body: "内容",
  reply: "处理回复",
  role: "身份",
  disabled: "已停用",
  organization_id: "所属机构",
  owner_id: "负责人",
  author_id: "发布人",
  team_id: "队伍",
  team_name: "报名队伍",
  tournament_id: "赛事",
  roster: "名单",
  review_note: "审核备注",
  version: "版本",
  created_at: "创建时间",
  updated_at: "更新时间",
  starts_at: "开始时间",
  ends_at: "结束时间",
  deadline: "截止时间",
  capacity: "名额",
  rules: "规程",
  description: "说明",
  hidden: "已下架",
  moderation_reason: "平台处理说明",
  home_score: "主队得分",
  away_score: "客队得分",
  stage: "比赛阶段",
  note: "备注",
  home_registration_id: "主队报名",
  away_registration_id: "客队报名",
  reason: "操作原因",
  action: "操作",
  resource_type: "对象类型",
  resource_id: "对象编号",
  admin_id: "平台操作人",
  before_data: "修改前",
  after_data: "修改后",
  applicant_id: "申请人",
  post_id: "帖子",
  message: "申请说明",
  username: "管理员",
  attribution: "素材来源",
  sort: "排序",
  assetId: "图片",
  subtitle: "副标题",
  startsAt: "开始时间",
  endsAt: "结束时间",
  sourceURL: "来源页面",
  tournamentId: "赛事",
  homeRegistrationId: "主队报名",
  awayRegistrationId: "客队报名",
  homeScore: "主队得分",
  awayScore: "客队得分",
  adultOnly: "成年演示资料确认",
};
