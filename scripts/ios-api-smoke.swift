import Foundation

private struct PublicTeamProbe: Decodable { let id, name: String }
@main
struct ClientSmoke {
  static func main() async throws {
    let client = APIClient()
    let teams: [PublicTeamProbe] = try await client.request("community/teams")
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
