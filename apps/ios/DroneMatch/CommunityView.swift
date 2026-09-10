import SwiftUI

struct CommunityView: View {
  @EnvironmentObject private var store: AppStore
  @State private var selected: PostKind
  @State private var posts: [CommunityPost] = []
  @State private var query = ""
  @State private var city = "全国"
  @State private var category = "全部"
  @State private var openOnly = true
  @State private var hasMore = false
  @State private var offset = 0
  private var filterKey: String {
    selected.rawValue + "|" + query + "|" + city + "|" + category + "|" + String(openOnly)
  }
  @State private var error: String?
  @State private var loading = false
  @State private var showCompose = false
  @State private var showLogin = false
  init(kind: PostKind) { _selected = State(initialValue: kind) }
  private var filtered: [CommunityPost] {
    posts.filter {
      $0.kind == selected.rawValue && (city == "全国" || $0.city == city)
        && (category == "全部" || $0.category == category) && (!openOnly || $0.isOpen)
        && (query.isEmpty || ($0.title + $0.body).localizedCaseInsensitiveContains(query))
    }
  }
  var body: some View {
    ScrollView {
      VStack(alignment: .leading, spacing: 16) {
        ScrollView(.horizontal, showsIndicators: false) {
          HStack(spacing: 24) {
            ForEach(PostKind.allCases) { kind in
              Button {
                selected = kind
              } label: {
                VStack(spacing: 12) {
                  Text(kind.title).font(.headline)
                  Capsule().fill(selected == kind ? Theme.accent : .clear).frame(height: 3)
                }
              }.foregroundStyle(selected == kind ? Theme.accent : .secondary)
                .accessibilityAddTraits(selected == kind ? .isSelected : [])
            }
          }.padding(.top, 8)
        }
        HStack {
          Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
          TextField("搜索标题或训练要求", text: $query).submitLabel(.search)
        }.padding(16).background(Theme.surface, in: RoundedRectangle(cornerRadius: 12))
        HStack {
          Menu {
            Picker("城市", selection: $city) {
              Text("全国").tag("全国")
              ForEach(
                Array(
                  Set(
                    posts.map(\.city) + store.tournaments.map(\.city) + (city == "全国" ? [] : [city])
                  )
                ).sorted(), id: \.self
              ) { Text($0).tag($0) }
            }
          } label: {
            Label(city, systemImage: "mappin").frame(minHeight: 44)
          }
          Spacer()
          Menu {
            Picker("设备级别", selection: $category) {
              ForEach(["全部", "20cm", "40cm"], id: \.self) { Text($0).tag($0) }
            }
          } label: {
            Label(category == "全部" ? "所有级别" : category, systemImage: "slider.horizontal.3").frame(
              minHeight: 44)
          }
        }.font(.subheadline)
        Toggle("只看进行中", isOn: $openOnly).font(.subheadline)
        if let error { InlineFailure(message: error) { Task { await load() } } }
        if loading && posts.isEmpty {
          ProgressView("正在加载").frame(maxWidth: .infinity).padding(40)
        } else if filtered.isEmpty && error == nil {
          ContentUnavailableView {
            Label("还没有符合条件的信息", systemImage: selected.icon)
          } description: {
            Text("换个城市或级别，也可以先发布一条。")
          } actions: {
            Button(selected.publish) { beginCompose() }.buttonStyle(.borderedProminent).tint(
              Theme.solidAccent)
          }
        }
        ForEach(filtered) { post in
          NavigationLink {
            CommunityDetail(initial: post)
          } label: {
            CommunityRow(post: post)
          }.buttonStyle(.plain)
        }
        if hasMore {
          Button("加载更多") { Task { await load(reset: false) } }.frame(
            maxWidth: .infinity, minHeight: 44
          ).disabled(loading)
        }
      }.padding(20)
    }.background(Theme.background).navigationTitle(selected.title).navigationBarTitleDisplayMode(
      .inline
    )
    .scrollDismissesKeyboard(.interactively)
    .onChange(of: query) { _, value in
      if value.count > 80 { query = String(value.prefix(80)) }
    }
    .toolbar {
      ToolbarItem(placement: .primaryAction) {
        Button("发布", systemImage: "plus") { beginCompose() }
      }
    }
    .task(id: filterKey) {
      do {
        if !query.isEmpty { try await Task.sleep(for: .milliseconds(250)) }
        await load()
      } catch {}
    }.refreshable { await load() }
    .sheet(isPresented: $showLogin, onDismiss: { if store.account != nil { showCompose = true } }) {
      LoginView()
    }
    .sheet(isPresented: $showCompose, onDismiss: { Task { await load() } }) {
      CommunityComposer(kind: selected)
    }
  }
  private func beginCompose() {
    if store.account == nil { showLogin = true } else { showCompose = true }
  }
  private func load(reset: Bool = true) async {
    loading = true
    let key = filterKey
    let start = reset ? 0 : offset
    if reset { hasMore = false }
    defer { if key == filterKey { loading = false } }
    do {
      let rows: [CommunityPost] = try await store.communityQuery(
        "posts",
        query: [
          "kind": selected.rawValue, "q": String(query.prefix(80)),
          "city": city == "全国" ? "" : city, "category": category == "全部" ? "" : category,
          "active": String(openOnly), "offset": String(start),
        ])
      guard !Task.isCancelled, key == filterKey else { return }
      if reset {
        posts = rows
      } else {
        let ids = Set(posts.map(\.id))
        posts += rows.filter { !ids.contains($0.id) }
      }
      offset = start + rows.count
      hasMore = rows.count == 100
      error = nil
    } catch is CancellationError {} catch {
      if !Task.isCancelled, key == filterKey { self.error = "信息加载失败，请检查连接后重试。" }
    }
  }
}
struct CommunityRow: View {
  let post: CommunityPost
  var body: some View {
    VStack(alignment: .leading, spacing: 16) {
      HStack(spacing: 12) {
        Image(systemName: post.type.icon).font(TypeScale.heading).foregroundStyle(Theme.accent)
          .frame(
            width: 42, height: 42
          ).background(Theme.accent.opacity(0.08), in: RoundedRectangle(cornerRadius: 12))
        VStack(alignment: .leading, spacing: 4) {
          Text(post.teamName ?? post.authorName).font(.subheadline.weight(.semibold))
          Text(post.city + " · " + post.type.title).font(.caption).foregroundStyle(.secondary)
        }
        Spacer()
        Text(post.isOpen ? "进行中" : post.statusLabel).font(.caption.weight(.medium)).foregroundStyle(
          post.isOpen ? Theme.accent : .secondary)
      }
      Text(post.title).font(.headline).fixedSize(horizontal: false, vertical: true)
      Text(post.body).font(.subheadline).foregroundStyle(.secondary).lineLimit(2).lineSpacing(3)
      HStack(spacing: 8) {
        if post.type != .volunteer {
          Text(post.category + " 级")
          Text("·")
        }
        Text(post.level)
        Spacer()
        Text(post.availability).lineLimit(1)
      }.font(.caption).foregroundStyle(.secondary)
      if let time = post.startsAt {
        Label(Tournament.formatDate(time) + "  " + post.venue, systemImage: "calendar").font(
          .caption
        ).foregroundStyle(Theme.accent)
      }
    }.padding(16).frame(maxWidth: .infinity, alignment: .leading).background(
      Theme.surface, in: RoundedRectangle(cornerRadius: 16))
  }
}
struct CommunityDetail: View {
  @EnvironmentObject private var store: AppStore
  let initial: CommunityPost
  @State private var current: CommunityPost?
  @State private var applications: [CommunityApplication] = []
  @State private var error: String?
  @State private var busy = false
  @State private var showApply = false
  @State private var showLogin = false
  @State private var confirmClose = false
  private var post: CommunityPost { current ?? initial }
  private var owned: Bool { post.authorId == store.account?.id }
  private var ownApplication: CommunityApplication? {
    applications.first { $0.applicantId == store.account?.id }
  }
  var body: some View {
    ScrollView {
      VStack(alignment: .leading, spacing: 24) {
        VStack(alignment: .leading, spacing: 16) {
          HStack {
            Label(post.type.title, systemImage: post.type.icon)
            Spacer()
            Text(post.isOpen ? "进行中" : post.statusLabel)
          }.font(.subheadline)
          Text(post.title).font(TypeScale.title)
          HStack {
            ClubAvatar(name: post.teamName ?? post.authorName)
            VStack(alignment: .leading, spacing: 5) {
              Text(post.teamName ?? post.authorName).font(.headline)
              Text(post.organizationName).font(.caption).foregroundStyle(.secondary)
            }
          }
        }
        if let error { InlineFailure(message: error) { Task { await load() } } }
        VStack(spacing: 16) {
          LabeledContent("所在城市", value: post.city)
          if post.type != .volunteer { LabeledContent("设备级别", value: post.category) }
          LabeledContent(
            post.type == .volunteer ? "志愿岗位" : post.type == .seeking ? "我的经验" : "经验要求",
            value: post.level)
          LabeledContent("可用时间", value: post.availability)
          if !post.venue.isEmpty { LabeledContent("活动场地", value: post.venue) }
          if let time = post.startsAt { LabeledContent("开始时间", value: Tournament.formatDate(time)) }
          if post.type == .friendly { LabeledContent("约赛费用", value: "免费") }
        }.font(.subheadline).padding(16).background(
          Theme.background, in: RoundedRectangle(cornerRadius: 16))
        VStack(alignment: .leading, spacing: 12) {
          Text("详细说明").font(.headline)
          Text(post.body).font(TypeScale.body).lineSpacing(5)
        }
        if owned {
          Text("收到的申请 · \(applications.count)").font(.headline)
          if applications.isEmpty {
            Text("有人提交申请后，会在这里显示。").foregroundStyle(.secondary).font(.subheadline)
          }
          ForEach(applications) { app in
            VStack(alignment: .leading, spacing: 12) {
              HStack {
                Text(app.teamName ?? app.applicantName).font(.headline)
                Spacer()
                Text(app.statusLabel).font(.caption).foregroundStyle(Theme.accent)
              }
              Text(app.message).font(.subheadline)
              NavigationLink("查看留言") { CommunityConversation(application: app) }
              if app.status == "pending" && post.isOpen {
                HStack {
                  Button("接受申请") { Task { await review(app, "accepted") } }.buttonStyle(
                    .borderedProminent
                  ).tint(Theme.solidAccent)
                  Button("不接受") { Task { await review(app, "rejected") } }.buttonStyle(.bordered)
                }.disabled(busy)
              }
            }.padding(16).background(Theme.background, in: RoundedRectangle(cornerRadius: 12))
          }
        } else if let app = ownApplication {
          VStack(alignment: .leading, spacing: 12) {
            Text("我的申请 · " + app.statusLabel).font(.headline)
            Text(app.message).font(.subheadline)
            NavigationLink("联系发布人") { CommunityConversation(application: app) }
            if app.status == "accepted" && post.type == .recruit {
              NavigationLink("打开我的队伍") { TeamsView() }
            }
            if app.status == "accepted" {
              Text(post.type == .recruit ? "你已加入该队伍的成员列表。比赛报名名单仍由队长维护。" : "对方已接受申请，请在申请中心查看活动安排。")
                .font(.subheadline).foregroundStyle(.secondary)
            }
            if app.status == "pending" {
              Button("撤回申请", role: .destructive) { Task { await review(app, "withdrawn") } }
                .disabled(busy)
            }
          }.padding(16).background(Theme.background, in: RoundedRectangle(cornerRadius: 12))
        }
      }.padding(20)
    }.background(Theme.page).navigationTitle(post.type.title).navigationBarTitleDisplayMode(.inline)
      .task { await load() }.refreshable { await load() }
      .onChange(of: store.account?.id) { _, _ in
        applications = []
        Task { await load() }
      }
      .safeAreaInset(edge: .bottom) {
        Group {
          if owned {
            Button(post.type == .friendly ? "取消约赛" : "关闭信息", role: .destructive) {
              confirmClose = true
            }.disabled(post.status == "closed" || post.status == "cancelled" || busy)
          } else {
            Button(
              ownApplication?.status == "withdrawn" && post.isOpen
                ? "重新申请"
                : ownApplication?.statusLabel ?? (post.isOpen ? post.type.action : post.statusLabel)
            ) { if store.account == nil { showLogin = true } else { showApply = true } }.disabled(
              !post.isOpen || (ownApplication != nil && ownApplication?.status != "withdrawn"))
          }
        }.font(.headline).frame(maxWidth: .infinity, minHeight: 48).buttonStyle(.borderedProminent)
          .tint(Theme.solidAccent)
          .padding(.horizontal, 20).padding(.vertical, 12).background(.bar)
      }
      .sheet(
        isPresented: $showLogin,
        onDismiss: {
          if store.account != nil {
            Task {
              await load()
              if !owned && (ownApplication == nil || ownApplication?.status == "withdrawn")
                && post.isOpen
              {
                showApply = true
              }
            }
          }
        }
      ) { LoginView() }
      .sheet(isPresented: $showApply, onDismiss: { Task { await load() } }) {
        CommunityApply(post: post)
      }
      .confirmationDialog(
        "关闭后不再接受申请，已有处理记录会保留。", isPresented: $confirmClose, titleVisibility: .visible
      ) {
        Button(post.type == .friendly ? "取消约赛" : "关闭信息", role: .destructive) {
          Task { await close() }
        }
      }
  }
  private func load() async {
    let owner = store.account?.id
    do {
      let value: CommunityPost = try await store.communityRequest("posts/\(initial.id)")
      current = value
      if store.account != nil {
        let all: [CommunityApplication] = try await store.communityRequest("applications")
        guard store.account?.id == owner else { return }
        applications = all.filter { $0.postId == initial.id }
      } else {
        applications = []
      }
      error = nil
    } catch { self.error = "无法刷新信息，当前显示上次内容。" }
  }
  private func review(_ app: CommunityApplication, _ status: String) async {
    busy = true
    defer { busy = false }
    do {
      let _: CommunityApplication = try await store.communityRequest(
        "applications/\(app.id)", method: "PATCH",
        body: JSONEncoder().encode(StateChange(status: status)))
      await load()
      await store.refresh()
    } catch { self.error = error.localizedDescription }
  }
  private func close() async {
    busy = true
    defer { busy = false }
    do {
      let _: CommunityPost = try await store.communityRequest(
        "posts/\(post.id)", method: "PATCH",
        body: JSONEncoder().encode(
          StateChange(status: post.type == .friendly ? "cancelled" : "closed")))
      await load()
      await store.refresh()
    } catch { self.error = error.localizedDescription }
  }
}
struct CommunityComposer: View {
  @EnvironmentObject private var store: AppStore
  @Environment(\.dismiss) private var dismiss
  let kind: PostKind
  @State private var title = ""
  @State private var city = ""
  @State private var category = "20cm"
  @State private var level = "不限"
  @State private var availability = "周末"
  @State private var venue = ""
  @State private var bodyText = ""
  @State private var teamId = ""
  @State private var startsAt = Date().addingTimeInterval(86400)
  @State private var busy = false
  @State private var error: String?
  @State private var showTeam = false
  private var needsTeam: Bool { kind == .recruit || kind == .friendly }
  private var validationMessage: String? {
    for (name, value) in [("标题", title), ("城市", city), ("经验或岗位", level), ("可参与时间", availability)] {
      if !(2...80).contains(value.trimmingCharacters(in: .whitespacesAndNewlines).count) {
        return "请填写2–80个字的" + name + "。"
      }
    }
    if needsTeam && teamId.isEmpty { return "请选择一支对应级别的队伍。" }
    if !(8...2000).contains(bodyText.trimmingCharacters(in: .whitespacesAndNewlines).count) {
      return "请填写8–2000个字的详细说明。"
    }
    let venueCount = venue.trimmingCharacters(in: .whitespacesAndNewlines).count
    if venueCount > 120 { return "场地说明最多120个字。" }
    if kind == .friendly || kind == .volunteer {
      if venueCount < 2 { return "请填写活动场地。" }
      if startsAt <= Date() { return "请选择未来的活动时间。" }
    }
    return nil
  }

  var body: some View {
    NavigationStack {
      Form {
        Section("基本信息") {
          TextField("标题", text: $title)
          TextField("城市", text: $city)
          if kind != .volunteer {
            Picker("设备级别", selection: $category) {
              Text("20cm").tag("20cm")
              Text("40cm").tag("40cm")
            }
          }
          if needsTeam {
            Picker("发布队伍", selection: $teamId) {
              Text("请选择").tag("")
              ForEach(store.teams.filter { $0.category == category }) { Text($0.name).tag($0.id) }
            }
            Button("创建队伍") { showTeam = true }
          }
        }
        Section("参与条件") {
          if kind == .volunteer {
            TextField("志愿岗位，如场务、检录", text: $level)
          } else {
            Picker(kind == .seeking ? "我的经验" : "经验要求", selection: $level) {
              ForEach(["不限", "入门", "进阶", "竞技"], id: \.self) { Text($0).tag($0) }
            }
          }
          TextField("可参与时间，如周六下午", text: $availability)
          TextField("场地或训练区域", text: $venue)
          if kind == .friendly || kind == .volunteer {
            DatePicker(
              "活动开始", selection: $startsAt, in: Date()...,
              displayedComponents: [.date, .hourAndMinute])
          }
        }
        Section("详细说明") {
          TextField(
            kind == .volunteer
              ? "说明岗位职责、集合地点与准备事项" : kind == .seeking ? "介绍自己的经验、希望加入的队伍与训练安排" : "介绍训练安排、参与要求和准备事项",
            text: $bodyText, axis: .vertical
          ).lineLimit(5...10)
        }
        if kind == .friendly {
          Section {
            Text("当前约赛免费。确认一个对手后停止接受其他申请；取消后双方可查看取消状态。").font(TypeScale.caption).foregroundStyle(
              .secondary)
          }
        }
        if let validationMessage {
          Section { Text(validationMessage).font(TypeScale.body).foregroundStyle(.secondary) }
        }
        if let error { Section { Text(error).foregroundStyle(.red) } }
      }.disabled(busy).navigationTitle(kind.publish).navigationBarTitleDisplayMode(.inline)
        .toolbar {
          ToolbarItem(placement: .cancellationAction) { Button("取消") { dismiss() }.disabled(busy) }
          ToolbarItem(placement: .confirmationAction) {
            Button {
              Task { await publish() }
            } label: {
              if busy { ProgressView() } else { Text("发布") }
            }.disabled(busy || validationMessage != nil)
          }
        }
        .sheet(isPresented: $showTeam) {
          TeamEditor(category: category) { team in teamId = team.id }
        }
        .onChange(of: category) { _, _ in teamId = "" }.interactiveDismissDisabled(busy)
        .onAppear { if kind == .volunteer && level == "不限" { level = "场务协助" } }
    }
  }
  private func publish() async {
    if let validationMessage {
      error = validationMessage
      return
    }
    busy = true
    defer { busy = false }
    do {
      let _: CommunityPost = try await store.communityRequest(
        "posts", method: "POST",
        body: JSONEncoder().encode(
          PostDraft(
            kind: kind.rawValue, title: title, city: city, category: category, level: level,
            availability: availability, venue: venue, body: bodyText,
            teamId: needsTeam ? teamId : nil,
            startsAt: (kind == .friendly || kind == .volunteer)
              ? ISO8601DateFormatter().string(from: startsAt) : nil)))
      dismiss()
    } catch { self.error = error.localizedDescription }
  }
}
struct CommunityApply: View {
  @EnvironmentObject private var store: AppStore
  @Environment(\.dismiss) private var dismiss
  let post: CommunityPost
  @State private var message = ""
  @State private var teamId = ""
  @State private var busy = false
  @State private var error: String?
  @State private var saved = false
  @State private var showTeam = false
  private var draft: ApplicationDraft {
    ApplicationDraft(message: message, teamId: teamId.isEmpty ? nil : teamId)
  }
  var body: some View {
    NavigationStack {
      Form {
        Section {
          Text(post.title).font(.headline)
          Text(post.city + " · " + post.category).font(.subheadline).foregroundStyle(.secondary)
        }
        if saved {
          Section {
            Label("申请已发送", systemImage: "checkmark.circle.fill").foregroundStyle(Theme.accent)
            Text("处理结果会显示在申请中心和本条信息中。")
            Button("完成") { dismiss() }
          }
        } else {
          if post.type == .friendly || post.type == .seeking {
            Section(post.type == .seeking ? "邀请加入的队伍" : "应约队伍") {
              Picker("选择队伍", selection: $teamId) {
                Text("请选择").tag("")
                ForEach(store.teams.filter { $0.category == post.category }) {
                  Text($0.name).tag($0.id)
                }
              }
              Button("创建匹配级别的队伍") { showTeam = true }
            }
          }
          Section("给发布人留言") {
            TextField("介绍经验、可参与时间或需要确认的事项", text: $message, axis: .vertical).lineLimit(4...8)
          }
          if let hint = draft.validationMessage(for: post.type) {
            Section { Text(hint).font(.footnote).foregroundStyle(.secondary) }
          }
          if let error { Section { Text(error).foregroundStyle(.red) } }
          Section {
            Button {
              Task { await apply() }
            } label: {
              HStack {
                Spacer()
                if busy { ProgressView() }
                Text("发送申请")
                Spacer()
              }
            }.disabled(busy || draft.validationMessage(for: post.type) != nil)
          }
        }
      }.sheet(isPresented: $showTeam) {
        TeamEditor(category: post.category) { team in teamId = team.id }
      }
      .navigationTitle(post.type.action).navigationBarTitleDisplayMode(.inline).toolbar {
        ToolbarItem(placement: .cancellationAction) { Button("关闭") { dismiss() }.disabled(busy) }
      }.interactiveDismissDisabled(busy)
    }
  }
  private func apply() async {
    if let validation = draft.validationMessage(for: post.type) {
      error = validation
      return
    }
    busy = true
    defer { busy = false }
    do {
      let _: CommunityApplication = try await store.communityRequest(
        "posts/\(post.id)/applications", method: "POST",
        body: JSONEncoder().encode(draft))
      saved = true
      await store.refresh()
    } catch { self.error = error.localizedDescription }
  }
}
struct CommunityInbox: View {
  @EnvironmentObject private var store: AppStore
  @State private var entries: [CommunityApplication] = []
  @State private var posts: [CommunityPost] = []
  @State private var memberships: [Membership] = []
  @State private var error: String?
  @State private var section = "我发出的"
  @State private var loading = true
  private var filtered: [CommunityApplication] {
    entries.filter {
      section == "我发出的" ? $0.applicantId == store.account?.id : $0.authorId == store.account?.id
    }
  }
  var body: some View {
    List {
      if store.account == nil {
        Section {
          Text("登录后查看申请和发布记录")
          Button("登录") { store.showLogin = true }
        }
      } else {
        if let error { Section { InlineFailure(message: error) { Task { await load() } } } }
        Section {
          Picker("记录类型", selection: $section) {
            ForEach(["我发出的", "我收到的", "我的发布", "加入的队伍"], id: \.self) { Text($0).tag($0) }
          }
        }
        if section == "我的发布" {
          if posts.isEmpty { Text("还没有发布记录").foregroundStyle(.secondary) }
          ForEach(posts.filter { $0.authorId == store.account?.id }) { post in
            NavigationLink {
              CommunityDetail(initial: post)
            } label: {
              VStack(alignment: .leading, spacing: 8) {
                Text(post.title).font(.headline)
                Text(post.type.title + " · " + post.statusLabel).font(.caption).foregroundStyle(
                  .secondary)
              }
            }
          }
        } else if section == "加入的队伍" {
          if memberships.isEmpty {
            Text("暂未加入队伍，可通过招募申请加入。").font(TypeScale.body).foregroundStyle(.secondary)
          }
          ForEach(memberships) { item in
            NavigationLink {
              TeamMembersView(teamID: item.teamId, teamName: item.teamName)
            } label: {
              VStack(alignment: .leading, spacing: 8) {
                Text(item.teamName).font(.headline)
                Text(item.city + " · " + item.category).font(.subheadline).foregroundStyle(
                  .secondary)
                Text("加入于 " + Tournament.formatDate(item.joinedAt)).font(.caption).foregroundStyle(
                  .secondary)
              }
            }
          }
        } else {
          if loading {
            ProgressView("正在加载申请")
          } else if filtered.isEmpty && error == nil {
            Text("暂无申请记录").foregroundStyle(.secondary)
          }
          ForEach(filtered) { entry in
            NavigationLink {
              CommunityConversation(application: entry)
            } label: {
              VStack(alignment: .leading, spacing: 8) {
                HStack {
                  Text(entry.postTitle).font(.headline)
                  Spacer()
                  UnreadBadge(count: entry.unreadCount ?? 0)
                  Text(entry.statusLabel).font(.caption).foregroundStyle(Theme.accent)
                }
                Text(entry.message).font(.subheadline).foregroundStyle(.secondary).lineLimit(2)
                if entry.postStatus == "cancelled" {
                  Text("活动已取消").font(.caption).foregroundStyle(.red)
                }
              }.padding(.vertical, 8)
            }
          }
        }
      }
    }.navigationTitle("申请中心").navigationBarTitleDisplayMode(.inline).task { await load() }.onChange(
      of: store.account?.id
    ) { _, _ in
      entries = []
      posts = []
      memberships = []
      Task { await load() }
    }.onReceive(store.$applications) { entries = $0 }.refreshable { await load() }
  }
  private func load() async {
    guard let owner = store.account?.id else { return }
    loading = true
    defer { loading = false }
    do {
      let a: [CommunityApplication] = try await store.communityRequest("applications")
      let p: [CommunityPost] = try await store.communityPages("posts", query: ["mine": "true"])
      let m: [Membership] = try await store.communityRequest("memberships")
      guard store.account?.id == owner else { return }
      entries = a
      posts = p
      memberships = m
      error = nil
    } catch { self.error = "申请信息加载失败，请重试。" }
  }
}
struct CommunityDestination: View {
  @EnvironmentObject private var store: AppStore
  let id: String
  @State private var post: CommunityPost?
  @State private var error: String?
  var body: some View {
    Group {
      if let post {
        CommunityDetail(initial: post)
      } else if let error {
        InlineFailure(message: error) { Task { await load() } }
      } else {
        ProgressView("正在加载")
      }
    }.task { await load() }
  }
  private func load() async {
    do {
      post = try await store.communityRequest("posts/\(id)")
      error = nil
    } catch { self.error = "暂时无法加载，请重试。" }
  }
}
