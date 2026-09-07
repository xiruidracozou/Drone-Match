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
    print("iOS model checks passed: expiry, open registration, capacity")
  }
}
