import SwiftUI

struct TeamsView: View {
  @EnvironmentObject private var store: AppStore
  @State private var showCreate = false
  var body: some View {
    List {
      if store.error != nil { Section { SyncNotice() } }
      if store.account == nil {
        Section {
          EmptyPanel(title: "找到你的队伍", detail: "登录后管理队伍，或接受招募加入其他队伍。", icon: "person.3")
          Button("登录") { store.showLogin = true }.frame(minHeight: 44)
        }
      } else {
        Section("我管理的") {
          if store.isLoading && store.teams.isEmpty {
            ProgressView("正在加载")
          } else if store.teams.isEmpty {
            Text("暂无管理的队伍").font(TypeScale.body).foregroundStyle(.secondary)
          }
          ForEach(store.teams) { team in
            NavigationLink {
              TeamDetail(initial: team)
            } label: {
              HStack(spacing: 16) {
                ClubAvatar(name: team.name)
                VStack(alignment: .leading, spacing: 8) {
                  Text(team.name).font(TypeScale.heading)
                  Text(team.city + " · " + team.category + " · 名单 \(team.roster.count) 人").font(
                    TypeScale.caption
                  ).foregroundStyle(.secondary)
                }
              }.padding(.vertical, 8)
            }
          }
          if store.account?.role == "captain" {
            Button {
              showCreate = true
            } label: {
              Label("创建队伍", systemImage: "plus.circle").frame(minHeight: 44)
            }
          }
        }
        Section("我加入的") {
          if store.memberships.isEmpty {
            Text("通过招募加入后，队伍会显示在这里。").font(TypeScale.body).foregroundStyle(.secondary)
          }
          ForEach(store.memberships) { membership in
            NavigationLink {
              TeamMembersView(teamID: membership.teamId, teamName: membership.teamName)
            } label: {
              HStack(spacing: 16) {
                ClubAvatar(name: membership.teamName)
                VStack(alignment: .leading, spacing: 8) {
                  Text(membership.teamName).font(TypeScale.heading)
                  Text(membership.city + " · " + membership.category).font(TypeScale.caption)
                    .foregroundStyle(.secondary)
                }
              }.padding(.vertical, 8)
            }
          }
          NavigationLink {
            CommunityView(kind: .recruit)
          } label: {
            Label("看看哪些队伍正在招募", systemImage: "person.2.badge.plus").frame(minHeight: 44)
          }
        }
      }
    }.navigationTitle("我的队伍").navigationBarTitleDisplayMode(.inline).refreshable {
      await store.refresh()
    }.task { await store.refresh() }
      .sheet(isPresented: $showCreate) { TeamEditor() }
  }
}

struct TeamDetail: View {
  @EnvironmentObject private var store: AppStore
  let initial: Team
  @State private var showEdit = false
  private var team: Team { store.teams.first { $0.id == initial.id } ?? initial }
  private var entries: [Registration] { store.registrations.filter { $0.teamId == initial.id } }
  var body: some View {
    List {
      if store.account == nil {
        Section {
          Text("登录后查看队伍资料")
          Button("登录") { store.showLogin = true }
        }
      } else if !store.teams.contains(where: { $0.id == initial.id }) {
        ContentUnavailableView("队伍暂不可用", systemImage: "person.2", description: Text("请返回队伍列表并刷新。"))
      } else {
        if store.error != nil { Section { SyncNotice() } }
        Section {
          HStack(spacing: 16) {
            ClubAvatar(name: team.name, size: 56)
            VStack(alignment: .leading, spacing: 8) {
              Text(team.name).font(TypeScale.heading)
              Text(team.city + " · " + team.category + " 级").font(.subheadline).foregroundStyle(
                .secondary)
            }
          }.padding(.vertical, 10)
        }
        Section {
          ForEach(team.roster, id: \.self) { name in
            HStack(spacing: 12) {
              Image(systemName: "person").foregroundStyle(.secondary)
              Text(name)
            }.padding(.vertical, 5)
          }
          Button("编辑队伍与名单") { showEdit = true }.frame(minHeight: 44)
        } header: {
          Text("当前名单 · \(team.roster.count) 人")
        } footer: {
          Text("名单用于之后的报名。已提交报名的名单保持不变。")
        }
        Section {
          NavigationLink {
            TeamMembersView(teamID: team.id, teamName: team.name)
          } label: {
            Label("社区成员", systemImage: "person.2")
          }
        }
        Section("这支队伍的报名") {
          if entries.isEmpty { Text("暂无报名记录").foregroundStyle(.secondary) }
          ForEach(entries) { entry in
            NavigationLink {
              RegistrationDetail(initial: entry)
            } label: {
              RegistrationRow(entry: entry)
            }
          }
          Button("浏览赛事") { store.selectedTab = 0 }.frame(minHeight: 44)
        }
      }
    }
    .navigationTitle("队伍详情").navigationBarTitleDisplayMode(.inline)
    .refreshable { await store.refresh() }
    .sheet(isPresented: $showEdit) { TeamEditor(team: team) }
  }
}

private struct MemberDraft: Identifiable {
  let id = UUID()
  var name: String
}

struct TeamEditor: View {
  @EnvironmentObject private var store: AppStore
  @Environment(\.dismiss) private var dismiss
  private let team: Team?
  private let requiredCategory: String?
  private let onSaved: (Team) -> Void
  @State private var name: String
  @State private var city: String
  @State private var category: String
  @State private var members: [MemberDraft]
  @State private var adultOnly = false
  @State private var busy = false
  @State private var error: String?
  @State private var attempted = false
  @FocusState private var focusedMember: UUID?

  init(team: Team? = nil, category: String? = nil, onSaved: @escaping (Team) -> Void = { _ in }) {
    self.team = team
    self.requiredCategory = category
    self.onSaved = onSaved
    _name = State(initialValue: team?.name ?? "")
    _city = State(initialValue: team?.city ?? "")
    _category = State(initialValue: team?.category ?? category ?? "20cm")
    _members = State(initialValue: (team?.roster ?? [""]).map { MemberDraft(name: $0) })
  }
  private var names: [String] {
    members.map { $0.name.trimmingCharacters(in: .whitespacesAndNewlines) }
  }
  private var validation: String? {
    let cleanName = name.trimmingCharacters(in: .whitespacesAndNewlines)
    let cleanCity = city.trimmingCharacters(in: .whitespacesAndNewlines)
    if !(2...80).contains(cleanName.count) { return "队伍名称需为 2–80 个字。" }
    if !(2...80).contains(cleanCity.count) { return "城市需为 2–80 个字。" }
    if names.isEmpty || names.count > 10 { return "名单需包含 1–10 人。" }
    if names.contains(where: { $0.isEmpty || $0.count > 40 }) { return "请填写每位飞手姓名，每个姓名最多 40 个字。" }
    if Set(names).count != names.count { return "名单中有重复姓名，请核对后保存。" }
    if !adultOnly { return "请确认仅使用虚构的成年演示资料。" }
    return nil
  }
  var body: some View {
    NavigationStack {
      Form {
        Section("队伍资料") {
          TextField("队伍名称", text: $name).accessibilityLabel("队伍名称")
          TextField("所在城市", text: $city).accessibilityLabel("所在城市")
          if let requiredCategory {
            LabeledContent("赛事要求级别", value: requiredCategory + " 级")
          } else {
            Picker("设备级别", selection: $category) {
              Text("20cm 级").tag("20cm")
              Text("40cm 级").tag("40cm")
            }
          }
        }
        Section {
          ForEach($members) { $member in
            HStack {
              TextField("飞手姓名", text: $member.name).focused($focusedMember, equals: member.id)
                .accessibilityLabel("飞手姓名")
              Button(role: .destructive) {
                members.removeAll { $0.id == member.id }
              } label: {
                Image(systemName: "minus.circle").frame(width: 44, height: 44)
              }.buttonStyle(.borderless).accessibilityLabel(
                "移除\(member.name.isEmpty ? "空白飞手" : member.name)")
            }
          }
          if members.count < 10 {
            Button {
              let member = MemberDraft(name: "")
              members.append(member)
              focusedMember = member.id
            } label: {
              Label("添加飞手", systemImage: "plus.circle")
            }.frame(minHeight: 44)
          }
        } header: {
          Text("人员名单 · \(members.count)/10")
        } footer: {
          Text(team == nil ? "逐项添加人员，报名时会再次确认名单。" : "保存后用于后续报名，已提交的队名和名单不会改变。")
        }
        Section {
          Toggle("仅使用虚构的成年演示资料", isOn: $adultOnly)
        }
        if attempted, let validation { Section { Text(validation).foregroundStyle(.red) } }
        if let error { Section { Text(error).foregroundStyle(.red) } }
      }
      .disabled(busy)
      .navigationTitle(team == nil ? "创建队伍" : "编辑队伍").navigationBarTitleDisplayMode(.inline)
      .toolbar {
        ToolbarItem(placement: .cancellationAction) { Button("取消") { dismiss() }.disabled(busy) }
        ToolbarItem(placement: .confirmationAction) {
          Button {
            Task { await save() }
          } label: {
            if busy { ProgressView() } else { Text("保存").fontWeight(.semibold) }
          }.disabled(busy)
        }
      }.interactiveDismissDisabled(busy)
    }
  }
  private func save() async {
    attempted = true
    guard validation == nil else { return }
    focusedMember = nil
    error = nil
    busy = true
    defer { busy = false }
    do {
      let saved = try await store.saveTeam(
        CreateTeam(
          name: name.trimmingCharacters(in: .whitespacesAndNewlines),
          city: city.trimmingCharacters(in: .whitespacesAndNewlines), category: category,
          roster: names), id: team?.id)
      onSaved(saved)
      dismiss()
    } catch { self.error = error.localizedDescription }
  }
}
