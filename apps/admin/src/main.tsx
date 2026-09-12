import React, { useEffect, useState } from "react";
import { createRoot } from "react-dom/client";
import {
  App as AntApp,
  ConfigProvider,
  Alert,
  Avatar,
  Button,
  Drawer,
  Empty,
  Form,
  Input,
  Menu,
  Select,
  Space,
  Spin,
  Table,
  Tag,
  Tabs,
} from "antd";
import zhCN from "antd/locale/zh_CN";
import {
  AppstoreOutlined,
  PictureOutlined,
  TrophyOutlined,
  TeamOutlined,
  CalendarOutlined,
  AuditOutlined,
  MessageOutlined,
  UserOutlined,
  ApartmentOutlined,
  FileTextOutlined,
  LogoutOutlined,
  MenuOutlined,
  ReloadOutlined,
  PlusOutlined,
  SearchOutlined,
} from "@ant-design/icons";
import { api, APIError } from "./api";
import {
  Row,
  titles,
  kinds,
  statuses,
  display,
  labels,
} from "./platform-model";
import { MutationForm, ReasonAction, RecordDetails } from "./platform-ui";
import { ContentEditor, ContentPreview } from "./content-editor";
import "./styles.css";
const icons = [
  <AppstoreOutlined />,
  <PictureOutlined />,
  <TrophyOutlined />,
  <AuditOutlined />,
  <CalendarOutlined />,
  <ApartmentOutlined />,
  <TeamOutlined />,
  <MessageOutlined />,
  <UserOutlined />,
  <MessageOutlined />,
  <FileTextOutlined />,
];
const navigation = Object.entries(titles).map(([key, label], i) => ({
  key,
  label,
  icon: icons[i],
}));
const resourceFromHash = () =>
  Object.hasOwn(titles, location.hash.slice(1))
    ? location.hash.slice(1)
    : "overview";
function PlatformApp() {
  const [token, setToken] = useState(
      sessionStorage.getItem("platform-token") || "",
    ),
    [account, setAccount] = useState<Row | null>(null),
    [resource, setResource] = useState(resourceFromHash),
    [navOpen, setNavOpen] = useState(false),
    [rows, setRows] = useState<Row[]>([]),
    [total, setTotal] = useState(0),
    [page, setPage] = useState(1),
    [query, setQuery] = useState(""),
    [status, setStatus] = useState(""),
    [parent, setParent] = useState(""),
    [revision, setRevision] = useState(0),
    [loading, setLoading] = useState(false),
    [error, setError] = useState(""),
    [lookups, setLookups] = useState<Row>({}),
    [overview, setOverview] = useState<Row>({}),
    [selected, setSelected] = useState<Row | null>(null),
    [editing, setEditing] = useState(false),
    [related, setRelated] = useState<Row[]>([]),
    [members, setMembers] = useState<Row[]>([]),
    [conversation, setConversation] = useState<Row | null>(null);
  const refresh = () => setRevision((n) => n + 1);
  const navigate = (key: string) => {
    history.pushState({}, "", "#" + key);
    setResource(key);
    setQuery("");
    setStatus("");
    setParent("");
    setPage(1);
    setSelected(null);
    setEditing(false);
    setNavOpen(false);
    setError("");
  };
  useEffect(() => {
    const handler = () => {
      setResource(resourceFromHash());
      setSelected(null);
      setPage(1);
      setQuery("");
      setStatus("");
      setParent("");
    };
    window.addEventListener("hashchange", handler);
    window.addEventListener("popstate", handler);
    return () => {
      window.removeEventListener("hashchange", handler);
      window.removeEventListener("popstate", handler);
    };
  }, []);
  const fail = (e: Error) => {
    setError(e.message);
    if (e instanceof APIError && e.status === 401) {
      sessionStorage.removeItem("platform-token");
      setToken("");
      setAccount(null);
      setRows([]);
      setSelected(null);
      setConversation(null);
    }
  };
  useEffect(() => {
    if (!token) return;
    let active = true;
    Promise.all([
      api<Row>("/platform/me", token),
      api<Row>("/platform/lookups", token),
    ])
      .then(([me, l]) => {
        if (active) {
          setAccount(me);
          setLookups(l);
        }
      })
      .catch((e) => {
        if (active) fail(e);
      });
    return () => {
      active = false;
    };
  }, [token, revision]);
  useEffect(() => {
    if (!token) return;
    let active = true;
    setLoading(true);
    setError("");
    const timer = setTimeout(async () => {
      try {
        if (resource === "overview") {
          const data = await api<Row>("/platform/overview", token);
          if (active) setOverview(data);
        } else {
          const params = new URLSearchParams({
            q: query,
            status,
            parent,
            offset: String((page - 1) * 30),
            limit: "30",
          });
          const data = await api<{ rows: Row[]; total: number }>(
            `/platform/${resource}?${params}`,
            token,
          );
          if (active) {
            setRows(data.rows);
            setTotal(data.total);
          }
        }
      } catch (e) {
        if (active) fail(e as Error);
      } finally {
        if (active) setLoading(false);
      }
    }, 200);
    return () => {
      active = false;
      clearTimeout(timer);
    };
  }, [token, resource, query, status, parent, page, revision]);
  useEffect(() => {
    setRelated([]);
    setMembers([]);
    setConversation(null);
    if (!selected?.id || !token) return;
    let active = true;
    (async () => {
      if (resource === "posts") {
        let offset = 0;
        let items: Row[] = [];
        while (active) {
          const result = await api<{ rows: Row[]; total: number }>(
            "/platform/applications?parent=" +
              selected.id +
              "&limit=100&offset=" +
              offset,
            token,
          );
          items.push(...result.rows);
          offset += result.rows.length;
          if (offset >= result.total || !result.rows.length) break;
        }
        if (active) setRelated(items);
      } else if (resource === "teams") {
        const result = await api<Row[]>(
          "/platform/teams/" + selected.id + "/members",
          token,
        );
        if (active) setMembers(result);
      } else if (resource !== "audit") {
        const result = await api<{ rows: Row[] }>(
          "/platform/audit?parent=" + selected.id + "&limit=100",
          token,
        );
        if (active) setRelated(result.rows);
      }
    })().catch((e) => {
      if (active) setError(e.message);
    });
    return () => {
      active = false;
    };
  }, [selected, resource, token]);
  const done = () => {
    setSelected(null);
    setEditing(false);
    setConversation(null);
    refresh();
  };
  if (!token)
    return (
      <main className="login-page">
        <section className="login-intro">
          <div className="brand">
            <TrophyOutlined /> DRONE MATCH
          </div>
          <h1>
            无人机足球
            <br />
            平台运营中心
          </h1>
          <p>赛事、内容与社区，在同一个工作台中管理。</p>
          <div className="login-note">俱乐部、主办方及队长请使用移动端。</div>
        </section>
        <section className="login-panel">
          <span className="eyebrow">平台专用</span>
          <h2>登录工作台</h2>
          <p className="muted">使用已创建的平台管理员账号。</p>
          {error && <Alert title={error} type="error" showIcon />}
          <Form
            layout="vertical"
            onFinish={async (values) => {
              setLoading(true);
              setError("");
              try {
                const result = await api<{ token: string; account: Row }>(
                  "/platform/sessions",
                  "",
                  "POST",
                  values,
                );
                sessionStorage.setItem("platform-token", result.token);
                setToken(result.token);
                setAccount(result.account);
              } catch (e) {
                setError((e as Error).message);
              } finally {
                setLoading(false);
              }
            }}
          >
            <Form.Item
              name="username"
              label="管理员账号"
              rules={[{ required: true }]}
            >
              <Input autoComplete="username" size="large" />
            </Form.Item>
            <Form.Item
              name="password"
              label="密码"
              rules={[{ required: true }]}
            >
              <Input.Password autoComplete="current-password" size="large" />
            </Form.Item>
            <Button
              block
              type="primary"
              size="large"
              htmlType="submit"
              loading={loading}
            >
              登录
            </Button>
          </Form>
        </section>
      </main>
    );
  const columns: any[] = [
    {
      title: resource === "content" ? "内容" : "名称 / 记录",
      key: "title",
      render: (_: unknown, row: Row) => (
        <Button
          type="link"
          className="row-title"
          onClick={() => {
            setSelected(row);
            setEditing(false);
          }}
        >
          {row.draft?.title ||
            row.title ||
            row.name ||
            row.team_name ||
            row.category ||
            row.action ||
            row.id}
        </Button>
      ),
    },
    ...(resource === "content"
      ? [
          { title: "类型", dataIndex: "kind", render: (v: string) => kinds[v] },
          {
            title: "发布状态",
            render: (_: unknown, r: Row) => (
              <Tag color={r.published ? "blue" : "default"}>
                {r.published ? "已发布" : "未发布"}
              </Tag>
            ),
          },
          { title: "城市", render: (_: unknown, r: Row) => r.draft.city },
        ]
      : [
          {
            title: resource === "audit" ? "对象" : "城市 / 身份",
            render: (_: unknown, r: Row) =>
              display(
                r.city || r.role || r.resource_type || r.tournament_id || "—",
              ),
          },
          {
            title: "状态",
            render: (_: unknown, r: Row) =>
              r.hidden ? (
                <Tag color="red">已下架</Tag>
              ) : r.disabled ? (
                <Tag color="red">已停用</Tag>
              ) : r.status ? (
                <Tag
                  color={
                    ["approved", "resolved", "final"].includes(r.status)
                      ? "blue"
                      : "default"
                  }
                >
                  {display(r.status)}
                </Tag>
              ) : (
                <span className="muted">正常</span>
              ),
          },
        ]),
    {
      title: "时间",
      render: (_: unknown, r: Row) => {
        const value = r.updated_at || r.starts_at || r.created_at;
        return value
          ? new Date(value).toLocaleString("zh-CN", { hour12: false })
          : "—";
      },
    },
    {
      title: "操作",
      render: (_: unknown, r: Row) => (
        <Button
          onClick={() => {
            setSelected(r);
            setEditing(false);
          }}
        >
          查看详情
        </Button>
      ),
    },
  ];
  const contentActions =
    selected && resource === "content" ? (
      <Space wrap>
        <Button type="primary" onClick={() => setEditing(true)}>
          编辑草稿
        </Button>
        <ReasonAction
          title="发布草稿"
          description="当前草稿将替换移动端已发布内容。请核对下方预览。"
          run={(reason) =>
            api("/platform/content/" + selected.id, token, "PUT", {
              version: selected.version,
              operation: "publish",
              reason,
            })
          }
          onDone={done}
        />
        {selected.published && (
          <ReasonAction
            title="下架内容"
            description="刷新后移动端不再展示该内容。"
            run={(reason) =>
              api("/platform/content/" + selected.id, token, "PUT", {
                version: selected.version,
                operation: "unpublish",
                reason,
              })
            }
            onDone={done}
          />
        )}
      </Space>
    ) : null;
  return (
    <div className="platform-shell">
      <aside className="sidebar">
        <div className="brand">
          <TrophyOutlined />
          <span>
            DRONE MATCH<small>平台运营中心</small>
          </span>
        </div>
        <Menu
          mode="inline"
          selectedKeys={[resource]}
          items={navigation}
          onClick={({ key }) => navigate(key)}
        />
        <div className="sidebar-footer">
          与移动端共用业务数据
          <br />
          <span>平台操作全程留痕</span>
        </div>
      </aside>
      <Drawer
        title="平台导航"
        placement="left"
        open={navOpen}
        onClose={() => setNavOpen(false)}
      >
        <Menu
          selectedKeys={[resource]}
          items={navigation}
          onClick={({ key }) => navigate(key)}
        />
      </Drawer>
      <main className="workspace">
        <header className="topbar">
          <Button
            className="mobile-menu"
            icon={<MenuOutlined />}
            aria-label="展开导航"
            onClick={() => setNavOpen(true)}
          />
          <span>平台 / {titles[resource]}</span>
          <Space>
            <Avatar size="small" icon={<UserOutlined />} />
            <span>{account?.username}</span>
            <Button
              type="text"
              icon={<LogoutOutlined />}
              onClick={async () => {
                try {
                  await api("/platform/session", token, "DELETE");
                  sessionStorage.removeItem("platform-token");
                  setToken("");
                  setAccount(null);
                  setSelected(null);
                  setConversation(null);
                } catch (e) {
                  fail(e as Error);
                }
              }}
            >
              退出
            </Button>
          </Space>
        </header>
        <section className="page-content">
          <div className="page-heading">
            <div>
              <h1>{titles[resource]}</h1>
              <p className="muted">
                {resource === "overview"
                  ? "查看平台动态，处理当前待办。"
                  : resource === "content"
                    ? "管理移动端展示内容，先保存草稿，核对后发布。"
                    : "查询全站记录，查看关联业务与操作历史。"}
              </p>
            </div>
            <Space>
              <Button icon={<ReloadOutlined />} onClick={refresh}>
                刷新
              </Button>
              {["content", "tournaments", "organizations", "matches"].includes(
                resource,
              ) && (
                <Button
                  type="primary"
                  icon={<PlusOutlined />}
                  onClick={() => {
                    setSelected({});
                    setEditing(true);
                  }}
                >
                  新增
                </Button>
              )}
            </Space>
          </div>
          {error && (
            <Alert
              showIcon
              title={error}
              type="error"
              action={<Button onClick={refresh}>重试</Button>}
            />
          )}
          <Spin spinning={loading}>
            {resource === "overview" ? (
              <>
                <div className="metrics">
                  {[
                    ["tournaments", "全站赛事", "tournaments"],
                    ["users", "可用账号", "users"],
                    ["posts", "公开社区活动", "posts"],
                  ].map(([key, label, target]) => (
                    <button
                      className="metric"
                      key={key}
                      onClick={() => navigate(target)}
                    >
                      <span>{label}</span>
                      <strong>{overview[key] ?? "—"}</strong>
                      <small>查看记录 →</small>
                    </button>
                  ))}
                </div>
                <section className="panel">
                  <div className="section-heading">
                    <h2>待处理</h2>
                    <span className="muted">根据当前业务记录汇总</span>
                  </div>
                  <button
                    className="task-row"
                    onClick={() => {
                      navigate("registrations");
                      setStatus("pending");
                    }}
                  >
                    <div>
                      <AuditOutlined />
                      <span>
                        <strong>待审核报名</strong>
                        <small>核对参赛队伍、设备级别与名单</small>
                      </span>
                    </div>
                    <b>{overview.pending ?? "—"} →</b>
                  </button>
                  <button
                    className="task-row"
                    onClick={() => navigate("feedback")}
                  >
                    <div>
                      <MessageOutlined />
                      <span>
                        <strong>用户反馈</strong>
                        <small>跟进问题，回复处理结果</small>
                      </span>
                    </div>
                    <b>{overview.feedback ?? "—"} →</b>
                  </button>
                </section>
                <section className="panel">
                  <h2>最近发布</h2>
                  {(overview.recentContent || []).map((c: Row) => (
                    <button
                      className="task-row"
                      key={c.id}
                      onClick={() => {
                        navigate("content");
                        setQuery(c.id);
                      }}
                    >
                      <span>{c.published.title}</span>
                      <span className="muted">
                        {kinds[c.kind]} ·{" "}
                        {new Date(c.updated_at).toLocaleDateString()}
                      </span>
                    </button>
                  ))}
                </section>
                <section className="panel">
                  <h2>常用操作</h2>
                  <Space wrap>
                    <Button onClick={() => navigate("content")}>
                      维护首页内容
                    </Button>
                    <Button onClick={() => navigate("posts")}>
                      巡查社区发布
                    </Button>
                    <Button onClick={() => navigate("matches")}>
                      查看赛程与比分
                    </Button>
                    <Button onClick={() => navigate("audit")}>
                      查询操作记录
                    </Button>
                  </Space>
                </section>
              </>
            ) : (
              <section className="panel data-panel">
                <div className="filters">
                  <Input
                    prefix={<SearchOutlined />}
                    aria-label="搜索记录"
                    placeholder="搜索名称、城市或编号"
                    value={query}
                    onChange={(e) => {
                      setQuery(e.target.value);
                      setPage(1);
                    }}
                    allowClear
                  />
                  {["registrations", "matches"].includes(resource) && (
                    <Select
                      allowClear
                      placeholder="全部赛事"
                      aria-label="按赛事筛选"
                      value={parent || undefined}
                      onChange={(v) => {
                        setParent(v || "");
                        setPage(1);
                      }}
                      options={(lookups.tournaments || []).map((r: Row) => ({
                        value: r.id,
                        label: r.title,
                      }))}
                    />
                  )}{" "}
                  {["registrations", "matches", "posts", "feedback"].includes(
                    resource,
                  ) && (
                    <Select
                      allowClear
                      placeholder="全部状态"
                      aria-label="按状态筛选"
                      value={status || undefined}
                      onChange={(v) => {
                        setStatus(v || "");
                        setPage(1);
                      }}
                      options={(resource === "registrations"
                        ? ["pending", "approved", "rejected"]
                        : resource === "matches"
                          ? ["scheduled", "final", "cancelled"]
                          : resource === "feedback"
                            ? ["received", "processing", "resolved"]
                            : ["open", "closed", "matched", "cancelled"]
                      ).map((value) => ({ value, label: statuses[value] }))}
                    />
                  )}
                  <span className="muted">共 {total} 条</span>
                </div>
                <Table
                  rowKey="id"
                  dataSource={rows}
                  columns={columns}
                  scroll={{ x: 780 }}
                  pagination={{
                    current: page,
                    pageSize: 30,
                    total,
                    onChange: setPage,
                    showSizeChanger: false,
                  }}
                  locale={{
                    emptyText: (
                      <Empty description="没有匹配记录，试试其他筛选条件" />
                    ),
                  }}
                />
              </section>
            )}
          </Spin>
        </section>
      </main>
      <Drawer
        size={760}
        open={!!selected}
        onClose={() => {
          setSelected(null);
          setEditing(false);
          setConversation(null);
        }}
        title={
          editing
            ? (selected?.id ? "编辑" : "新增") + titles[resource]
            : titles[resource] + "详情"
        }
        destroyOnHidden
      >
        {selected &&
          (editing ? (
            resource === "content" ? (
              <ContentEditor row={selected} token={token} onDone={done} />
            ) : (
              <MutationForm
                resource={resource}
                row={selected}
                lookups={lookups}
                token={token}
                onDone={done}
                onCancel={() =>
                  selected.id ? setEditing(false) : setSelected(null)
                }
              />
            )
          ) : (
            <>
              <div className="detail-actions">
                {contentActions}
                {!["audit", "posts", "content"].includes(resource) && (
                  <Button type="primary" onClick={() => setEditing(true)}>
                    平台代办 / 修改
                  </Button>
                )}
                {["tournaments", "posts"].includes(resource) && (
                  <ReasonAction
                    title={selected.hidden ? "恢复展示" : "下架内容"}
                    description={
                      selected.hidden
                        ? "恢复公开展示，不会重新开启已结束的活动。"
                        : "退出公开列表并阻止新增参与；保留已有历史记录。"
                    }
                    run={(reason) =>
                      api(
                        `/platform/${resource}/${selected.id}`,
                        token,
                        "PATCH",
                        {
                          version: selected.version,
                          reason,
                          values: { hidden: !selected.hidden },
                        },
                      )
                    }
                    onDone={done}
                  />
                )}
                {resource === "organizations" && (
                  <>
                    {[
                      ["teams", "所属队伍"],
                      ["users", "所属账号"],
                      ["tournaments", "所属赛事"],
                    ].map(([key, label]) => (
                      <Button
                        key={key}
                        onClick={() => {
                          const id = selected.id;
                          navigate(key);
                          setParent(id);
                        }}
                      >
                        {label}
                      </Button>
                    ))}
                  </>
                )}
                {resource === "tournaments" && (
                  <>
                    <Button
                      onClick={() => {
                        const id = selected.id;
                        navigate("registrations");
                        setParent(id);
                      }}
                    >
                      查看报名
                    </Button>
                    <Button
                      onClick={() => {
                        const id = selected.id;
                        navigate("matches");
                        setParent(id);
                      }}
                    >
                      查看赛程
                    </Button>
                  </>
                )}
              </div>
              {resource === "content" ? (
                <>
                  <Tag>{kinds[selected.kind]}</Tag>
                  <p className="muted">
                    内容编号：{selected.id} · 版本 {selected.version}
                  </p>
                  <Tabs
                    items={[
                      {
                        key: "draft",
                        label: "当前草稿",
                        children: (
                          <ContentPreview
                            data={selected.draft}
                            kind={selected.kind}
                          />
                        ),
                      },
                      {
                        key: "published",
                        label: "已发布版本",
                        children: selected.published ? (
                          <ContentPreview
                            data={selected.published}
                            kind={selected.kind}
                          />
                        ) : (
                          <Empty description="尚未发布" />
                        ),
                      },
                    ]}
                  />
                </>
              ) : (
                <RecordDetails row={selected} lookups={lookups} />
              )}
              {resource === "teams" && (
                <>
                  <h3>社区成员</h3>
                  {members.map((m) => (
                    <div className="member-row" key={m.id}>
                      <span>
                        {m.name} {m.is_owner && <Tag>负责人</Tag>}
                      </span>
                      {!m.is_owner && (
                        <ReasonAction
                          title="移除成员"
                          description="不会改变已提交的赛事报名名单。"
                          run={(reason) =>
                            api(
                              "/platform/teams/" +
                                selected.id +
                                "/remove-member",
                              token,
                              "POST",
                              { accountId: m.id, reason },
                            )
                          }
                          onDone={done}
                        />
                      )}
                    </div>
                  ))}
                </>
              )}
              {resource === "posts" && (
                <>
                  <h3>申请记录</h3>
                  {related.length === 0 ? (
                    <Empty description="暂无申请" />
                  ) : (
                    related.map((a) => (
                      <div className="application-row" key={a.id}>
                        <span>
                          {a.applicant_id} · {display(a.status)}
                        </span>
                        <ReasonAction
                          title="调阅会话"
                          description="仅限处理投诉或纠纷。原因和本次调阅会被记录；不会改变用户已读状态。"
                          run={async (reason) => {
                            const result = await api<Row>(
                              "/platform/applications/" + a.id + "/inspect",
                              token,
                              "POST",
                              { reason },
                            );
                            setConversation(result);
                          }}
                          onDone={() => {}}
                        />
                      </div>
                    ))
                  )}
                </>
              )}
              {resource !== "posts" && related.length > 0 && (
                <>
                  <h3>操作历史</h3>
                  {related.map((a) => (
                    <details className="audit-entry" key={a.id}>
                      <summary>
                        {new Date(a.created_at).toLocaleString()} · {a.action} ·{" "}
                        {a.reason}
                      </summary>
                      <RecordDetails row={a} />
                    </details>
                  ))}
                </>
              )}
            </>
          ))}
      </Drawer>
      <Drawer
        size={600}
        open={!!conversation}
        onClose={() => setConversation(null)}
        title="会话调阅（已记录日志）"
      >
        {conversation && (
          <>
            <p className="muted">申请：{conversation.application.id}</p>
            <div className="message">
              <strong>申请说明</strong>
              <p className="preserve">{conversation.application.message}</p>
            </div>
            {conversation.messages.map((m: Row) => (
              <div key={m.id} className="message">
                <strong>{m.sender_name}</strong>
                <small>{new Date(m.created_at).toLocaleString()}</small>
                <p className="preserve">{m.body}</p>
              </div>
            ))}
          </>
        )}
      </Drawer>
    </div>
  );
}
createRoot(document.getElementById("root")!).render(
  <React.StrictMode>
    <ConfigProvider
      locale={zhCN}
      theme={{
        token: {
          colorPrimary: "#285de5",
          colorText: "#202633",
          colorBgLayout: "#f5f6fa",
          borderRadius: 10,
          fontFamily:
            '-apple-system,BlinkMacSystemFont,"PingFang SC","Microsoft YaHei",sans-serif',
          controlHeight: 40,
        },
        components: {
          Menu: { itemSelectedBg: "#edf2ff", itemHeight: 44 },
          Table: { headerBg: "#f7f8fb" },
          Button: { primaryShadow: "none" },
        },
      }}
    >
      <AntApp>
        <PlatformApp />
      </AntApp>
    </ConfigProvider>
  </React.StrictMode>,
);
