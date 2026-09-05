import Foundation
import SwiftUI

@MainActor
final class AppStore: ObservableObject {
    @Published var tournaments: [Tournament] = []
    @Published var teams: [Team] = []
    @Published var registrations: [Registration] = []
    @Published var account: Account?
    @Published var isLoading = false
    @Published var error: String?
    @Published var selectedTab = 0
    @Published var showLogin = false
    private let api = APIClient()
    private var token = SessionStorage.read()
    private var identityVersion = 0
    private var refreshVersion = 0

    func refresh() async {
        refreshVersion += 1
        let currentRefresh = refreshVersion
        isLoading = true
        let version = identityVersion
        let currentToken = token
        defer { if currentRefresh == refreshVersion { isLoading = false } }
        do {
            let rows: [Tournament] = try await api.request("tournaments")
            guard version == identityVersion && currentRefresh == refreshVersion else { return }
            tournaments = rows
            if let currentToken {
                let me: Account = try await api.request("me", token: currentToken)
                let ownTeams: [Team] = try await api.request("teams", token: currentToken)
                let entries: [Registration] = try await api.request("registrations", token: currentToken)
                guard version == identityVersion && currentRefresh == refreshVersion else { return }
                account = me
                teams = ownTeams
                registrations = entries
            }
            error = nil
        } catch {
            guard version == identityVersion && currentRefresh == refreshVersion else { return }
            handle(error)
        }
    }
    func demoAccounts() async throws -> [Account] {
        let rows: [Account] = try await api.request("dev/accounts")
        return rows.filter { $0.role == "captain" }
    }
    func login(_ accountID: String) async throws {
        let session: SessionResponse = try await api.request("dev/sessions", method:"POST", body:JSONEncoder().encode(LoginRequest(accountId:accountID)))
        try SessionStorage.save(session.token)
        identityVersion += 1
        token = session.token
        account = session.account
        teams = []
        registrations = []
        showLogin = false
        await refresh()
    }
    func logout() async throws {
        if let token {
            do { let _: OKResponse = try await api.request("auth/session",token:token,method:"DELETE") }
            catch let error as APIError where error.status == 401 { }
        }
        clearSession()
    }
    private func clearSession() {
        identityVersion += 1
        token = nil
        account = nil
        teams = []
        registrations = []
        SessionStorage.clear()
    }
    func submit(tournamentID: String, teamID: String) async throws -> Registration {
        guard let token else { throw APIError(status:401,message:"请先选择演示账号") }
        let result: Registration = try await api.request("tournaments/\(tournamentID)/registrations",token:token,method:"POST",body:JSONEncoder().encode(SubmitRegistration(teamId:teamID)))
        await refresh()
        return result
    }
    func createTeam(_ value: CreateTeam) async throws {
        guard let token else { throw APIError(status:401,message:"请先登录") }
        let _: Team = try await api.request("teams",token:token,method:"POST",body:JSONEncoder().encode(value))
        await refresh()
    }
    func handle(_ error: Error) {
        if let apiError = error as? APIError, apiError.status == 401 { clearSession() }
        if (error as? URLError)?.code == .cancelled { return }
        self.error = error is URLError ? "暂时无法连接服务，请检查网络后重试。" : error.localizedDescription
    }
}
