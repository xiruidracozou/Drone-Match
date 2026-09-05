export interface Account {
  id: string;
  name: string;
  role: "organizer" | "captain";
  organizationId: string;
  organizationName: string;
}
export interface Tournament {
  id: string;
  title: string;
  city: string;
  venue: string;
  category: string;
  startsAt: string;
  deadline: string;
  capacity: number;
  approved: number;
  description: string;
  rules: string;
  status: string;
  organizerName: string;
  organizationId: string;
}
export interface Team {
  id: string;
  name: string;
  city: string;
  category: string;
  roster: string[];
}
export interface Registration {
  id: string;
  tournamentId: string;
  teamId: string;
  teamName: string;
  tournamentTitle: string;
  roster: string[];
  status: "pending" | "approved" | "rejected";
  reviewNote: string;
  version: number;
  createdAt: string;
  city: string;
  category: string;
}
export class APIError extends Error {
  constructor(
    message: string,
    readonly status: number,
  ) {
    super(message);
  }
}
export async function api<T>(
  path: string,
  token = "",
  method = "GET",
  body?: unknown,
): Promise<T> {
  const response = await fetch("/api/v1" + path, {
    method,
    headers: {
      "Content-Type": "application/json",
      ...(token ? { Authorization: `Bearer ${token}` } : {}),
    },
    ...(body ? { body: JSON.stringify(body) } : {}),
  });
  const data = await response.json();
  if (!response.ok) {
    const fields = data.fieldErrors?.fieldErrors;
    const details = fields ? Object.values(fields).flat().join("；") : "";
    throw new APIError(
      details || data.message || "请求失败，请稍后重试",
      response.status,
    );
  }
  return data;
}
export const date = (value: string) =>
  new Intl.DateTimeFormat("zh-CN", {
    month: "2-digit",
    day: "2-digit",
    hour: "2-digit",
    minute: "2-digit",
    hour12: false,
  }).format(new Date(value));
export const statusText = {
  pending: "待审核",
  approved: "已通过",
  rejected: "未通过",
};
