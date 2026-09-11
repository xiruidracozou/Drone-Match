import Foundation

struct BrowseCity: Codable, Identifiable {
  let name, province: String
  let districts: [String]
  var id: String { province + name }
  func matches(_ query: String) -> Bool {
    let term = query.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !term.isEmpty else { return true }
    let text = ([name, province] + districts).joined(separator: " ")
    if text.localizedCaseInsensitiveContains(term) { return true }
    let pinyin =
      name.applyingTransform(.toLatin, reverse: false)?
      .folding(options: .diacriticInsensitive, locale: Locale(identifier: "zh_CN"))
      .replacingOccurrences(of: " ", with: "") ?? ""
    return pinyin.localizedCaseInsensitiveContains(term.replacingOccurrences(of: " ", with: ""))
  }
  static func normalized(_ name: String) -> String {
    let value = name.trimmingCharacters(in: .whitespacesAndNewlines)
    return value.hasSuffix("市") ? String(value.dropLast()) : value
  }
  static func recent(_ chosen: String, previous: [String]) -> [String] {
    Array(
      ([chosen] + previous).reduce(into: [String]()) { result, value in
        if value != "全国" && !value.isEmpty && !result.contains(value) { result.append(value) }
      }.prefix(6))
  }
  static let catalog: [BrowseCity] = {
    guard
      let url = Bundle.main.url(
        forResource: "Cities", withExtension: "json", subdirectory: "Media"),
      let data = try? Data(contentsOf: url),
      let rows = try? JSONDecoder().decode([BrowseCity].self, from: data)
    else { return [] }
    return rows.sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
  }()
}

struct HomePromotion: Codable, Identifiable {
  let id, title, subtitle, imageName, city, startsAt, endsAt: String
  let destination: URL
  func isVisible(in selectedCity: String, at now: Date) -> Bool {
    guard destination.scheme == "https", destination.host != nil,
      let start = Tournament.dateFrom(startsAt) ?? ISO8601DateFormatter().date(from: startsAt),
      let end = Tournament.dateFrom(endsAt) ?? ISO8601DateFormatter().date(from: endsAt)
    else { return false }
    return start <= now && now < end && (city == "全国" || city == selectedCity)
  }
  static let bundled: [HomePromotion] = {
    guard
      let url = Bundle.main.url(
        forResource: "HomePromotions", withExtension: "json", subdirectory: "Media"),
      let data = try? Data(contentsOf: url)
    else { return [] }
    return (try? JSONDecoder().decode([HomePromotion].self, from: data)) ?? []
  }()
}
