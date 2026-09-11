import SwiftUI

struct PublicTeam: Codable, Identifiable, Hashable {
  let id, name, city, category, organizationId, organizationName: String
  let rosterCount, memberCount: Int
}
struct PublicOrganization: Codable, Identifiable, Hashable {
  let id, name, city: String
  let teamCount: Int
}
struct DirectoryView: View {
  @AppStorage("selectedCity") private var city = "全国"
  @State private var showCity = false
  @EnvironmentObject private var store: AppStore
  @State private var teams: [PublicTeam] = []
  @State private var organizations: [PublicOrganization] = []
  @State private var query = ""
  @State private var kind = "队伍"
  @State private var loading = true
  @State private var error: String?
  private var matchingTeams: [PublicTeam] {
    teams.filter {
      (city == "全国" || $0.city == city)
        && (query.isEmpty
          || ($0.name + $0.city + $0.organizationName).localizedCaseInsensitiveContains(query))
    }
  }
  private var matchingOrganizations: [PublicOrganization] {
    organizations.filter {
      (city == "全国" || $0.city == city)
        && (query.isEmpty
          || ($0.name + $0.city).localizedCaseInsensitiveContains(query))
    }
  }
  var body: some View {
    List {
      Section {
        Button {
          showCity = true
        } label: {
          Label(city + " · 选择位置", systemImage: "location")
        }.frame(minHeight: 44)
      }
      Section {
        Picker("目录类型", selection: $kind) {
          Text("队伍").tag("队伍")
          Text("机构").tag("机构")
        }.pickerStyle(.segmented)
      }
      if let error { Section { InlineFailure(message: error) { Task { await load() } } } }
      if loading { ProgressView("正在加载目录") }
      if !loading && error == nil {
        let noTeams = matchingTeams.isEmpty
        let noOrgs = matchingOrganizations.isEmpty
        if kind == "队伍" ? noTeams : noOrgs {
          EmptyPanel(title: "没有匹配的\(kind)", detail: "换一个名称或城市试试。", icon: "magnifyingglass")
        }
      }
      if kind == "队伍" {
        ForEach(matchingTeams) { team in
          NavigationLink {
            PublicTeamDetail(team: team)
          } label: {
            HStack(spacing: 16) {
              ClubAvatar(name: team.name)
              VStack(alignment: .leading, spacing: 8) {
                Text(team.name).font(.headline)
                Text(team.city + " · " + team.category).font(.subheadline).foregroundStyle(
                  .secondary)
                Text(team.organizationName).font(.caption).foregroundStyle(.secondary)
              }
            }.padding(.vertical, 8)
          }
        }
      } else {
        ForEach(matchingOrganizations) { organization in
          NavigationLink {
            OrganizationDetail(organization: organization)
          } label: {
            VStack(alignment: .leading, spacing: 8) {
              Text(organization.name).font(.headline)
              Text(organization.city + " · \(organization.teamCount) 支队伍").font(.subheadline)
                .foregroundStyle(.secondary)
            }.padding(.vertical, 10)
          }
        }
      }
    }.navigationTitle("队伍与机构").searchable(text: $query, prompt: "搜索名称或城市").task(id: city) {
      await load()
    }
    .refreshable { await load() }
    .sheet(isPresented: $showCity) { CitySelection() }
  }
  private func load() async {
    let requestedCity = city
    loading = true
    defer { if requestedCity == city { loading = false } }
    do {
      let foundTeams: [PublicTeam] = try await store.communityPages(
        "teams")
      let foundOrganizations: [PublicOrganization] = try await store.communityPages(
        "organizations")
      guard !Task.isCancelled, requestedCity == city else { return }
      teams = foundTeams.filter { requestedCity == "全国" || $0.city == requestedCity }
      organizations = foundOrganizations.filter {
        requestedCity == "全国" || $0.city == requestedCity
      }
      error = nil
    } catch {
      if !Task.isCancelled && requestedCity == city { self.error = "目录加载失败，请重试。" }
    }
  }
}
struct PublicTeamDetail: View {
  @EnvironmentObject private var store: AppStore
  let team: PublicTeam
  @State private var posts: [CommunityPost] = []
  @State private var error: String?
  var body: some View {
    ScrollView {
      VStack(alignment: .leading, spacing: 24) {
        HStack(spacing: 16) {
          ClubAvatar(name: team.name, size: 64)
          VStack(alignment: .leading, spacing: 8) {
            Text(team.name).font(TypeScale.title)
            Text(team.city + " · " + team.category + " 级").font(.subheadline).foregroundStyle(
              .secondary)
          }
        }
        LabeledContent("所属机构", value: team.organizationName).font(.subheadline)
        HStack {
          Label("\(team.rosterCount) 人报名名单", systemImage: "person.3")
          Spacer()
          Text("\(team.memberCount) 位社区成员")
        }.font(.caption).foregroundStyle(.secondary)
        Divider()
        Text("队伍动态").font(TypeScale.heading)
        if let error { InlineFailure(message: error) { Task { await load() } } }
        if posts.isEmpty && error == nil {
          Text("队伍暂未发布招募或训练约赛。").font(.subheadline).foregroundStyle(.secondary)
        }
        ForEach(posts) { post in
          NavigationLink {
            CommunityDetail(initial: post)
          } label: {
            CommunityRow(post: post)
          }.buttonStyle(.plain)
        }
      }.padding(20)
    }.background(Theme.background).navigationTitle("队伍主页").navigationBarTitleDisplayMode(.inline)
      .task { await load() }.refreshable { await load() }
  }
  private func load() async {
    do {
      let all: [CommunityPost] = try await store.communityPages("posts", query: ["teamId": team.id])
      posts = all.filter { $0.teamId == team.id }
      error = nil
    } catch { self.error = "队伍动态加载失败。" }
  }
}
struct OrganizationDetail: View {
  @EnvironmentObject private var store: AppStore
  let organization: PublicOrganization
  @State private var teams: [PublicTeam] = []
  @State private var error: String?
  var body: some View {
    List {
      Section {
        Text(organization.name).font(TypeScale.title).padding(.vertical, 12)
        Label(organization.city, systemImage: "mappin.and.ellipse")
      }
      if let error { Section { InlineFailure(message: error) { Task { await load() } } } }
      Section("公开队伍") {
        ForEach(teams) { team in
          NavigationLink {
            PublicTeamDetail(team: team)
          } label: {
            HStack {
              ClubAvatar(name: team.name)
              Text(team.name)
              Spacer()
              Text(team.category).font(.caption).foregroundStyle(.secondary)
            }
          }
        }
      }
      Section("举办赛事") {
        ForEach(store.tournaments.filter { $0.organizationId == organization.id }) { event in
          NavigationLink {
            TournamentDetail(initial: event)
          } label: {
            EventRow(event: event)
          }
        }
      }
    }.navigationTitle("机构主页").navigationBarTitleDisplayMode(.inline).task { await load() }
      .refreshable { await load() }
  }
  private func load() async {
    do {
      let all: [PublicTeam] = try await store.communityPages(
        "teams", query: ["organizationId": organization.id])
      teams = all.filter { $0.organizationId == organization.id }
      error = nil
    } catch { self.error = "机构队伍加载失败。" }
  }
}
