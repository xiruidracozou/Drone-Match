# 当前开发 API

版本：2026-09-06，第一阶段本地预览。本文描述实际已实现的接口，与产品文档中的目标 API 草案分开维护。

基础地址：`http://127.0.0.1:3001/api/v1`。JSON 请求与响应；日期为 ISO 8601 UTC 字符串。写入校验、身份和数据权限均在服务端执行。当前为小规模开发数据，列表没有实现服务端分页。

## 会话与账号

| 方法 | 路径 | 说明 |
| --- | --- | --- |
| GET | `/health` | 数据库连通性；成功 `{ "status": "ok" }` |
| GET | `/dev/accounts` | 返回演示账号；仅 `DEMO_MODE=true` 可用 |
| POST | `/dev/sessions` | 请求 `{ "accountId": "captain-east" }`；返回 `{ "token": "…", "account": {…} }` |
| GET | `/me` | 返回当前账号和机构，仅有有效会话可用 |
| DELETE | `/auth/session` | 撤销当前会话；返回 `{ "ok": true }` |

私有接口带 `Authorization: Bearer <token>`。令牌随机生成，数据库只保存 SHA-256 摘要，有效期 8 小时。iOS 保存在 Keychain，Web 保存在当前标签页的 sessionStorage。当前没有生产账号登录、刷新令牌或 SMS 服务。

账号字段：`id`、`name`、`role`（`captain` / `organizer`）、`organizationId`、`organizationName`。

## 队伍

`GET /teams` 返回当前账号负责的队伍，不返回整个机构或平台的人员库。

`POST /teams` 仅队长可调用：

```json
{
  "name": "测试队伍",
  "city": "上海",
  "category": "20cm",
  "roster": ["成年演示飞手甲", "成年演示飞手乙"],
  "adultOnly": true
}
```

名称、城市 2–80 字；设备级别仅 `20cm` / `40cm`；名单 1–10 个非空、非重复姓名；`adultOnly` 必须为 true。机构与负责人从会话读取，客户端不能自行指定。返回 `id,name,city,category,roster`。

成人演示声明只是开发数据范围约束，不是实际年龄核验。当前不接收真实未成年人信息，不存在监护授权或跨队唯一飞手身份模型。

## 赛事

| 方法 | 路径 | 权限 |
| --- | --- | --- |
| GET | `/tournaments?q=上海` | 游客可用，名称或城市关键词查询 |
| GET | `/tournaments/:id` | 游客可用，详情不存在时 404 |
| GET | `/admin/tournaments` | 主办方，仅返回其机构举办的赛事 |
| POST | `/admin/tournaments` | 主办方，发布本机构演示赛事 |

创建请求字段：`title,city,venue,category,startsAt,deadline,capacity,description`。名称/城市/场地 2–80 字，描述 4–2000 字，名额整数 1–128，截止时间晚于当前时间且早于比赛时间。`rules` 由服务端设置为固定演示规则；本阶段只含一个成人演示组，免费报名。

赛事响应字段：`id,title,city,venue,category,startsAt,deadline,capacity,description,rules,organizerName,organizationId,approved,status`。

`approved` 是已通过队伍数；`status` 为服务端时间计算的 `open` / `closed`，满额仍可能是 open，客户端必须同时判断 `approved < capacity`。报名最终允许与否由提交事务再次校验。

## 报名与审核

`POST /tournaments/:id/registrations`：队长提交 `{ "teamId": "team-east", "acceptRules": true }`。需要本队权限、匹配设备级别、有效名单、未截止且未满额。服务端保存队名与名单快照。同队同赛事重复提交返回已有记录（包括其当前审核状态），不会新建第二份报名；本阶段不支持撤回、重报或修改已提交名单。

`GET /registrations`：队长看到自己提交的报名；主办方看到自己举办赛事的所有报名，允许参赛队伍来自其他机构。

`POST /admin/registrations/:id/review`：

```json
{
  "status": "approved",
  "version": 1,
  "note": "名单已确认"
}
```

`status` 仅 `approved` / `rejected`；驳回时 `note` 必填，最长 500 字。只允许本赛事主办方对 pending 报名执行一次审核。带旧版本或重复审批返回 409，客户端刷新后查看已有结果。

事务按赛事行锁串行检查名额，再锁报名、检查版本，最后更新状态并记录审核日志；审核与审计同事务提交。两队争抢最后一个名额仅一队可通过。申请待审不占正式名额。

报名响应：`id,tournamentId,teamId,teamName,tournamentTitle,city,category,roster,status,reviewNote,version,createdAt`。不暴露其他机构的账号令牌或完整成员库。

## 错误

业务错误返回 `{ "code": "…", "message": "…" }`；输入错误额外包含 `fieldErrors`。当前尚未实现全局 requestId 与完整 OpenAPI schema。

| HTTP | code | 说明 |
| --- | --- | --- |
| 400 | INVALID_INPUT | 缺字段、类型/范围错误、未勾选规则、日期顺序错误 |
| 401 | UNAUTHORIZED | 缺失、过期或撤销的会话 |
| 403 | FORBIDDEN | 角色或队伍/赛事机构权限不符 |
| 404 | NOT_FOUND | 业务对象不存在；禁用的开发端点使用框架 404 |
| 409 | REGISTRATION_CLOSED | 已截止 |
| 409 | CATEGORY_MISMATCH | 设备级别不符 |
| 409 | INVALID_ROSTER | 已保存的名单不符合演示数量限制 |
| 409 | DIVISION_FULL | 名额已满 |
| 409 | VERSION_CONFLICT | 报名版本过期或已处理 |

本阶段没有支付、飞手成长统计、公开人员列表、照片/证件上传、实时消息或视频 API。不要以产品文档中的未来接口调用当前服务。

## 队伍编辑（iOS 第二轮调整）

`PUT /teams/:id`：请求体与 `POST /teams` 相同，完整替换队名、城市、设备级别与名单（包含 `adultOnly: true`）。仅队长可编辑自己拥有的队伍；不存在或不属于自己的队伍返回 404，非队长返回 403，未登录返回 401，非法或重复名单返回 400。响应为更新后的 `id,name,city,category,roster`。

编辑仅影响后续报名。已提交报名保留提交时的队名、级别及人员名单，不随队伍编辑改变。本接口不提供删除队伍、真实成员身份或报名名单变更能力。
