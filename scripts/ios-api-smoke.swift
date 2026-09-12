import Foundation

private struct PublicTeamProbe: Decodable { let id, name: String }
@main
struct ClientSmoke {
  static func main() async throws {
    let client = APIClient()
    let teams: [PublicTeamProbe] = try await client.request("community/teams")
    let content: [PublishedContent] = try await client.request("content?city=%E5%85%A8%E5%9B%BD")
    precondition(content.allSatisfy { $0.city == "全国" }, "全国请求不能混入其他城市广告")
    precondition(content.filter { $0.kind == "advert" || $0.kind == "video" }.allSatisfy { $0.externalURL != nil })
    print("Published content decoded through iOS API client: \(content.count) records")
    var query = URLComponents()
    query.queryItems = [
      URLQueryItem(name: "q", value: "不存在的查询 + & / #"), URLQueryItem(name: "offset", value: "0"),
    ]
    let filtered: [PublicTeamProbe] = try await client.request(
      "community/teams?" + query.percentEncodedQuery!)
    precondition(filtered.isEmpty, "查询参数必须发送给服务器，不能被编码成路径")
    print("iOS API client smoke passed: public directory \(teams.count), encoded query filter")
  }
}
