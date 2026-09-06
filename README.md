# Drone-Match

> 第三轮 iOS 改造进行中：蓝色首页、招募/找队/约赛/志愿活动、申请留言与公开目录已编码，整项产品功能与界面验收尚未完成。详见 [第三轮改造清单](docs/design/第三轮改造与验收清单.md)。下文已实现列表保留上一轮稳定版本的说明。

无人机足球多俱乐部与赛事平台。原生 iOS App、Web 管理后台和统一后端在本地开发，GitHub 保存源代码与开发文档。

**当前为第一阶段的本地开发预览，不是可上线的完整 P0 产品。** 已打通真实 PostgreSQL 支持的“赛事发布 → 队伍报名 → 主办方审核 → 客户端查看结果”流程。所有预置机构、人员和赛事均为虚构演示资料。

## 已实现

- SwiftUI iOS：赛事、队伍、我的三栏；赛事搜索/城市与级别筛选、详情、演示登录、队伍创建与编辑、建队后继续报名、报名详情、退出登录。
- React/Ant Design Web：主办方工作台、发布赛事、报名审核；队长的赛事广场、队伍和报名管理。
- NestJS API + PostgreSQL：会话鉴权、机构/队伍权限、名单快照、报名去重、最后名额并发保护、审核版本控制和审计。
- 真实数据库集成测试，独立测试 schema，不清空开发数据。
- iOS 暂不展示生涯和视频主栏目；尚无正式成绩、计分、直播资源或视频服务。

## 本地启动

需要 Node.js 22.12+、npm、PostgreSQL 16+ 命令行工具（`initdb`、`pg_ctl`、`psql`、`createdb`）。iOS 需要 macOS、Xcode、iOS Simulator SDK 和至少一个可用模拟器。推荐 Node 22 LTS；本次本机也验证了 Node 25。

```bash
npm ci
npm run db:start
npm run db:setup
npm run dev
```

- Web 后台：<http://127.0.0.1:5173>
- API 健康检查：<http://127.0.0.1:3001/api/v1/health>
- 本地数据库：`postgresql://localhost:55432/drone_match`

`npm run db:start` 在项目 `.local/postgres` 创建独立数据库集群，仅监听本机 `127.0.0.1:55432`，不更改已有 PostgreSQL 服务。该本地集群采用 trust 鉴权，只用于本机开发。已有数据库可通过 `DATABASE_URL` 环境变量接入。

```bash
DATABASE_URL='postgresql://user:password@127.0.0.1:5432/drone_match' npm run db:setup
DATABASE_URL='postgresql://user:password@127.0.0.1:5432/drone_match' npm run dev
```

环境示例见 `.env.example`；当前脚本从进程环境读取，不会自动载入 `.env`。`db:setup` 为首版幂等建表和种子初始化，不重置已有报名，也不会将已过期演示赛事自动延期。后续结构变更应添加显式迁移。

停止 Web/API 用 `Ctrl+C`；停止本项目数据库用 `npm run db:stop`。开发数据、依赖、构建产物、缓存、环境文件不提交 Git。

## 启动 iOS

直接打开 `apps/ios/DroneMatch.xcodeproj`，选择 `DroneMatch` scheme 和一个 iPhone 模拟器运行。App 默认连接同一台 Mac 的 `127.0.0.1:3001`，请先启动后端。

如果本机 Xcode 的 scheme 目标解析要求尚未安装的较新 iOS 运行时，可用已安装 SDK 直接构建：

```bash
npm run ios:build
xcrun simctl list devices available
# 用上一步的设备 UUID 替换 SIMULATOR_ID
xcrun simctl boot SIMULATOR_ID
xcrun simctl bootstatus SIMULATOR_ID -b
xcrun simctl install SIMULATOR_ID .local/ios-build/DroneMatch.app
xcrun simctl launch SIMULATOR_ID com.dronematch.local
```

已启动的设备跳过 `boot`。`ios:build` 会使用模拟器专用的本地签名与 Keychain entitlement；不能关闭代码签名后仍假定 Keychain 登录可用。`Simulator.entitlements` 只匹配 Simulator SDK，不是正式开发者团队签名。

真机连接、正式 Bundle ID、Apple Team、发布 API 域名和生产签名尚未配置。新增 Swift 文件后运行 `python3 scripts/generate-ios-project.py` 更新可重复生成的 Xcode 工程；生成脚本不需要第三方 XcodeGen。

## 跨端体验

1. 浏览器打开后台，选择“青空赛事运营”，可发布本机构演示赛事。
2. iOS 选择“林教练”或“陈教练”演示账号；查看赛事，选择设备级别匹配的队伍，确认演示规则并提交。
3. 后台刷新，进入“报名审核”，查看名单后通过或驳回。
4. iOS “我的 → 我的报名”下拉刷新查看结果。App 回到前台也会刷新。
5. 切换到“远山赛事运营”，只能管理远山举办的赛事。不同机构的队伍可申请其他主办方的公开赛事，这是允许的参赛关系。

Web 也提供队长入口，可完整验证报名流程。驳回必须填写原因。审核通过占正式名额；待审申请不占名额；两人同时批准最后一个名额只允许一份成功。

## 验证

```bash
npm run check        # 后端和后台构建 + 真实 PostgreSQL 测试
npm run ios:build    # 原生模拟器构建
npm run format:check
```

测试账号为演示账号，不使用真实手机号/密码。演示会话须显式启用 `DEMO_MODE=true`，仅在本机服务使用；生产环境设置 `NODE_ENV=production` 时，启用演示鉴权会启动失败。不能把当前开发服务绑定公网、配置公开隧道或用于真实用户。

## 工程目录

```text
apps/ios/           SwiftUI App 与 Xcode 工程
apps/admin/         React + Ant Design 后台
apps/api/           NestJS API、数据库 schema、集成测试
scripts/            本地启动、数据库与 iOS 构建
.github/workflows/  Node/PostgreSQL CI 与 iOS 构建检查
docs/               产品文档、接口说明、开发进度与验证记录
```

## 当前边界与下一阶段

正式短信登录、机构入驻审核、未成年人/监护授权、真实飞手身份模型、人员跨队资格约束、名单锁定、检录、排赛计分、生涯统计、视频源、招募约赛、内容治理、用户注销和生产部署仍未实现。当前队伍名单是成人演示字符串快照，不是完整人员身份系统；没有声称验证真实年龄或资质。

数据库采用直接参数化 SQL，暂未加入 Prisma，减少首个垂直流程的依赖；遵循 PostgreSQL 事务与约束设计。演示赛事使用固定演示报名规则，不代替 FAI 或其他主办方正式规程。支付、Android 和硬件接入按产品文档后续阶段规划。

详细方案：[产品与开发文档](docs/无人机足球平台-产品与开发文档-v0.1.md) · [当前接口](docs/API.md) · [开发与验证记录](docs/开发进度.md)。
