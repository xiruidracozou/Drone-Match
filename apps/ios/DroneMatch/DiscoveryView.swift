import SwiftUI

struct DiscoveryView: View {
  @EnvironmentObject private var store: AppStore
  @State private var posts: [CommunityPost] = []
  @State private var teams: [PublicTeam] = []
  @State private var organizations: [PublicOrganization] = []
  @State private var query = ""
  @State private var city = "全国"
  @State private var error: String?
  private var events: [Tournament] {
    store.tournaments.filter {
      (city == "全国" || $0.city == city)
        && (query.isEmpty
          || ($0.title + $0.city + $0.organizerName).localizedCaseInsensitiveContains(query))
    }
  }
  private var visiblePosts: [CommunityPost] {
    posts.filter {
      (city == "全国" || $0.city == city)
        && (query.isEmpty || ($0.title + $0.body + $0.city).localizedCaseInsensitiveContains(query))
    }
  }
  var body: some View {
    NavigationStack {
      ScrollView {
        VStack(spacing: 22) {
          VStack(alignment: .leading, spacing: 20) {
            HStack {
              VStack(alignment: .leading, spacing: 4) {
                Text("无人机足球").font(.title2.weight(.heavy))
                Text("发现同伴，奔赴下一场").font(.subheadline).foregroundStyle(.white.opacity(0.82))
              }
              Spacer()
              Menu {
                Picker("城市", selection: $city) {
                  Text("全国").tag("全国")
                  ForEach(
                    Array(Set(store.tournaments.map(\.city) + posts.map(\.city))).sorted(),
                    id: \.self
                  ) { Text($0).tag($0) }
                }
              } label: {
                Label(city, systemImage: "location").font(.subheadline.weight(.medium)).frame(
                  minHeight: 44)
              }
            }
            HStack(spacing: 10) {
              Image(systemName: "magnifyingglass")
              TextField("搜索赛事、队伍、机构或招募", text: $query).submitLabel(.search)
              if !query.isEmpty {
                Button {
                  query = ""
                } label: {
                  Image(systemName: "xmark.circle.fill").frame(width: 44, height: 44)
                }.accessibilityLabel("清除搜索")
              }
            }.font(.subheadline).padding(.horizontal, 14).frame(minHeight: 48)
              .background(.white.opacity(0.16), in: RoundedRectangle(cornerRadius: 12))
          }.foregroundStyle(.white).padding(.horizontal, 20).padding(.top, 16).padding(.bottom, 26)
            .background(Theme.accent.gradient)
          if query.isEmpty {
            LazyVGrid(
              columns: Array(repeating: GridItem(.flexible(), spacing: 10), count: 3), spacing: 22
            ) {
              ForEach(PostKind.allCases) { kind in
                NavigationLink {
                  CommunityView(kind: kind)
                } label: {
                  ServiceShortcut(title: kind.title, icon: kind.icon)
                }
              }
              NavigationLink {
                TeamsView()
              } label: {
                ServiceShortcut(title: "我的队伍", icon: "person.3.sequence")
              }
              NavigationLink {
                CommunityInbox()
              } label: {
                ServiceShortcut(title: "申请中心", icon: "tray")
              }
            }.buttonStyle(.plain).padding(.horizontal, 20)
          }
          VStack(alignment: .leading, spacing: 18) {
            SyncNotice()
            if let error { InlineFailure(message: error) { Task { await load() } } }
            HStack {
              Text(query.isEmpty ? "值得参加" : "赛事结果").font(.title3.weight(.bold))
              Spacer()
              Button("全部赛事") { store.selectedTab = 0 }.font(.subheadline)
            }
            if query.isEmpty, let event = events.first {
              NavigationLink {
                TournamentDetail(initial: event)
              } label: {
                FeaturedTournament(event: event)
              }.buttonStyle(.plain)
              ForEach(events.dropFirst().prefix(2)) { event in
                NavigationLink {
                  TournamentDetail(initial: event)
                } label: {
                  EventRow(event: event)
                }.buttonStyle(.plain)
              }
            } else {
              ForEach(events) { event in
                NavigationLink {
                  TournamentDetail(initial: event)
                } label: {
                  EventRow(event: event)
                }.buttonStyle(.plain)
              }
            }
            HStack {
              Text(query.isEmpty ? "和同伴一起飞" : "社区结果").font(.title3.weight(.bold))
              Spacer()
              NavigationLink("查看全部") { CommunityView(kind: .recruit) }.font(.subheadline)
            }.padding(.top, 4)
            if visiblePosts.isEmpty {
              VStack(alignment: .leading, spacing: 10) {
                Text(query.isEmpty ? "把下一次训练约起来" : "没有匹配的社区信息").font(.headline)
                Text("发布招募、找队意向或训练约赛，与其他飞手建立联系。").font(.subheadline).foregroundStyle(.secondary)
                NavigationLink("发布训练约赛") { CommunityView(kind: .friendly) }.font(
                  .subheadline.weight(.semibold)
                ).frame(minHeight: 44)
              }.padding(18).frame(maxWidth: .infinity, alignment: .leading).background(
                Theme.surface, in: RoundedRectangle(cornerRadius: 16))
            } else {
              ForEach(visiblePosts.prefix(query.isEmpty ? 3 : 100)) { post in
                NavigationLink {
                  CommunityDetail(initial: post)
                } label: {
                  CommunityRow(post: post)
                }.buttonStyle(.plain)
              }
            }
            if !query.isEmpty {
              Text("队伍与机构").font(.title3.bold())
              ForEach(
                teams.filter {
                  ($0.name + $0.city).localizedCaseInsensitiveContains(query)
                    && (city == "全国" || $0.city == city)
                }
              ) { team in
                NavigationLink {
                  PublicTeamDetail(team: team)
                } label: {
                  HStack {
                    ClubAvatar(name: team.name)
                    VStack(alignment: .leading, spacing: 6) {
                      Text(team.name).font(.headline)
                      Text(team.city + " · " + team.category).font(.caption).foregroundStyle(
                        .secondary)
                    }
                    Spacer()
                    Image(systemName: "chevron.right").font(.caption)
                  }.padding(14).background(Theme.surface, in: RoundedRectangle(cornerRadius: 14))
                }.buttonStyle(.plain)
              }
              ForEach(
                organizations.filter {
                  ($0.name + $0.city).localizedCaseInsensitiveContains(query)
                    && (city == "全国" || $0.city == city)
                }
              ) { organization in
                NavigationLink {
                  OrganizationDetail(organization: organization)
                } label: {
                  Label(organization.name, systemImage: "building.2").font(.subheadline).frame(
                    maxWidth: .infinity, minHeight: 48, alignment: .leading)
                }
              }
            }
            if query.isEmpty {
              NavigationLink {
                DirectoryView()
              } label: {
                HStack {
                  Label("发现队伍与俱乐部", systemImage: "building.2")
                  Spacer()
                  Image(systemName: "chevron.right")
                }.font(.subheadline.weight(.semibold)).padding(18).background(
                  Theme.surface, in: RoundedRectangle(cornerRadius: 14))
              }
              Text("初识无人机足球").font(.title3.weight(.bold)).padding(.top, 4)
              NavigationLink {
                EquipmentGuide()
              } label: {
                VStack(alignment: .leading, spacing: 0) {
                  EquipmentPhoto().frame(height: 170).clipped()
                  VStack(alignment: .leading, spacing: 8) {
                    Text("从一颗飞行球开始").font(.headline)
                    Text("认识球体、队伍与比赛，准备第一次训练。").font(.subheadline).foregroundStyle(.secondary)
                  }.padding(18)
                }.background(Theme.surface, in: RoundedRectangle(cornerRadius: 18)).clipShape(
                  RoundedRectangle(cornerRadius: 18))
              }.buttonStyle(.plain)
            }
          }.padding(.horizontal, 20).padding(.bottom, 24)
        }
      }.background(Theme.background).toolbar(.hidden, for: .navigationBar)
        .scrollDismissesKeyboard(.interactively).task { await load() }
        .refreshable {
          await store.refresh()
          await load()
        }
    }
  }
  private func load() async {
    do {
      posts = try await store.communityRequest("posts")
      teams = try await store.communityRequest("teams")
      organizations = try await store.communityRequest("organizations")
      error = nil
    } catch { self.error = "社区信息加载失败，请重试。" }
  }
}
struct ServiceShortcut: View {
  let title, icon: String
  var body: some View {
    VStack(spacing: 10) {
      Image(systemName: icon).font(.system(size: 25, weight: .medium)).foregroundStyle(Theme.accent)
        .frame(height: 32)
      Text(title).font(.subheadline.weight(.medium)).foregroundStyle(.primary)
    }.frame(maxWidth: .infinity, minHeight: 72).contentShape(Rectangle())
  }
}
struct FeaturedTournament: View {
  let event: Tournament
  var body: some View {
    HStack(alignment: .top, spacing: 18) {
      VStack(alignment: .leading, spacing: 13) {
        Text(event.category + " 级赛事").font(.caption.weight(.semibold)).foregroundStyle(
          .white.opacity(0.7))
        Text(event.title).font(.title3.weight(.bold)).fixedSize(horizontal: false, vertical: true)
        Text(event.city + " · " + event.venue).font(.subheadline).foregroundStyle(
          .white.opacity(0.8))
        HStack {
          Text(event.statusLabel).font(.caption.weight(.semibold))
          Spacer()
          Image(systemName: "arrow.right").font(.subheadline)
        }.padding(.top, 6)
      }
      VStack(spacing: 3) {
        Text(event.monthLabel).font(.caption)
        Text(event.dayLabel).font(.system(size: 34, weight: .bold, design: .rounded))
        Text(event.weekdayLabel).font(.caption)
      }.frame(width: 55).padding(.vertical, 10).background(
        .white.opacity(0.12), in: RoundedRectangle(cornerRadius: 12))
    }.foregroundStyle(.white).padding(22).frame(maxWidth: .infinity, alignment: .leading)
      .background(Theme.navy, in: RoundedRectangle(cornerRadius: 18))
  }
}
struct EquipmentPhoto: View {
  var body: some View {
    if let path = Bundle.main.url(
      forResource: "DroneSoccer", withExtension: "jpg", subdirectory: "Media"),
      let image = UIImage(contentsOfFile: path.path)
    {
      Image(uiImage: image).resizable().scaledToFill().accessibilityLabel("真实的不同尺寸无人机足球设备")
    }
  }
}
struct EquipmentGuide: View {
  var body: some View {
    ScrollView {
      VStack(alignment: .leading, spacing: 24) {
        EquipmentPhoto().frame(height: 240).clipped()
        VStack(alignment: .leading, spacing: 18) {
          Text("认识你的第一颗飞行球").font(.title.bold())
          Text("无人机足球让两支队伍在网笼内协作对抗。球形保护罩包裹无人机，飞手在场外操纵，指定进攻球穿过对方球门得分。具体人数、器材和计分方式以所参加赛事的规程为准。").font(
            .body
          ).lineSpacing(6)
          Text("先确认三件事").font(.title3.bold())
          Label("赛事要求的设备级别", systemImage: "checkmark.circle")
          Label("适合训练的封闭场地", systemImage: "checkmark.circle")
          Label("队伍名单与现场组织方式", systemImage: "checkmark.circle")
          NavigationLink("查看参赛准备流程") { ParticipationGuide() }.frame(minHeight: 44)
          Link(
            "查看 FAI 无人机足球介绍",
            destination: URL(
              string: "https://www.fai.org/event/2026-fai-drone-soccer-international-series")!)
          Text("图片：A7N8X / Wikimedia Commons，CC0。设备实拍，非本平台赛事现场。").font(.caption).foregroundStyle(
            .secondary)
          Link(
            "图片来源与许可",
            destination: URL(
              string: "https://commons.wikimedia.org/wiki/File:Drone_soccer_in_diverse_taglie.jpg")!
          ).font(.caption)
        }.padding(.horizontal, 20)
      }.padding(.bottom, 30)
    }.navigationTitle("入门指南").navigationBarTitleDisplayMode(.inline)
  }
}
struct InlineFailure: View {
  let message: String
  let retry: () -> Void
  var body: some View {
    VStack(alignment: .leading, spacing: 10) {
      Label(message, systemImage: "exclamationmark.circle").font(.subheadline)
      Button("重新加载", action: retry).frame(minHeight: 44)
    }.padding(16).frame(maxWidth: .infinity, alignment: .leading).background(
      Theme.surface, in: RoundedRectangle(cornerRadius: 12))
  }
}
