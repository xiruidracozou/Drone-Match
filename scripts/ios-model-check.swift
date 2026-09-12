import Foundation

@main
struct ModelChecks {
  static func main() throws {
    let decoder = JSONDecoder()
    let publishedRaw = """
      {"id":"ad","kind":"advert","title":"测试","subtitle":"","body":"","city":"上海","assetId":"field-photo","attribution":"CC0","sourceURL":"","startsAt":null,"endsAt":"2099-01-01T00:00:00.000Z","sort":0,"action":{"type":"external","id":"","url":"https://example.com"}}
      """
    let content = try decoder.decode(PublishedContent.self, from: Data(publishedRaw.utf8))
    precondition(content.visible(in: "上海") && !content.visible(in: "杭州"))
    let pastContent = try decoder.decode(
      PublishedContent.self,
      from: Data(publishedRaw.replacingOccurrences(of: "2099", with: "2000").utf8))
    precondition(!pastContent.visible(in: "上海"), "缓存广告到期后应隐藏")
    precondition(content.externalURL != nil)
    let unsafeContent = try decoder.decode(
      PublishedContent.self,
      from: Data(
        publishedRaw.replacingOccurrences(of: "https://example.com", with: "javascript:alert(1)")
          .utf8))
    precondition(unsafeContent.externalURL == nil)

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
    let cityRows = try decoder.decode(
      [BrowseCity].self,
      from: Data(contentsOf: URL(fileURLWithPath: "apps/ios/DroneMatch/Media/Cities.json")))
    let shanghai = cityRows.first { $0.name == "上海" }!
    precondition(
      shanghai.matches("浦东新区") && shanghai.matches("shanghai") && shanghai.matches("上海市"))
    precondition(!shanghai.matches("hangzhou"))
    precondition(cityRows.filter { $0.name == "上海" }.count == 1)
    precondition(BrowseCity.normalized(" 上海市 ") == "上海")
    precondition(BrowseCity.recent("杭州", previous: ["上海", "杭州", "全国"]) == ["杭州", "上海"])
    precondition(BrowseCity.recent("全国", previous: ["杭州"]) == ["杭州"])
    let promotionData = Data(
      """
      {"id":"test","kind":"advert","title":"test","subtitle":"test","body":"","assetId":"field-photo","attribution":"CC0","sourceURL":"","sort":0,"city":"上海","startsAt":"2026-09-01T00:00:00Z","endsAt":"2026-10-01T00:00:00Z","action":{"type":"external","id":"","url":"https://example.com/event"}}
      """.utf8)
    let promotion = try decoder.decode(PublishedContent.self, from: promotionData)
    let active = ISO8601DateFormatter().date(from: "2026-09-11T00:00:00Z")!
    precondition(promotion.visible(in: "上海", at: active))
    precondition(
      promotion.visible(in: "上海", at: ISO8601DateFormatter().date(from: promotion.startsAt!)!))
    let nationwide = try decoder.decode(
      PublishedContent.self,
      from: Data(
        String(decoding: promotionData, as: UTF8.self).replacingOccurrences(of: "上海", with: "全国")
          .utf8))
    precondition(
      nationwide.visible(in: "上海", at: active) && nationwide.visible(in: "全国", at: active))
    precondition(!promotion.visible(in: "杭州", at: active))
    precondition(!promotion.visible(in: "全国", at: active))
    precondition(
      !promotion.visible(in: "上海", at: ISO8601DateFormatter().date(from: promotion.endsAt!)!))
    precondition(
      !promotion.visible(in: "上海", at: ISO8601DateFormatter().date(from: "2026-08-31T00:00:00Z")!)
    )
    let unsafe = try decoder.decode(
      PublishedContent.self,
      from: Data(
        String(decoding: promotionData, as: UTF8.self).replacingOccurrences(
          of: "https://", with: "javascript://"
        ).utf8))
    precondition(!unsafe.visible(in: "上海", at: active))
    print(
      "iOS model checks passed: registration/application boundaries, city search/history, promotion targeting and expiry"
    )

  }
}
