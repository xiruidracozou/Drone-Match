import React, { useEffect, useState } from "react";
import { createRoot } from "react-dom/client";
import {
  Alert,
  App as AntApp,
  Avatar,
  Button,
  Checkbox,
  ConfigProvider,
  DatePicker,
  Empty,
  Form,
  Input,
  InputNumber,
  Modal,
  Select,
  Spin,
  Table,
  Tag,
} from "antd";
import zhCN from "antd/locale/zh_CN";
import {
  ArrowRightOutlined,
  CheckCircleOutlined,
  ClockCircleOutlined,
  EnvironmentOutlined,
  LogoutOutlined,
  PlusOutlined,
  ReloadOutlined,
  SearchOutlined,
  TeamOutlined,
  ThunderboltOutlined,
  TrophyOutlined,
  UnorderedListOutlined,
  AppstoreOutlined,
} from "@ant-design/icons";
import {
  Account,
  APIError,
  api,
  date,
  Registration,
  statusText,
  Team,
  Tournament,
} from "./api";
import "./styles.css";

function App() {
  const { message } = AntApp.useApp();
  const [token, setToken] = useState(
    sessionStorage.getItem("drone-match-token") || "",
  );
  const [account, setAccount] = useState<Account | null>(null);
  const [accounts, setAccounts] = useState<Account[]>([]);
  const [events, setEvents] = useState<Tournament[]>([]);
  const [registrations, setRegistrations] = useState<Registration[]>([]);
  const [teams, setTeams] = useState<Team[]>([]);
  const [tab, setTab] = useState("overview");
  const [search, setSearch] = useState("");
  const [filter, setFilter] = useState("all");
  const [loading, setLoading] = useState(true);
  const [error, setError] = useState("");
  const [revision, setRevision] = useState(0);
  const [busy, setBusy] = useState(false);
  const [modal, setModal] = useState<"event" | "team" | null>(null);
  const [detail, setDetail] = useState<Tournament | null>(null);
  const [review, setReview] = useState<Registration | null>(null);
  const [reviewStatus, setReviewStatus] = useState<"approved" | "rejected">(
    "approved",
  );
  const [note, setNote] = useState("");
  const [form] = Form.useForm();
  const [registrationForm] = Form.useForm();
  const organizer = account?.role === "organizer";
  const refresh = () => setRevision((n) => n + 1);
  useEffect(() => {
    let current = true;
    setLoading(true);
    setError("");
    async function load() {
      if (!token) {
        const rows = await api<Account[]>("/dev/accounts");
        if (current) {
          setAccounts(rows);
          setAccount(null);
        }
        return;
      }
      const me = await api<Account>("/me", token);
      const [ev, reg, tm] = await Promise.all([
        api<Tournament[]>(
          me.role === "organizer" ? "/admin/tournaments" : "/tournaments",
          token,
        ),
        api<Registration[]>("/registrations", token),
        api<Team[]>("/teams", token),
      ]);
      if (current) {
        setAccount(me);
        setEvents(ev);
        setRegistrations(reg);
        setTeams(tm);
      }
    }
    load()
      .catch((e) => {
        if (current) {
          setError(e.message);
          if (e instanceof APIError && e.status === 401) {
            sessionStorage.removeItem("drone-match-token");
            setToken("");
            setAccount(null);
          }
        }
      })
      .finally(() => {
        if (current) setLoading(false);
      });
    return () => {
      current = false;
    };
  }, [token, revision]);
  async function login(id: string) {
    setBusy(true);
    try {
      const result = await api<{ token: string; account: Account }>(
        "/dev/sessions",
        "",
        "POST",
        { accountId: id },
      );
      sessionStorage.setItem("drone-match-token", result.token);
      setToken(result.token);
      setTab("overview");
    } catch (e) {
      message.error((e as Error).message);
    } finally {
      setBusy(false);
    }
  }
  async function logout() {
    setBusy(true);
    try {
      await api("/auth/session", token, "DELETE");
      sessionStorage.removeItem("drone-match-token");
      setToken("");
      setAccount(null);
      setEvents([]);
      setRegistrations([]);
      setTeams([]);
      setDetail(null);
      setReview(null);
      setModal(null);
    } catch (e) {
      message.error((e as Error).message);
    } finally {
      setBusy(false);
    }
  }
  function openModal(kind: "event" | "team") {
    form.resetFields();
    setModal(kind);
  }
  async function create(values: Record<string, unknown>) {
    setBusy(true);
    try {
      if (modal === "event") {
        await api("/admin/tournaments", token, "POST", {
          ...values,
          startsAt: (
            values.startsAt as { toISOString(): string }
          ).toISOString(),
          deadline: (
            values.deadline as { toISOString(): string }
          ).toISOString(),
        });
      } else {
        await api("/teams", token, "POST", {
          ...values,
          roster: (values.roster as string)
            .split("\n")
            .map((s) => s.trim())
            .filter(Boolean),
        });
      }
      message.success(modal === "event" ? "赛事已发布" : "队伍已创建");
      setModal(null);
      refresh();
    } catch (e) {
      message.error((e as Error).message);
    } finally {
      setBusy(false);
    }
  }
  async function submitRegistration(values: {
    teamId: string;
    acceptRules: boolean;
  }) {
    if (!detail) return;
    setBusy(true);
    try {
      await api(
        `/tournaments/${detail.id}/registrations`,
        token,
        "POST",
        values,
      );
      message.success("报名已提交，等待主办方审核");
      setDetail(null);
      setTab("registrations");
      refresh();
    } catch (e) {
      message.error((e as Error).message);
    } finally {
      setBusy(false);
    }
  }
  async function submitReview() {
    if (!review) return;
    if (reviewStatus === "rejected" && !note.trim()) {
      message.error("请填写未通过的原因");
      return;
    }
    setBusy(true);
    try {
      await api(`/admin/registrations/${review.id}/review`, token, "POST", {
        status: reviewStatus,
        version: review.version,
        note,
      });
      message.success("审核结果已保存");
      setReview(null);
      refresh();
    } catch (e) {
      message.error((e as Error).message);
      refresh();
    } finally {
      setBusy(false);
    }
  }
  function openDetail(item: Tournament) {
    registrationForm.resetFields();
    setDetail(item);
  }
  const pending = registrations.filter((r) => r.status === "pending");
  const visibleEvents = events.filter((e) =>
    `${e.title}${e.city}`.includes(search),
  );
  const visibleRegistrations = registrations.filter(
    (r) =>
      (filter === "all" || r.status === filter) &&
      `${r.teamName}${r.tournamentTitle}`.includes(search),
  );
  const columns = [
    {
      title: "参赛队伍",
      dataIndex: "teamName",
      render: (name: string, row: Registration) => (
        <div className="table-team">
          <Avatar shape="square" icon={<TeamOutlined />} />
          <div>
            <strong>{name}</strong>
            <small>
              {row.roster.length} 名飞手 · {row.category}
            </small>
          </div>
        </div>
      ),
    },
    { title: "报名赛事", dataIndex: "tournamentTitle" },
    { title: "提交时间", dataIndex: "createdAt", render: date },
    {
      title: "状态",
      dataIndex: "status",
      render: (s: Registration["status"]) => (
        <Tag
          color={
            s === "approved" ? "green" : s === "pending" ? "gold" : "default"
          }
        >
          {statusText[s]}
        </Tag>
      ),
    },
    {
      title: "操作",
      key: "action",
      render: (_: unknown, r: Registration) => (
        <Button
          type="link"
          onClick={() => {
            setReview(r);
            setReviewStatus("approved");
            setNote("");
          }}
        >
          {organizer && r.status === "pending" ? "审核报名" : "查看详情"}{" "}
          <ArrowRightOutlined />
        </Button>
      ),
    },
  ];
  if (!account)
    return (
      <div className="login-page">
        <section className="login-brand">
          <div className="brand">
            <ThunderboltOutlined />
            <span>Drone Match</span>
          </div>
          <div>
            <h1>
              无人机足球
              <br />
              赛事管理中心
            </h1>
            <p>
              发布赛事、审核队伍报名，
              <br />
              集中管理机构的参赛信息。
            </p>
          </div>
          <span className="login-foot">Drone Match 赛事平台</span>
        </section>
        <section className="login-form">
          <Tag color="green">本地开发环境</Tag>
          <h2>进入赛事工作台</h2>
          <p className="muted">选择演示身份，体验不同机构的工作空间。</p>
          {error && (
            <Alert
              type="error"
              title={error}
              action={<Button onClick={refresh}>重试</Button>}
            />
          )}
          <Spin spinning={loading}>
            <div className="account-list">
              {accounts.map((a) => (
                <button
                  className="account-option"
                  key={a.id}
                  disabled={busy}
                  onClick={() => login(a.id)}
                >
                  <Avatar
                    icon={
                      a.role === "organizer" ? (
                        <TrophyOutlined />
                      ) : (
                        <TeamOutlined />
                      )
                    }
                  />
                  <span>
                    <strong>{a.name}</strong>
                    <small>
                      {a.organizationName} ·{" "}
                      {a.role === "organizer" ? "主办方" : "队长"}
                    </small>
                  </span>
                  <ArrowRightOutlined />
                </button>
              ))}
            </div>
          </Spin>
          <p className="dev-note">
            演示数据均为虚构。此版本仅在本机运行，真实短信登录与身份核验将在后续阶段接入。
          </p>
        </section>
      </div>
    );
  const nav = [
    { id: "overview", label: "工作台", icon: <AppstoreOutlined /> },
    {
      id: "events",
      label: organizer ? "赛事管理" : "赛事广场",
      icon: <TrophyOutlined />,
    },
    {
      id: "registrations",
      label: organizer ? "报名审核" : "我的报名",
      icon: <UnorderedListOutlined />,
    },
    ...(!organizer
      ? [{ id: "teams", label: "我的队伍", icon: <TeamOutlined /> }]
      : []),
  ];
  const headings: Record<string, string> = {
    overview: "工作台",
    events: organizer ? "赛事管理" : "赛事广场",
    registrations: organizer ? "报名审核" : "我的报名",
    teams: "我的队伍",
  };
  return (
    <div className="shell">
      <aside className="sidebar">
        <div className="brand">
          <ThunderboltOutlined />
          <span>
            Drone Match<small>无人机足球赛事平台</small>
          </span>
        </div>
        <div className="workspace-label">{account.organizationName}</div>
        <nav>
          {nav.map((n) => (
            <button
              className={tab === n.id ? "nav-item active" : "nav-item"}
              key={n.id}
              onClick={() => {
                setTab(n.id);
                setSearch("");
                setFilter("all");
              }}
            >
              {n.icon}
              <span>{n.label}</span>
              {n.id === "registrations" && pending.length > 0 && (
                <b>{pending.length}</b>
              )}
            </button>
          ))}
        </nav>
        <div className="sidebar-bottom">
          <div className="workspace-card">
            <CheckCircleOutlined />
            <div>
              独立机构工作空间<small>仅显示你有权限管理的数据</small>
            </div>
          </div>
          <button
            className="profile"
            aria-label="退出登录"
            onClick={logout}
            disabled={busy}
          >
            <Avatar>{account.name[0]}</Avatar>
            <span>
              {account.name}
              <small>{organizer ? "赛事运营" : "队伍管理"}</small>
            </span>
            <LogoutOutlined />
          </button>
        </div>
      </aside>
      <main className="main">
        <header className="topbar">
          <span>
            工作空间 <span className="slash">/</span>{" "}
            {nav.find((n) => n.id === tab)?.label}
          </span>
          <div>
            <Tag>本地演示</Tag>
            <Button
              icon={<ReloadOutlined />}
              onClick={refresh}
              loading={loading}
            >
              刷新数据
            </Button>
          </div>
        </header>
        <div className="page">
          <div className="page-heading">
            <div>
              <h1>{headings[tab]}</h1>
              <p className="muted">
                {organizer
                  ? `${account.organizationName} · ${pending.length} 条报名待处理`
                  : `${account.organizationName} · 管理队伍与参赛报名`}
              </p>
            </div>
            <Button
              type="primary"
              size="large"
              icon={<PlusOutlined />}
              onClick={() => openModal(organizer ? "event" : "team")}
            >
              {organizer ? "发布赛事" : "创建队伍"}
            </Button>
          </div>
          {error && (
            <Alert
              type="error"
              title={error}
              showIcon
              closable
              onClose={() => setError("")}
            />
          )}
          <Spin spinning={loading}>
            {tab === "overview" && (
              <>
                <div className="stat-grid">
                  {[
                    {
                      label: organizer ? "正在报名的赛事" : "可报名赛事",
                      value: events.filter(
                        (e) => e.status === "open" && e.approved < e.capacity,
                      ).length,
                      icon: <TrophyOutlined />,
                      hint: "报名通道开放中的赛事",
                    },
                    {
                      label: "待审核报名",
                      value: pending.length,
                      icon: <ClockCircleOutlined />,
                      hint: organizer
                        ? "需要你查看并处理"
                        : "已提交，等待主办方确认",
                    },
                    {
                      label: "已通过报名",
                      value: registrations.filter(
                        (r) => r.status === "approved",
                      ).length,
                      icon: <CheckCircleOutlined />,
                      hint: "已获得参赛资格",
                    },
                  ].map((s) => (
                    <div className="stat" key={s.label}>
                      <div>
                        {s.label}
                        {s.icon}
                      </div>
                      <strong>{s.value}</strong>
                      <small>{s.hint}</small>
                    </div>
                  ))}
                </div>
                <section className="table-panel">
                  <div className="section-heading">
                    <div>
                      <h2>{organizer ? "待审核报名" : "最近报名"}</h2>
                      <p className="muted">
                        {organizer
                          ? "核对队伍、设备级别与飞手名单后处理。"
                          : "报名状态与主办方审核结果保持同步。"}
                      </p>
                    </div>
                    <Button onClick={() => setTab("registrations")}>
                      全部报名 <ArrowRightOutlined />
                    </Button>
                  </div>
                  <Table
                    rowKey="id"
                    columns={columns}
                    dataSource={(organizer ? pending : registrations).slice(
                      0,
                      5,
                    )}
                    pagination={false}
                    scroll={{ x: 760 }}
                    locale={{
                      emptyText: (
                        <Empty
                          image={Empty.PRESENTED_IMAGE_SIMPLE}
                          description={
                            organizer
                              ? "当前没有待审核报名"
                              : "还没有报名，去看看赛事吧"
                          }
                        />
                      ),
                    }}
                  />
                </section>
                <div className="section-heading">
                  <h2>{organizer ? "近期赛事" : "近期赛事"}</h2>
                  <Button type="text" onClick={() => setTab("events")}>
                    查看全部 <ArrowRightOutlined />
                  </Button>
                </div>
                <div className="event-grid">
                  {events.slice(0, 2).map((e) => (
                    <EventCard
                      key={e.id}
                      event={e}
                      onClick={() => openDetail(e)}
                    />
                  ))}
                </div>
              </>
            )}
            {tab === "events" && (
              <>
                <div className="toolbar">
                  <Input
                    prefix={<SearchOutlined />}
                    placeholder="搜索赛事或城市"
                    aria-label="搜索赛事或城市"
                    value={search}
                    onChange={(e) => setSearch(e.target.value)}
                    allowClear
                  />
                  <span className="muted">
                    共 {visibleEvents.length} 场赛事
                  </span>
                </div>
                <div className="event-grid">
                  {visibleEvents.map((e) => (
                    <EventCard
                      key={e.id}
                      event={e}
                      onClick={() => openDetail(e)}
                    />
                  ))}
                </div>
                {visibleEvents.length === 0 && (
                  <Empty description="没有找到相关赛事" />
                )}
              </>
            )}
            {tab === "registrations" && (
              <section className="table-panel">
                <div className="toolbar">
                  <Input
                    prefix={<SearchOutlined />}
                    placeholder="搜索队伍或赛事"
                    aria-label="搜索报名"
                    value={search}
                    onChange={(e) => setSearch(e.target.value)}
                    allowClear
                  />
                  <Select
                    aria-label="筛选报名状态"
                    value={filter}
                    onChange={setFilter}
                    options={[
                      { value: "all", label: "全部状态" },
                      ...Object.entries(statusText).map(([value, label]) => ({
                        value,
                        label,
                      })),
                    ]}
                  />
                </div>
                <Table
                  rowKey="id"
                  columns={columns}
                  dataSource={visibleRegistrations}
                  scroll={{ x: 760 }}
                  pagination={{ pageSize: 8, hideOnSinglePage: true }}
                  locale={{ emptyText: <Empty description="暂无报名记录" /> }}
                />
              </section>
            )}
            {tab === "teams" && (
              <div className="team-grid">
                {teams.map((team) => (
                  <section className="team-card" key={team.id}>
                    <Avatar size={56} shape="square" icon={<TeamOutlined />} />
                    <h2>{team.name}</h2>
                    <p className="muted">
                      {team.city} · {team.category} 级
                    </p>
                    <div className="roster">
                      {team.roster.map((name) => (
                        <Tag key={name}>{name}</Tag>
                      ))}
                    </div>
                    <small className="muted">
                      {team.roster.length} 名成年演示飞手
                    </small>
                  </section>
                ))}
                {teams.length === 0 && (
                  <Empty description="还没有队伍，创建后即可报名" />
                )}
              </div>
            )}
          </Spin>
          <footer className="page-footer">
            Drone Match <span>本地开发环境 · 仅使用演示资料</span>
          </footer>
        </div>
      </main>
      <Modal
        title={modal === "event" ? "发布演示赛事" : "创建演示队伍"}
        open={!!modal}
        onCancel={() => !busy && setModal(null)}
        onOk={() => form.submit()}
        confirmLoading={busy}
        okText={modal === "event" ? "确认发布" : "创建队伍"}
        cancelText="取消"
        destroyOnHidden
      >
        <Form
          form={form}
          layout="vertical"
          onFinish={create}
          initialValues={{ category: "20cm", capacity: 16 }}
        >
          <Alert
            type="info"
            title="仅用于本地成年飞手演示，不用于真实赛事报名。"
            showIcon
            className="form-note"
          />
          <Form.Item
            name={modal === "event" ? "title" : "name"}
            label={modal === "event" ? "赛事名称" : "队伍名称"}
            rules={[
              {
                required: true,
                min: 2,
                max: 80,
                message: "请输入 2–80 字名称",
              },
            ]}
          >
            <Input maxLength={80} />
          </Form.Item>
          <div className="form-row">
            <Form.Item
              name="city"
              label="城市"
              rules={[{ required: true, min: 2, message: "请输入城市" }]}
            >
              <Input />
            </Form.Item>
            <Form.Item
              name="category"
              label="设备级别"
              rules={[{ required: true }]}
            >
              <Select
                options={[
                  { value: "20cm", label: "20cm 级" },
                  { value: "40cm", label: "40cm 级" },
                ]}
              />
            </Form.Item>
          </div>
          {modal === "event" ? (
            <>
              <Form.Item
                name="venue"
                label="比赛场地"
                rules={[{ required: true, min: 2, message: "请输入比赛场地" }]}
              >
                <Input />
              </Form.Item>
              <div className="form-row">
                <Form.Item
                  name="deadline"
                  label="报名截止（本地时间）"
                  rules={[{ required: true }]}
                >
                  <DatePicker
                    showTime
                    format="YYYY-MM-DD HH:mm"
                    style={{ width: "100%" }}
                  />
                </Form.Item>
                <Form.Item
                  name="startsAt"
                  label="比赛开始（本地时间）"
                  rules={[{ required: true }]}
                >
                  <DatePicker
                    showTime
                    format="YYYY-MM-DD HH:mm"
                    style={{ width: "100%" }}
                  />
                </Form.Item>
              </div>
              <Form.Item
                name="capacity"
                label="队伍名额"
                rules={[{ required: true }]}
              >
                <InputNumber min={1} max={128} />
              </Form.Item>
              <Form.Item
                name="description"
                label="赛事介绍"
                rules={[
                  {
                    required: true,
                    min: 4,
                    message: "请填写至少 4 字赛事介绍",
                  },
                ]}
              >
                <Input.TextArea rows={3} maxLength={2000} />
              </Form.Item>
            </>
          ) : (
            <>
              <Form.Item
                name="roster"
                label="飞手名单（每行一名，最多 10 名）"
                rules={[{ required: true, message: "请填写成年演示飞手名单" }]}
              >
                <Input.TextArea rows={4} />
              </Form.Item>
              <Form.Item
                name="adultOnly"
                valuePropName="checked"
                rules={[
                  {
                    validator: (_, v) =>
                      v
                        ? Promise.resolve()
                        : Promise.reject(new Error("请确认仅使用成年演示资料")),
                  },
                ]}
              >
                <Checkbox>仅使用成年飞手的虚构演示资料</Checkbox>
              </Form.Item>
            </>
          )}
        </Form>
      </Modal>
      <Modal
        title="赛事详情"
        open={!!detail}
        onCancel={() => !busy && setDetail(null)}
        footer={null}
        width={640}
        destroyOnHidden
      >
        {detail && (
          <>
            <Tag color="green">{detail.category} 级</Tag>
            <h2>{detail.title}</h2>
            <p>{detail.description}</p>
            <div className="detail-facts">
              <p>
                主办方 <strong>{detail.organizerName}</strong>
              </p>
              <p>
                比赛时间 <strong>{date(detail.startsAt)}</strong>
              </p>
              <p>
                报名截止 <strong>{date(detail.deadline)}</strong>
              </p>
              <p>
                比赛场地{" "}
                <strong>
                  {detail.city} · {detail.venue}
                </strong>
              </p>
              <p>
                已通过 / 总名额{" "}
                <strong>
                  {detail.approved} / {detail.capacity} 队
                </strong>
              </p>
            </div>
            <h3>报名说明</h3>
            <p className="rules">{detail.rules}</p>
            {!organizer &&
              (registrations.some((r) => r.tournamentId === detail.id) ? (
                <Alert
                  type="success"
                  title="已有报名记录，请前往“我的报名”查看进度。"
                />
              ) : detail.status === "closed" ||
                detail.approved >= detail.capacity ? (
                <Alert type="warning" title="报名已截止或名额已满" />
              ) : teams.filter((t) => t.category === detail.category).length ===
                0 ? (
                <Alert type="info" title="请先创建与本赛事设备级别一致的队伍" />
              ) : (
                <Form
                  form={registrationForm}
                  layout="vertical"
                  onFinish={submitRegistration}
                >
                  <Form.Item
                    name="teamId"
                    label="选择报名队伍"
                    rules={[{ required: true, message: "请选择队伍" }]}
                  >
                    <Select
                      options={teams
                        .filter((t) => t.category === detail.category)
                        .map((t) => ({
                          value: t.id,
                          label: `${t.name} · ${t.roster.length} 人`,
                        }))}
                    />
                  </Form.Item>
                  <Form.Item
                    name="acceptRules"
                    valuePropName="checked"
                    rules={[
                      {
                        validator: (_, v) =>
                          v
                            ? Promise.resolve()
                            : Promise.reject(
                                new Error("请先阅读并同意报名说明"),
                              ),
                      },
                    ]}
                  >
                    <Checkbox>已阅读演示规则，确认提交当前队伍名单</Checkbox>
                  </Form.Item>
                  <Button type="primary" block htmlType="submit" loading={busy}>
                    提交报名
                  </Button>
                </Form>
              ))}
          </>
        )}
      </Modal>
      <Modal
        title={
          organizer && review?.status === "pending"
            ? "审核队伍报名"
            : "报名详情"
        }
        open={!!review}
        onCancel={() => !busy && setReview(null)}
        footer={
          organizer && review?.status === "pending" ? (
            <>
              <Button onClick={() => setReview(null)} disabled={busy}>
                取消
              </Button>
              <Button type="primary" onClick={submitReview} loading={busy}>
                确认审核
              </Button>
            </>
          ) : null
        }
        destroyOnHidden
      >
        {review && (
          <>
            <h2>{review.teamName}</h2>
            <p className="muted">{review.tournamentTitle}</p>
            <Tag color={review.status === "approved" ? "green" : "gold"}>
              {statusText[review.status]}
            </Tag>
            <h3>提交时的飞手名单</h3>
            <div className="roster">
              {review.roster.map((name) => (
                <Tag key={name}>{name}</Tag>
              ))}
            </div>
            {organizer && review.status === "pending" ? (
              <>
                <label className="field-label" htmlFor="review-status">
                  审核结果
                </label>
                <Select
                  id="review-status"
                  value={reviewStatus}
                  onChange={setReviewStatus}
                  style={{ width: "100%" }}
                  options={[
                    { value: "approved", label: "通过，分配参赛名额" },
                    { value: "rejected", label: "未通过" },
                  ]}
                />
                <label className="field-label" htmlFor="review-note">
                  {reviewStatus === "rejected"
                    ? "未通过原因（必填）"
                    : "审核备注（选填）"}
                </label>
                <Input.TextArea
                  id="review-note"
                  value={note}
                  onChange={(e) => setNote(e.target.value)}
                  maxLength={500}
                  rows={3}
                />
              </>
            ) : (
              <p>审核说明：{review.reviewNote || "暂无补充说明"}</p>
            )}
          </>
        )}
      </Modal>
    </div>
  );
}
function EventCard({
  event: e,
  onClick,
}: {
  event: Tournament;
  onClick: () => void;
}) {
  const starts = new Date(e.startsAt);
  return (
    <button className="event-card" onClick={onClick}>
      <div className="event-date">
        <span>{starts.getMonth() + 1}月</span>
        <strong>{starts.getDate()}</strong>
        <small>{e.category}</small>
      </div>
      <div className="event-content">
        <div>
          <Tag
            color={
              e.status === "open" && e.approved < e.capacity
                ? "green"
                : "default"
            }
          >
            {e.status === "closed"
              ? "报名截止"
              : e.approved >= e.capacity
                ? "名额已满"
                : "报名中"}
          </Tag>
          <span className="muted">
            {e.approved}/{e.capacity} 队已通过
          </span>
        </div>
        <h3>{e.title}</h3>
        <p>
          <EnvironmentOutlined /> {e.city}　{e.venue}
        </p>
        <div className="event-bottom">
          <span>{date(e.startsAt)}</span>
          <span>查看详情</span>
        </div>
      </div>
    </button>
  );
}
createRoot(document.getElementById("root")!).render(
  <React.StrictMode>
    <ConfigProvider
      locale={zhCN}
      theme={{
        token: {
          colorPrimary: "#008a46",
          borderRadius: 8,
          fontFamily:
            '-apple-system, BlinkMacSystemFont, "PingFang SC", "Microsoft YaHei", sans-serif',
          colorText: "#18221d",
          colorTextSecondary: "#66716b",
          controlHeight: 40,
        },
        components: {
          Button: { primaryShadow: "none" },
          Table: { headerBg: "#f6f8f6", headerColor: "#64736b" },
        },
      }}
    >
      <AntApp>
        <App />
      </AntApp>
    </ConfigProvider>
  </React.StrictMode>,
);
