import React, { useEffect, useState } from "react";
import {
  Alert,
  Button,
  Form,
  Input,
  InputNumber,
  Select,
  DatePicker,
  Space,
  Upload,
} from "antd";
import dayjs from "dayjs";
import { api } from "./api";
import { Row, kinds } from "./platform-model";
export function ContentPreview({ data, kind }: { data: Row; kind: string }) {
  return (
    <article
      className={"content-preview " + (kind === "hero" ? "preview-hero" : "")}
    >
      {data.assetId && (
        <img
          src={"/api/v1/content/assets/" + encodeURIComponent(data.assetId)}
          alt="内容预览"
        />
      )}
      <div>
        <small>{kind === "advert" ? "广告" : data.attribution}</small>
        <h2>{data.title || "标题预览"}</h2>
        <p>{data.subtitle}</p>
        <div className="preserve">{data.body}</div>
        {data.action?.type === "external" && (
          <p className="muted">外部链接：{data.action.url}</p>
        )}
      </div>
    </article>
  );
}
export function ContentEditor({
  row,
  token,
  onDone,
}: {
  row: Row;
  token: string;
  onDone: () => void;
}) {
  const [form] = Form.useForm();
  const [assets, setAssets] = useState<Row[]>([]),
    [error, setError] = useState(""),
    [busy, setBusy] = useState(false),
    [license, setLicense] = useState("");
  const current = Form.useWatch([], form) || {};
  useEffect(() => {
    const d = row.draft || {};
    form.setFieldsValue({
      kind: row.kind || "hero",
      ...d,
      city: d.city || "全国",
      sort: d.sort || 0,
      startsAt: d.startsAt ? dayjs(d.startsAt) : null,
      endsAt: d.endsAt ? dayjs(d.endsAt) : null,
      actionType: d.action?.type || "none",
      target: d.action?.id || "",
      url: d.action?.url || "",
    });
    api<Row[]>("/platform/assets", token)
      .then(setAssets)
      .catch((e) => setError(e.message));
  }, [row, token]);
  async function save(v: Row) {
    setBusy(true);
    setError("");
    const data = {
      title: v.title,
      subtitle: v.subtitle || "",
      body: v.body || "",
      city: v.city || "全国",
      sort: v.sort || 0,
      startsAt: v.startsAt?.toISOString() || null,
      endsAt: v.endsAt?.toISOString() || null,
      assetId: v.assetId || "",
      attribution: v.attribution || "",
      action: { type: v.actionType, id: v.target || "", url: v.url || "" },
      sourceURL: v.sourceURL || "",
    };
    try {
      await api(
        "/platform/content" + (row.id ? "/" + row.id : ""),
        token,
        row.id ? "PUT" : "POST",
        row.id
          ? { version: row.version, reason: v.reason, operation: "save", data }
          : { kind: v.kind, reason: v.reason, data },
      );
      onDone();
    } catch (e) {
      setError((e as Error).message);
    } finally {
      setBusy(false);
    }
  }
  return (
    <>
      <Alert
        title="保存草稿不会影响移动端，返回详情核对后再发布。"
        type="info"
        showIcon
      />
      {error && <Alert title={error} type="error" />}
      <Form form={form} layout="vertical" onFinish={save} className="edit-form">
        <Form.Item name="kind" label="内容类型" rules={[{ required: true }]}>
          <Select
            disabled={!!row.id}
            options={Object.entries(kinds).map(([value, label]) => ({
              value,
              label,
            }))}
          />
        </Form.Item>
        <Form.Item
          name="title"
          label="标题"
          rules={[{ required: true, min: 2, max: 100 }]}
        >
          <Input maxLength={100} />
        </Form.Item>
        <Form.Item name="subtitle" label="副标题">
          <Input maxLength={250} />
        </Form.Item>
        <Form.Item name="body" label="正文（纯文本，支持分段）">
          <Input.TextArea rows={7} maxLength={10000} />
        </Form.Item>
        <div className="form-grid">
          <Form.Item
            name="city"
            label="展示城市"
            extra="全国，或城市名，不带市后缀。"
          >
            <Input />
          </Form.Item>
          <Form.Item name="sort" label="排序（小数值优先）">
            <InputNumber min={0} max={999} />
          </Form.Item>
          <Form.Item name="startsAt" label="开始展示">
            <DatePicker showTime />
          </Form.Item>
          <Form.Item name="endsAt" label="结束展示">
            <DatePicker showTime />
          </Form.Item>
        </div>
        <Form.Item name="assetId" label="图片">
          <Select
            allowClear
            options={assets.map((a) => ({
              value: a.id,
              label: a.attribution + " · " + a.filename,
            }))}
          />
        </Form.Item>
        <div className="upload-box">
          <Input
            placeholder="上传素材的来源与许可"
            value={license}
            onChange={(e) => setLicense(e.target.value)}
            maxLength={500}
          />
          <Upload
            accept="image/jpeg,image/png"
            showUploadList={false}
            beforeUpload={async (file) => {
              if (license.trim().length < 2) {
                setError("请先填写素材来源与许可");
                return false;
              }
              if (file.size > 10 * 1024 * 1024) {
                setError("图片上限10MB");
                return false;
              }
              setBusy(true);
              try {
                const data = await new Promise<string>((res, rej) => {
                  const reader = new FileReader();
                  reader.onload = () =>
                    res(String(reader.result).split(",")[1]);
                  reader.onerror = rej;
                  reader.readAsDataURL(file);
                });
                const asset = await api<Row>(
                  "/platform/assets",
                  token,
                  "POST",
                  {
                    data,
                    attribution: license,
                    reason: "内容运营上传素材：" + license,
                  },
                );
                setAssets((a) => [asset, ...a]);
                form.setFieldValue("assetId", asset.id);
                form.setFieldValue("attribution", license);
                setError("");
              } catch (e) {
                setError((e as Error).message);
              } finally {
                setBusy(false);
              }
              return false;
            }}
          >
            <Button loading={busy}>上传 JPEG / PNG（10MB以内）</Button>
          </Upload>
        </div>
        <Form.Item name="attribution" label="图片说明／来源署名">
          <Input maxLength={500} />
        </Form.Item>
        <Form.Item name="actionType" label="点击行为">
          <Select
            options={[
              ["none", "无跳转"],
              ["video", "视频栏目"],
              ["guide", "指南详情"],
              ["tournament", "赛事详情"],
              ["community", "社区招募"],
              ["external", "外部 HTTPS 链接"],
            ].map(([value, label]) => ({ value, label }))}
          />
        </Form.Item>
        {["guide", "tournament"].includes(current.actionType) && (
          <Form.Item
            name="target"
            label="目标内容编号"
            extra="指南可使用 equipment 或 participation；其他内容编号在列表详情中复制。"
            rules={[{ required: true }]}
          >
            <Input />
          </Form.Item>
        )}
        {current.actionType === "external" && (
          <Form.Item
            name="url"
            label="HTTPS 落地页"
            rules={[{ required: true, type: "url" }]}
          >
            <Input />
          </Form.Item>
        )}
        <Form.Item name="sourceURL" label="官方来源页（HTTPS）">
          <Input />
        </Form.Item>
        <Form.Item
          name="reason"
          label="修改原因"
          rules={[{ required: true, min: 2, max: 500 }]}
        >
          <Input.TextArea rows={2} maxLength={500} />
        </Form.Item>
        <Button type="primary" htmlType="submit" loading={busy}>
          保存草稿
        </Button>
      </Form>
      <h3>内容预览</h3>
      <ContentPreview
        data={{
          ...current,
          action: { type: current.actionType, url: current.url },
        }}
        kind={current.kind || row.kind}
      />
    </>
  );
}
