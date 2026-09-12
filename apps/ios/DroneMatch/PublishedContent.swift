import Foundation

struct PublishedContent: Codable, Identifiable, Hashable {
  struct Action: Codable, Hashable { let type, id, url: String }
  let id, kind, title, subtitle, body, city, assetId, attribution, sourceURL: String
  let startsAt, endsAt: String?
  let sort: Int
  let action: Action
  func visible(in city: String, at now: Date = Date()) -> Bool {
    guard self.city == "全国" || self.city == city else { return false }
    if kind == "advert" || kind == "video", externalURL == nil { return false }
    if let startsAt {
      guard let date = Tournament.dateFrom(startsAt) ?? ISO8601DateFormatter().date(from: startsAt),
        date <= now
      else { return false }
    }
    if let endsAt {
      guard let date = Tournament.dateFrom(endsAt) ?? ISO8601DateFormatter().date(from: endsAt),
        now < date
      else { return false }
    }
    return true
  }
  var externalURL: URL? {
    guard let url = URL(string: action.url), url.scheme == "https", url.host != nil else {
      return nil
    }
    return url
  }
}
