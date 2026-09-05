import Foundation
import Security

struct APIError: LocalizedError {
    let status: Int
    let message: String
    var errorDescription: String? { message }
}
struct APIClient {
    private let baseURL = URL(string: Bundle.main.object(forInfoDictionaryKey: "APIBaseURL") as? String ?? "http://127.0.0.1:3001/api/v1")!
    func request<T: Decodable>(_ path: String, token: String? = nil, method: String = "GET", body: Data? = nil) async throws -> T {
        var request = URLRequest(url: baseURL.appendingPathComponent(path))
        request.httpMethod = method
        request.httpBody = body
        request.timeoutInterval = 15
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        if let token { request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization") }
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse else { throw APIError(status: 0, message: "服务器响应异常") }
        guard (200..<300).contains(http.statusCode) else {
            let error = try? JSONDecoder().decode(APIMessage.self, from: data)
            throw APIError(status: http.statusCode, message: error?.message ?? "操作未完成，请稍后重试")
        }
        return try JSONDecoder().decode(T.self, from: data)
    }
}
enum SessionStorage {
    private static let query: [String: Any] = [kSecClass as String:kSecClassGenericPassword, kSecAttrService as String:"com.dronematch.local", kSecAttrAccount as String:"session"]
    static func read() -> String? {
        var request = query
        request[kSecReturnData as String] = true
        request[kSecMatchLimit as String] = kSecMatchLimitOne
        var item: CFTypeRef?
        guard SecItemCopyMatching(request as CFDictionary, &item) == errSecSuccess, let data = item as? Data else { return nil }
        return String(data: data, encoding: .utf8)
    }
    static func save(_ token: String) throws {
        clear()
        var request = query
        request[kSecValueData as String] = Data(token.utf8)
        request[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        guard SecItemAdd(request as CFDictionary, nil) == errSecSuccess else { throw APIError(status:0,message:"无法安全保存登录状态") }
    }
    static func clear() { SecItemDelete(query as CFDictionary) }
}
