import React, { useEffect, useState } from "react";
import {
  Alert,
  Button,
  Checkbox,
  DatePicker,
  Descriptions,
  Form,
  Input,
  InputNumber,
  Modal,
  Select,
  Space,
  Table,
  Tag,
} from "antd";
import dayjs from "dayjs";
import { api } from "./api";
import {
  Field,
  Row,
  labels,
  display,
  fieldsFor,
  initialValues,
} from "./platform-model";
export function RecordDetails({
  row,
  lookups = {},
}: {
  row: Row;
  lookups?: Row;
}) {
  const resolve = (k: string, v: unknown) => {
    const group =
      k === "organization_id"
        ? "organizations"
        : k === "tournament_id"
          ? "tournaments"
          : k === "team_id"
            ? "teams"
            : "";
    const record = (lookups[group] || []).find((r: Row) => r.id === v);
    return record ? record.name || record.title : display(v);
  };
  return (
    <Descriptions
      size="small"
      bordered
      column={1}
      items={Object.entries(row)
        .filter(([k]) => !["draft", "published", "password_hash"].includes(k))
        .map(([key, value]) => ({
          key,
          label: labels[key] || key,
          children: <span className="preserve">{resolve(key, value)}</span>,
        }))}
    />
  );
}
export function FieldControl({
  field,
  ...control
}: {
  field: Field;
  [key: string]: any;
}) {
  if (field.type === "area" || field.type === "roster")
    return (
      <Input.TextArea
        {...control}
        rows={4}
        maxLength={field.type === "roster" ? 1000 : 10000}
      />
    );
  if (field.type === "select")
    return (
      <Select
        {...control}
        showSearch
        optionFilterProp="label"
        options={field.options}
      />
    );
  if (field.type === "number")
    return (
      <InputNumber {...control} style={{ width: "100%" }} min={0} max={999} />
    );
  if (field.type === "date")
    return (
      <DatePicker
        {...control}
        showTime
        format="YYYY-MM-DD HH:mm"
        style={{ width: "100%" }}
      />
    );
  if (field.type === "check")
    return <Checkbox {...control}>{field.label}</Checkbox>;
  return <Input {...control} maxLength={200} />;
}
export function MutationForm({
  resource,
  row,
  lookups,
  token,
  onDone,
  onCancel,
}: {
  resource: string;
  row: Row;
  lookups: Row;
  token: string;
  onDone: () => void;
  onCancel: () => void;
}) {
  const [form] = Form.useForm();
  const [error, setError] = useState("");
  const [busy, setBusy] = useState(false);
  const [review, setReview] = useState<Row | null>(null);
  const [registrations, setRegistrations] = useState<Row[]>([]);
  const selectedTournament = Form.useWatch("tournamentId", form);
  const fields = fieldsFor(resource, lookups, registrations);
  useEffect(() => {
    const v = initialValues(resource, row);
    fieldsFor(resource, lookups).forEach((f) => {
      if (f.type === "date" && v[f.key]) v[f.key] = dayjs(v[f.key]);
    });
    form.setFieldsValue(v);
  }, [resource, row]);
  useEffect(() => {
    if (resource !== "matches" || !selectedTournament) return;
    let active = true;
    (async () => {
      const all: Row[] = [];
      let total = 1;
      while (all.length < total) {
        const data = await api<{ rows: Row[]; total: number }>(
          `/platform/registrations?parent=${encodeURIComponent(selectedTournament)}&limit=100&offset=${all.length}`,
          token,
        );
        all.push(...data.rows);
        total = data.total;
        if (!data.rows.length) break;
      }
      if (active) setRegistrations(all);
    })().catch((e) => {
      if (active) setError(e.message);
    });
    return () => {
      active = false;
    };
  }, [resource, selectedTournament, token]);
  async function submit(values: Row) {
    setError("");
    const body: Row = {};
    for (const f of fields) {
      let value = values[f.key];
      if (f.type === "date") value = value?.toISOString();
      if (f.type === "roster")
        value = String(value || "")
          .split("\n")
          .map((s) => s.trim())
          .filter(Boolean);
      if (f.type === "check") value = !!value;
      body[f.key] = value ?? (f.type === "number" ? null : "");
    }
    if (resource === "matches") {
      if (row.id) delete body.tournamentId;
      if (body.status !== "final") {
        body.homeScore = null;
        body.awayScore = null;
      }
    }
    setReview({ reason: values.reason, values: body });
  }
  async function save() {
    if (!review) return;
    setBusy(true);
    setError("");
    try {
      await api(
        `/platform/${resource}${row.id ? "/" + row.id : ""}`,
        token,
        row.id ? "PATCH" : "POST",
        { ...review, ...(row.id ? { version: row.version } : {}) },
      );
      onDone();
    } catch (e) {
      setError((e as Error).message);
      setReview(null);
    } finally {
      setBusy(false);
    }
  }
  return (
    <>
      <Alert
        title="平台代办操作"
        description="修改当前队伍名单不会更改历史报名。纠正报名或赛程将保留修改前后的记录；撤销参赛资格前需处理关联赛程。"
        type="info"
        showIcon
      />
      {error && <Alert title={error} type="error" showIcon />}
      <Form
        form={form}
        layout="vertical"
        onFinish={submit}
        className="edit-form"
      >
        {fields.map((field) => (
          <Form.Item
            key={field.key}
            name={field.key}
            label={field.type === "check" ? undefined : field.label}
            valuePropName={field.type === "check" ? "checked" : "value"}
            rules={
              field.required && field.type !== "check"
                ? [{ required: true, message: "请填写" + field.label }]
                : []
            }
          >
            <FieldControl
              field={{
                ...field,
                ...(field.key === "tournamentId" && row.id
                  ? {
                      options: field.options?.filter(
                        (o) => o.value === row.tournament_id,
                      ),
                    }
                  : {}),
              }}
            />
          </Form.Item>
        ))}
        <Form.Item
          name="reason"
          label="操作原因（写入平台日志）"
          rules={[
            {
              required: true,
              min: 2,
              max: 500,
              message: "请填写2–500字操作原因",
            },
          ]}
        >
          <Input.TextArea rows={3} maxLength={500} />
        </Form.Item>
        <Space>
          <Button onClick={onCancel}>取消</Button>
          <Button type="primary" htmlType="submit">
            核对修改
          </Button>
        </Space>
      </Form>
      <Modal
        title="确认平台代办"
        open={!!review}
        onCancel={() => !busy && setReview(null)}
        onOk={save}
        confirmLoading={busy}
        okText="确认提交"
        cancelText="返回修改"
        width={720}
      >
        <p>{review?.reason}</p>
        <Table
          size="small"
          pagination={false}
          rowKey="key"
          dataSource={Object.entries(review?.values || {}).map(
            ([key, value]) => ({
              key,
              before: initialValues(resource, row)[key],
              after: value,
            }),
          )}
          columns={[
            { title: "字段", dataIndex: "key", render: (k) => labels[k] || k },
            { title: "修改前", dataIndex: "before", render: display },
            { title: "修改后", dataIndex: "after", render: display },
          ]}
          scroll={{ x: 600 }}
        />
      </Modal>
    </>
  );
}
export function ReasonAction({
  title,
  description,
  run,
  onDone,
}: {
  title: string;
  description: string;
  run: (reason: string) => Promise<unknown>;
  onDone: () => void;
}) {
  const [open, setOpen] = useState(false),
    [reason, setReason] = useState(""),
    [busy, setBusy] = useState(false),
    [error, setError] = useState("");
  return (
    <>
      <Button onClick={() => setOpen(true)}>{title}</Button>
      <Modal
        title={title}
        open={open}
        onCancel={() => !busy && setOpen(false)}
        okText="确认操作"
        cancelText="取消"
        confirmLoading={busy}
        okButtonProps={{ disabled: reason.trim().length < 2 }}
        onOk={async () => {
          setBusy(true);
          setError("");
          try {
            await run(reason.trim());
            setOpen(false);
            onDone();
          } catch (e) {
            setError((e as Error).message);
          } finally {
            setBusy(false);
          }
        }}
      >
        <p>{description}</p>
        {error && <Alert title={error} type="error" />}
        <label>
          操作原因
          <Input.TextArea
            value={reason}
            onChange={(e) => setReason(e.target.value)}
            maxLength={500}
            rows={3}
          />
        </label>
      </Modal>
    </>
  );
}
