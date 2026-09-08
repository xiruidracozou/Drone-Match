import SwiftUI

struct DiscoveryView: View {
  @EnvironmentObject private var store: AppStore
  @State private var posts: [CommunityPost] = []
  @State private var teams: [PublicTeam] = []
  @State private var organizations: [PublicOrganization] = []
  @State private var query = ""
  @AppStorage("selectedCity") private var city = "全国"
  @State private var error: String?
  @State private var loading = true
  private var term: String { query.trimmingCharacters(in: .whitespacesAndNewlines) }
  private var events: [Tournament] {
    store.tournaments.filter {
      (city == "全国" || $0.city == city)
        && (term.isEmpty
          || ($0.title + $0.city + $0.organizerName).localizedCaseInsensitiveContains(term))
    }
    .sorted { $0.startsAt < $1.startsAt }
  }
  private var visiblePosts: [CommunityPost] {
    posts.filter {
      (city == "全国" || $0.city == city)
        && (term.isEmpty
          ? $0.isOpen : ($0.title + $0.body + $0.city).localizedCaseInsensitiveContains(term))
    }
  }
  var body: some View {
    NavigationStack {
      ScrollView {
        VStack(alignment: .leading, spacing: 24) {
          if term.isEmpty {
            LazyVGrid(
              columns: Array(repeating: GridItem(.flexible(), spacing: 8), count: 3), spacing: 16
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
                DirectoryView()
              } label: {
                ServiceShortcut(title: "俱乐部", icon: "building.2")
              }
            }.buttonStyle(.plain).padding(.vertical, 8)
            if let account = store.account {
              NavigationLink {
                CommunityInbox()
              } label: {
                HStack(spacing: 12) {
                  Image(systemName: "tray").foregroundStyle(Theme.accent)
                  VStack(alignment: .leading, spacing: 4) {
                    Text(account.name + "，查看申请进展").font(TypeScale.body.weight(.semibold))
                    Text(store.unreadCount > 0 ? "有新的留言，点此查看" : "招募、约赛与志愿活动记录").font(
                      TypeScale.caption
                    ).foregroundStyle(.secondary)
                  }
                  Spacer()
                  UnreadBadge(count: store.unreadCount)
                  Image(systemName: "chevron.right").font(TypeScale.caption)
                }.padding(16).background(Theme.surface, in: RoundedRectangle(cornerRadius: 12))
              }.buttonStyle(.plain)
            }
          }
          SyncNotice()
          if let error { InlineFailure(message: error) { Task { await load() } } }
          HStack {
            SectionHeading(
              title: term.isEmpty ? "近期可报名" : "赛事", subtitle: term.isEmpty ? "按比赛日期排列" : nil)
            Button("全部") { store.selectedTab = 0 }.font(TypeScale.body).frame(minHeight: 44)
          }
          let shown = term.isEmpty ? events.filter(\.canRegister) : events
          if let first = shown.first {
            NavigationLink {
              TournamentDetail(initial: first)
            } label: {
              FeaturedTournament(event: first)
            }.buttonStyle(.plain)
            ForEach(shown.dropFirst().prefix(term.isEmpty ? 2 : shown.count)) { event in
              NavigationLink {
                TournamentDetail(initial: event)
              } label: {
                EventRow(event: event, showsMonth: true)
              }.buttonStyle(.plain)
            }
          } else if store.isLoading {
            ProgressView("正在加载赛事").frame(maxWidth: .infinity)
          } else if store.error == nil {
            EmptyPanel(title: "暂无符合条件的赛事", detail: "切换城市或前往赛事页查看其他安排。", icon: "calendar")
          }
          HStack {
            SectionHeading(title: term.isEmpty ? "招募与约赛" : "社区信息")
            NavigationLink("全部") { CommunityView(kind: .recruit) }.font(TypeScale.body).frame(
              minHeight: 44)
          }
          if loading {
            ProgressView("正在加载社区").frame(maxWidth: .infinity)
          } else if visiblePosts.isEmpty && error == nil {
            EmptyPanel(title: "寻找一起训练的同伴", detail: "看看其他城市的招募，或发布你的训练安排。", icon: "person.2")
            NavigationLink("浏览招募与约赛") { CommunityView(kind: .recruit) }.font(TypeScale.body).frame(
              minHeight: 44)
          } else {
            ForEach(visiblePosts.prefix(term.isEmpty ? 3 : visiblePosts.count)) { post in
              NavigationLink {
                CommunityDetail(initial: post)
              } label: {
                CommunityRow(post: post)
              }.buttonStyle(.plain)
            }
          }
          if !term.isEmpty {
            SectionHeading(title: "队伍与机构")
            let foundTeams = teams.filter {
              ($0.name + $0.city + $0.organizationName).localizedCaseInsensitiveContains(term)
                && (city == "全国" || $0.city == city)
            }
            let foundOrgs = organizations.filter {
              ($0.name + $0.city).localizedCaseInsensitiveContains(term)
                && (city == "全国" || $0.city == city)
            }
            ForEach(foundTeams) { team in
              NavigationLink {
                PublicTeamDetail(team: team)
              } label: {
                HStack(spacing: 16) {
                  ClubAvatar(name: team.name)
                  VStack(alignment: .leading, spacing: 4) {
                    Text(team.name).font(TypeScale.heading)
                    Text(team.city + " · " + team.category).font(TypeScale.caption).foregroundStyle(
                      .secondary)
                  }
                  Spacer()
                  Image(systemName: "chevron.right").font(TypeScale.caption)
                }
              }.buttonStyle(.plain).padding(.vertical, 8)
            }
            ForEach(foundOrgs) { org in
              NavigationLink {
                OrganizationDetail(organization: org)
              } label: {
                Label(org.name, systemImage: "building.2").font(TypeScale.body).frame(minHeight: 44)
              }
            }
            if !loading && error == nil && foundTeams.isEmpty && foundOrgs.isEmpty {
              Text("没有匹配的队伍或机构").font(TypeScale.body).foregroundStyle(.secondary)
            }
          } else {
            SectionHeading(title: "认识这项运动")
            NavigationLink {
              EquipmentGuide()
            } label: {
              HStack(spacing: 16) {
                EquipmentPhoto().frame(width: 104, height: 88).clipped().clipShape(
                  RoundedRectangle(cornerRadius: 12))
                VStack(alignment: .leading, spacing: 8) {
                  Text("无人机足球入门").font(TypeScale.heading)
                  Text("器材、场地与参赛准备").font(TypeScale.body).foregroundStyle(.secondary)
                }
                Spacer(minLength: 0)
              }
            }.buttonStyle(.plain)
          }
        }.padding(20).frame(maxWidth: 600)
      }.frame(maxWidth: .infinity).background(Theme.background)
        .navigationTitle("无人机足球").navigationBarTitleDisplayMode(.inline)
        .searchable(text: $query, prompt: "搜索赛事、队伍、机构、招募")
        .onChange(of: query) { _, value in
          if value.count > 80 { query = String(value.prefix(80)) }
        }
        .toolbar {
          ToolbarItem(placement: .topBarLeading) {
            Menu {
              Picker("城市", selection: $city) {
                Text("全国").tag("全国")
                ForEach(
                  Array(
                    Set(
                      store.tournaments.map(\.city) + teams.map(\.city) + posts.map(\.city)
                        + (city == "全国" ? [] : [city]))
                  )
                  .sorted(), id: \.self
                ) { Text($0).tag($0) }
              }
            } label: {
              HStack(spacing: 4) {
                Image(systemName: "location")
                Text(city).lineLimit(1)
              }.font(TypeScale.body).fixedSize(horizontal: true, vertical: false)
                .accessibilityLabel("选择城市，当前" + city)
            }
          }
          ToolbarItem(placement: .topBarTrailing) {
            NavigationLink {
              CommunityInbox()
            } label: {
              Image(systemName: store.unreadCount > 0 ? "envelope.badge" : "envelope")
                .accessibilityLabel("申请与消息")
            }
          }
        }
        .task(id: term + "|" + city) {
          do {
            if !term.isEmpty { try await Task.sleep(for: .milliseconds(250)) }
            await load()
          } catch {}
        }.refreshable {
          await store.refresh()
          await load()
        }
    }
  }
  private func load() async {
    loading = true
    let key = term + "|" + city
    defer { if key == term + "|" + city { loading = false } }
    do {
      let postQuery = [
        "q": term, "city": city == "全国" ? "" : city, "active": term.isEmpty ? "true" : "false",
        "limit": term.isEmpty ? "3" : "100",
      ]
      let found: [CommunityPost] =
        term.isEmpty
        ? try await store.communityQuery("posts", query: postQuery)
        : try await store.communityPages(
          "posts", query: ["q": term, "city": city == "全国" ? "" : city])
      let foundTeams: [PublicTeam] =
        term.isEmpty ? [] : try await store.communityPages("teams", query: ["q": term])
      let foundOrganizations: [PublicOrganization] =
        term.isEmpty ? [] : try await store.communityPages("organizations", query: ["q": term])
      guard !Task.isCancelled, key == term + "|" + city else { return }
      posts = found
      teams = foundTeams
      organizations = foundOrganizations
      error = nil
    } catch is CancellationError {} catch {
      if !Task.isCancelled, key == term + "|" + city { self.error = "内容加载失败，请重试。" }
    }
  }
}
struct ServiceShortcut: View {
  let title, icon: String
  var body: some View {
    VStack(spacing: 12) {
      Image(systemName: icon).font(.system(size: 25, weight: .medium)).foregroundStyle(Theme.accent)
        .frame(height: 32)
      Text(title).font(.subheadline.weight(.medium)).foregroundStyle(.primary)
    }.frame(maxWidth: .infinity, minHeight: 72).contentShape(Rectangle())
  }
}
struct FeaturedTournament: View {
  let event: Tournament
  var body: some View {
    HStack(alignment: .top, spacing: 16) {
      VStack(alignment: .leading, spacing: 12) {
        Text(event.category + " 级赛事").font(.caption.weight(.semibold)).foregroundStyle(
          .white.opacity(0.7))
        Text(event.title).font(TypeScale.heading).fixedSize(horizontal: false, vertical: true)
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
        Text(event.dayLabel).font(TypeScale.title).monospacedDigit()
        Text(event.weekdayLabel).font(.caption)
      }.frame(width: 55).padding(.vertical, 10).background(
        .white.opacity(0.12), in: RoundedRectangle(cornerRadius: 12))
    }.foregroundStyle(.white).padding(24).frame(maxWidth: .infinity, alignment: .leading)
      .background(Theme.navy, in: RoundedRectangle(cornerRadius: 16))
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
        VStack(alignment: .leading, spacing: 16) {
          Text("认识你的第一颗飞行球").font(TypeScale.title)
          Text("无人机足球让两支队伍在网笼内协作对抗。球形保护罩包裹无人机，飞手在场外操纵，指定进攻球穿过对方球门得分。具体人数、器材和计分方式以所参加赛事的规程为准。").font(
            .body
          ).lineSpacing(6)
          Text("先确认三件事").font(TypeScale.heading)
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
    VStack(alignment: .leading, spacing: 12) {
      Label(message, systemImage: "exclamationmark.circle").font(.subheadline)
      Button("重新加载", action: retry).frame(minHeight: 44)
    }.padding(16).frame(maxWidth: .infinity, alignment: .leading).background(
      Theme.surface, in: RoundedRectangle(cornerRadius: 12))
  }
}
