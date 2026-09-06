import Foundation

struct Tournament: Codable, Identifiable, Hashable {
  let id, title, city, venue, category, startsAt, deadline, description, rules, status,
    organizerName, organizationId: String
  let capacity, approved: Int
  var canRegister: Bool { status == "open" && approved < capacity }
  var date: Date? {
    let formatter = ISO8601DateFormatter()
    formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
    return formatter.date(from: startsAt)
  }
  var monthLabel: String {
    date.map { $0.formatted(.dateTime.month(.abbreviated).locale(Locale(identifier: "zh_CN"))) }
      ?? "待定"
  }
  var dayLabel: String { date.map { String(Calendar.current.component(.day, from: $0)) } ?? "—" }
  var monthKey: String { String(startsAt.prefix(7)) }
  var monthTitle: String {
    date.map { $0.formatted(.dateTime.year().month(.wide).locale(Locale(identifier: "zh_CN"))) }
      ?? "时间待定"
  }
  var weekdayLabel: String {
    date.map { $0.formatted(.dateTime.weekday(.abbreviated).locale(Locale(identifier: "zh_CN"))) }
      ?? ""
  }
  var statusLabel: String { canRegister ? "报名中" : status == "closed" ? "报名截止" : "名额已满" }
  var dateLabel: String { Self.formatDate(startsAt) }
  static func formatDate(_ value: String) -> String {
    let formatter = ISO8601DateFormatter()
    formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
    guard let date = formatter.date(from: value) else { return value }
    return date.formatted(
      .dateTime.month(.twoDigits).day(.twoDigits).hour().minute().locale(
        Locale(identifier: "zh_CN")))
  }
}
struct Account: Codable, Identifiable {
  let id, name, role, organizationId, organizationName: String
}
struct Team: Codable, Identifiable, Hashable {
  let id, name, city, category: String
  let roster: [String]
}
struct Registration: Codable, Identifiable, Hashable {
  let id, tournamentId, teamId, teamName, tournamentTitle, status, reviewNote, createdAt, city,
    category: String
  let roster: [String]
  let version: Int
  var statusLabel: String {
    ["pending": "待审核", "approved": "已通过", "rejected": "未通过"][status] ?? status
  }
}
struct SessionResponse: Codable {
  let token: String
  let account: Account
}
struct SubmitRegistration: Encodable {
  let teamId: String
  let acceptRules = true
}
struct CreateTeam: Encodable {
  let name, city, category: String
  let roster: [String]
  let adultOnly = true
}
struct LoginRequest: Encodable { let accountId: String }
struct APIMessage: Decodable { let message: String? }
struct OKResponse: Decodable { let ok: Bool }
