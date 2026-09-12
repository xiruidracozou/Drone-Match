import SwiftUI

struct DiscoveryView: View {
  @Environment(\.dynamicTypeSize) private var typeSize
  @EnvironmentObject private var store: AppStore
  @State private var posts: [CommunityPost] = []
  @State private var teams: [PublicTeam] = []
  @State private var organizations: [PublicOrganization] = []
  @State private var query = ""
  @State private var showCity = false
  @State private var destination: PublishedContent?
  @FocusState private var searching: Bool
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
        VStack(alignment: .leading, spacing: 20) {
          if term.isEmpty {
            ContentSyncNotice()
            let highlights = store.content.filter { $0.kind == "hero" && $0.visible(in: city) }
            if !highlights.isEmpty {
              HomeHighlights(
                items: highlights, suspended: showCity || destination != nil || searching
              ) { item in
                if item.action.type == "video" {
                  store.selectedTab = 4
                } else if item.action.type != "none" {
                  destination = item
                }
              }
            }
            LazyVGrid(
              columns: Array(
                repeating: GridItem(.flexible(), spacing: 8),
                count: typeSize.isAccessibilitySize ? 1 : 3), spacing: 12
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
            }.buttonStyle(.plain).padding(.bottom, 4)
            if store.account != nil && (store.unreadCount > 0 || pendingApplications > 0) {
              NavigationLink {
                CommunityInbox()
              } label: {
                HStack(spacing: 12) {
                  Image(systemName: "tray").foregroundStyle(Theme.accent)
                  VStack(alignment: .leading, spacing: 4) {
                    Text(store.unreadCount > 0 ? "你有新的活动留言" : "有申请等待处理").font(
                      TypeScale.body.weight(.semibold))
                    Text(store.unreadCount > 0 ? "查看申请与消息" : "\(pendingApplications) 条申请待处理").font(
                      TypeScale.caption
                    ).foregroundStyle(.secondary)
                  }
                  .frame(maxWidth: .infinity, alignment: .leading).layoutPriority(1)
                  UnreadBadge(count: store.unreadCount)
                  Image(systemName: "chevron.right").font(TypeScale.caption)
                }.padding(12).background(Theme.surface, in: RoundedRectangle(cornerRadius: 12))
              }.buttonStyle(.plain)
            }
          }
          SyncNotice()
          if let error { InlineFailure(message: error) { Task { await load() } } }
          (typeSize.isAccessibilitySize
            ? AnyLayout(VStackLayout(alignment: .leading, spacing: 8)) : AnyLayout(HStackLayout()))
          {
            SectionHeading(
              title: term.isEmpty ? (city == "全国" ? "近期赛事" : city + "赛事") : "赛事",
              subtitle: term.isEmpty ? "近期可报名 · 按比赛日期" : nil)
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
            VStack(alignment: .leading, spacing: 8) {
              Text("当地暂时没有可报名赛事").font(.subheadline).foregroundStyle(.secondary)
              Button("换个城市看看") { showCity = true }.frame(minHeight: 44)
            }
          }
          if term.isEmpty {
            ForEach(store.content.filter { $0.kind == "advert" && $0.visible(in: city) }.prefix(1))
            {
              promotion in
              HomePromotionSlot(promotion: promotion)
            }
          }
          (typeSize.isAccessibilitySize
            ? AnyLayout(VStackLayout(alignment: .leading, spacing: 8)) : AnyLayout(HStackLayout()))
          {
            SectionHeading(title: term.isEmpty ? "招募与约赛" : "社区信息")
            NavigationLink("全部") { CommunityView(kind: .recruit) }.font(TypeScale.body).frame(
              minHeight: 44)
          }
          if loading {
            ProgressView("正在加载社区").frame(maxWidth: .infinity)
          } else if visiblePosts.isEmpty && error == nil {
            VStack(alignment: .leading, spacing: 8) {
              Text("当地还没有招募与约赛").font(.subheadline).foregroundStyle(.secondary)
              NavigationLink("发布或寻找训练同伴") { CommunityView(kind: .recruit) }.font(TypeScale.body)
                .frame(minHeight: 44)
            }
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
          } else if let guide = store.content.first(where: {
            $0.id == "equipment" && $0.kind == "guide" && $0.visible(in: city)
          }) {
            SectionHeading(title: "认识这项运动")
            NavigationLink {
              EquipmentGuide()
            } label: {
              HStack(spacing: 16) {
                PublishedImage(assetId: guide.assetId).frame(width: 104, height: 88).clipped()
                  .clipShape(
                    RoundedRectangle(cornerRadius: 12))
                VStack(alignment: .leading, spacing: 8) {
                  Text(guide.title).font(TypeScale.heading)
                  Text(guide.subtitle).font(TypeScale.body).foregroundStyle(.secondary)
                }
                Spacer(minLength: 0)
              }
            }.buttonStyle(.plain)
          }
        }.padding(.horizontal, 16).padding(.top, 8).padding(.bottom, 24).frame(maxWidth: 600)
      }.frame(maxWidth: .infinity).background(Theme.background)
        .scrollDismissesKeyboard(.interactively)
        .safeAreaInset(edge: .top, spacing: 0) { header }
        .toolbar(.hidden, for: .navigationBar)
        .sheet(isPresented: $showCity) { CitySelection() }
        .navigationDestination(item: $destination) { ContentDestination(content: $0) }
        .onChange(of: query) { _, value in
          if value.count > 80 { query = String(value.prefix(80)) }
        }
        .task(id: term + "|" + city) {
          do {
            if !term.isEmpty { try await Task.sleep(for: .milliseconds(250)) }
            await load()
          } catch {}
        }.refreshable {
          await store.refreshContent(city: city)
          await store.refresh()
          await load()
        }
    }
  }
  private var pendingApplications: Int {
    store.applications.filter { $0.authorId == store.account?.id && $0.status == "pending" }.count
  }
  private var header: some View {
    VStack(spacing: 8) {
      HStack(spacing: 8) {
        Button {
          searching = false
          showCity = true
        } label: {
          HStack(spacing: 4) {
            Image(systemName: "location.fill").font(.system(size: 16))
            Text(city).font(.subheadline.weight(.semibold))
              .lineLimit(typeSize.isAccessibilitySize ? 2 : 1)
            Image(systemName: "chevron.down").font(.system(size: 12))
          }.frame(minHeight: 44).foregroundStyle(.primary)
        }.accessibilityLabel("选择位置，当前" + city)
        if typeSize.isAccessibilitySize { Spacer(minLength: 0) } else { searchBar }
        NavigationLink {
          CommunityInbox()
        } label: {
          Image(systemName: store.unreadCount > 0 ? "envelope.badge" : "envelope")
            .font(.system(size: 22)).frame(width: 44, height: 44)
        }.accessibilityLabel("申请与消息")
      }
      if typeSize.isAccessibilitySize { searchBar }
    }.padding(.horizontal, 16).padding(.vertical, 8).background(Theme.page)
  }
  private var searchBar: some View {
    HStack(spacing: 8) {
      Image(systemName: "magnifyingglass").font(.system(size: 18)).foregroundStyle(.secondary)
      TextField("搜索赛事、俱乐部", text: $query).font(.subheadline)
        .focused($searching).submitLabel(.search).onSubmit { searching = false }
        .accessibilityLabel("搜索赛事、队伍、机构、招募")
      if !query.isEmpty {
        Button {
          query = ""
          searching = false
        } label: {
          Image(systemName: "xmark.circle.fill").font(.system(size: 18))
            .foregroundStyle(.secondary).frame(width: 44, height: 44)
        }.accessibilityLabel("清除搜索")
      }
    }.padding(.leading, 12).frame(minHeight: 44)
      .background(Theme.background, in: RoundedRectangle(cornerRadius: 12))
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
  @Environment(\.dynamicTypeSize) private var typeSize
  let title, icon: String
  var body: some View {
    (typeSize.isAccessibilitySize
      ? AnyLayout(HStackLayout(spacing: 16)) : AnyLayout(VStackLayout(spacing: 6))) {
        Image(systemName: icon).font(.system(size: 22, weight: .medium)).foregroundStyle(
          Theme.accent
        )
        .frame(width: 40, height: 40).background(
          Theme.accent.opacity(0.07), in: RoundedRectangle(cornerRadius: 12))
        Text(title).font(.subheadline.weight(.medium)).foregroundStyle(.primary)
      }.frame(
        maxWidth: .infinity, minHeight: 64,
        alignment: typeSize.isAccessibilitySize ? .leading : .center
      ).contentShape(Rectangle())
  }
}
struct FeaturedTournament: View {
  let event: Tournament
  var body: some View {
    EventRow(event: event, showsMonth: true)
      .padding(.horizontal, 16)
      .background(Theme.surface, in: RoundedRectangle(cornerRadius: 14))
      .overlay(alignment: .leading) {
        RoundedRectangle(cornerRadius: 2).fill(Theme.solidAccent).frame(width: 3, height: 32)
      }
  }
}
struct EquipmentGuide: View {
  var body: some View { PublishedGuide(id: "equipment") }
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
