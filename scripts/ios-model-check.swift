import Foundation

@main
struct ModelChecks {
  static func main() throws {
    let decoder = JSONDecoder()
    let raw = """
      {"id":"event","title":"测试赛事","city":"上海","venue":"场馆","category":"20cm","startsAt":"2099-01-02T08:00:00.000Z","deadline":"2000-01-01T08:00:00.000Z","description":"说明","rules":"规则","status":"open","organizerName":"主办方","organizationId":"org","capacity":16,"approved":0}
      """
    let expired = try decoder.decode(Tournament.self, from: Data(raw.utf8))
    precondition(!expired.canRegister, "截止时间已过时，即使缓存状态仍为open，也必须停止报名")
    precondition(expired.statusLabel == "报名截止", "截止后的状态应明确")
    let available = try decoder.decode(
      Tournament.self,
      from: Data(raw.replacingOccurrences(of: "2000-01-01", with: "2099-01-01").utf8))
    precondition(available.canRegister)
    let full = try decoder.decode(
      Tournament.self,
      from: Data(
        raw.replacingOccurrences(of: "2000-01-01", with: "2099-01-01").replacingOccurrences(
          of: "\"approved\":0", with: "\"approved\":16"
        ).utf8))
    precondition(!full.canRegister && full.statusLabel == "名额已满")
    for kind in PostKind.allCases {
      precondition(
        ApplicationDraft(message: " \n ", teamId: "team").validationMessage(for: kind) != nil)
      precondition(
        ApplicationDraft(message: "好", teamId: "team").validationMessage(for: kind) != nil)
      precondition(
        ApplicationDraft(message: "周末可参与", teamId: "team").validationMessage(for: kind) == nil)
      precondition(
        ApplicationDraft(message: String(repeating: "好", count: 500), teamId: "team")
          .validationMessage(for: kind) == nil)
      precondition(
        ApplicationDraft(message: String(repeating: "好", count: 501), teamId: "team")
          .validationMessage(for: kind) != nil, "申请留言不能超过服务端500字符限制")
    }
    for kind in [PostKind.friendly, .seeking] {
      precondition(
        ApplicationDraft(message: "周末可参与", teamId: nil).validationMessage(for: kind) != nil)
    }
    for kind in [PostKind.recruit, .volunteer] {
      precondition(
        ApplicationDraft(message: "周末可参与", teamId: nil).validationMessage(for: kind) == nil)
    }
    precondition(
      ApplicationDraft(message: String(repeating: "🚁", count: 251), teamId: "team")
        .validationMessage(for: .recruit) != nil, "字符长度应与服务端UTF16规则一致")
    print("iOS model checks passed: registration states and application input boundaries")
  }
}
