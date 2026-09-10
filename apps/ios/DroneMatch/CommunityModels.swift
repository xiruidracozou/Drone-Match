import Foundation

enum PostKind: String, CaseIterable, Identifiable, Codable {
  case recruit, seeking, friendly, volunteer
  var id: String { rawValue }
  var title: String {
    switch self {
    case .recruit: "战队招募"
    case .seeking: "飞手找队"
    case .friendly: "训练约赛"
    case .volunteer: "志愿者"
    }
  }
  var icon: String {
    switch self {
    case .recruit: "person.2.badge.plus"
    case .seeking: "flag"
    case .friendly: "sportscourt"
    case .volunteer: "hands.sparkles"
    }
  }
  var action: String {
    switch self {
    case .recruit: "申请入队"
    case .seeking: "邀请入队"
    case .friendly: "申请应约"
    case .volunteer: "报名志愿者"
    }
  }
  var publish: String {
    switch self {
    case .recruit: "发布招募"
    case .seeking: "发布找队"
    case .friendly: "发起约赛"
    case .volunteer: "发布活动"
    }
  }
}
struct CommunityPost: Codable, Identifiable, Hashable {
  let id, authorId, authorName, organizationName, kind, title, city, category, level, availability,
    venue, body, status, createdAt: String
  let teamId, teamName, startsAt: String?
  let applicationCount: Int
  var type: PostKind { PostKind(rawValue: kind) ?? .recruit }
  var statusLabel: String {
    if status == "open" && !isOpen { return "已结束" }
    return ["open": "进行中", "matched": "已约定", "closed": "已关闭", "cancelled": "已取消"][status] ?? status
  }
  var isOpen: Bool {
    status == "open"
      && (startsAt.flatMap { ISO8601DateFormatter().date(from: $0) ?? Tournament.dateFrom($0) }.map
      { $0 > Date() } ?? true)
  }
}
struct CommunityApplication: Codable, Identifiable {
  let id, postId, applicantId, applicantName, message, status, createdAt, authorId, postTitle, kind,
    postStatus, city, category: String
  let teamId, teamName: String?
  let unreadCount: Int?
  var statusLabel: String {
    ["pending": "待处理", "accepted": "已接受", "rejected": "未接受", "withdrawn": "已撤回"][status] ?? status
  }
}
struct PostDraft: Encodable {
  let kind, title, city, category, level, availability, venue, body: String
  let teamId, startsAt: String?
}
struct ApplicationDraft: Encodable {
  let message: String
  let teamId: String?
  func validationMessage(for kind: PostKind) -> String? {
    let length = message.trimmingCharacters(in: .whitespacesAndNewlines).utf16.count
    if length < 2 {
      return "请填写申请留言。"
    }
    if length > 500 { return "申请留言不能超过500字符。" }
    if (kind == .friendly || kind == .seeking) && (teamId ?? "").isEmpty {
      return "请选择对应的队伍。"
    }
    return nil
  }
}
struct StateChange: Encodable { let status: String }
struct Membership: Codable, Identifiable {
  let teamId, teamName, city, category, joinedAt: String
  var id: String { teamId }
}
extension Tournament {
  static func dateFrom(_ value: String) -> Date? {
    let f = ISO8601DateFormatter()
    f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
    return f.date(from: value)
  }
}
