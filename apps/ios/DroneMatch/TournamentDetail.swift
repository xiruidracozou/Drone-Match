import SwiftUI

struct TournamentDetail: View {
  @EnvironmentObject private var store: AppStore
  let initial: Tournament
  @State private var showRegistration = false
  @State private var showLogin = false
  private var event: Tournament { store.tournaments.first { $0.id == initial.id } ?? initial }
  private var entries: [Registration] { store.registrations.filter { $0.tournamentId == event.id } }

  var body: some View {
    ScrollView {
      VStack(alignment: .leading, spacing: 24) {
        SyncNotice()
        VStack(alignment: .leading, spacing: 14) {
          StatusBadge(text: event.statusLabel)
          Text(event.title).font(.title2.weight(.bold)).fixedSize(horizontal: false, vertical: true)
          Text(event.organizerName).font(.subheadline).foregroundStyle(.secondary)
          HStack {
            Text(event.category + " 级").font(.subheadline.weight(.medium))
            Spacer()
            Text("\(event.approved) / \(event.capacity) 队已通过").font(.subheadline).foregroundStyle(
              .secondary)
          }.padding(.top, 6)
        }
        Divider()
        VStack(alignment: .leading, spacing: 20) {
          info(
            "比赛时间", value: event.monthTitle + event.dayLabel + "日  " + event.dateLabel.suffix(5),
            icon: "calendar")
          info("报名截止", value: Tournament.formatDate(event.deadline), icon: "clock")
          info("比赛场地", value: event.city + " · " + event.venue, icon: "mappin.and.ellipse")
        }
        Divider()
        VStack(alignment: .leading, spacing: 12) {
          Text("赛事介绍").font(.headline)
          Text(event.description).font(.body).lineSpacing(5).foregroundStyle(.secondary)
        }
        VStack(alignment: .leading, spacing: 12) {
          Text("参赛须知").font(.headline)
          Text(event.rules).font(.subheadline).lineSpacing(5).foregroundStyle(.secondary)
        }
        if !entries.isEmpty {
          VStack(alignment: .leading, spacing: 12) {
            Text("本赛事报名").font(.headline)
            ForEach(entries) { entry in
              NavigationLink {
                RegistrationDetail(initial: entry)
              } label: {
                HStack {
                  VStack(alignment: .leading, spacing: 8) {
                    Text(entry.teamName).font(.subheadline.weight(.semibold))
                    StatusBadge(text: entry.statusLabel)
                  }
                  Spacer()
                  Image(systemName: "chevron.right").font(.caption).foregroundStyle(.secondary)
                }.padding(16).background(Theme.background, in: RoundedRectangle(cornerRadius: 10))
              }.buttonStyle(.plain)
            }
            Text("同一队伍仅能提交一次，已提交名单保留不变。").font(.footnote).foregroundStyle(.secondary)
          }
        }
      }.padding(20).frame(maxWidth: 680)
    }
    .frame(maxWidth: .infinity).background(Theme.page)
    .navigationTitle("赛事详情").navigationBarTitleDisplayMode(.inline).toolbar(.hidden, for: .tabBar)
    .safeAreaInset(edge: .bottom) {
      HStack(spacing: 24) {
        VStack(alignment: .leading, spacing: 4) {
          Text("报名费用").font(.caption).foregroundStyle(.secondary)
          Text("免费").font(.headline)
        }
        Button {
          if store.account == nil { showLogin = true } else { showRegistration = true }
        } label: {
          Text(
            !event.canRegister
              ? event.statusLabel
              : store.account == nil ? "登录后报名" : entries.isEmpty ? "报名参赛" : "为其他队伍报名"
          )
          .font(.headline).frame(maxWidth: .infinity, minHeight: 44)
        }.buttonStyle(.borderedProminent).buttonBorderShape(.roundedRectangle(radius: 12))
          .disabled(!event.canRegister)
      }.padding(.horizontal, 20).padding(.vertical, 12).background(.bar)
    }
    .sheet(
      isPresented: $showLogin,
      onDismiss: {
        if store.account != nil { showRegistration = true }
      }
    ) { LoginView() }
    .sheet(isPresented: $showRegistration) { RegistrationSheet(event: event) }
    .refreshable { await store.refresh() }
  }
  private func info(_ label: String, value: String, icon: String) -> some View {
    HStack(alignment: .top, spacing: 14) {
      Image(systemName: icon).foregroundStyle(Theme.green).frame(width: 22)
      VStack(alignment: .leading, spacing: 6) {
        Text(label).font(.caption).foregroundStyle(.secondary)
        Text(value).font(.subheadline)
      }
    }.accessibilityElement(children: .combine)
  }
}

struct TournamentDestination: View {
  let id: String
  @State private var event: Tournament?
  @State private var error: String?
  var body: some View {
    Group {
      if let event {
        TournamentDetail(initial: event)
      } else if let error {
        ContentUnavailableView {
          Label("无法加载赛事", systemImage: "wifi.exclamationmark")
        } description: {
          Text(error)
        } actions: {
          Button("重新加载") { Task { await load() } }
        }
      } else {
        ProgressView("正在加载赛事")
      }
    }.task { await load() }
  }
  private func load() async {
    error = nil
    do { event = try await APIClient().request("tournaments/\(id)") } catch {
      self.error = (error as? APIError)?.message ?? "请检查服务连接后重试。"
    }
  }
}

struct RegistrationSheet: View {
  @EnvironmentObject private var store: AppStore
  @Environment(\.dismiss) private var dismiss
  let event: Tournament
  @State private var teamID = ""
  @State private var accepted = false
  @State private var busy = false
  @State private var error: String?
  @State private var submitted: Registration?
  @State private var showCreate = false
  private var compatibleTeams: [Team] {
    let registered = Set(store.registrations.filter { $0.tournamentId == event.id }.map(\.teamId))
    return store.teams.filter { $0.category == event.category && !registered.contains($0.id) }
  }
  var body: some View {
    NavigationStack {
      Group {
        if let submitted {
          RegistrationDetail(initial: submitted)
        } else {
          Form {
            Section {
              Text(event.title).font(.headline)
              LabeledContent("设备级别", value: event.category + " 级")
              LabeledContent("报名费用", value: "免费")
            }
            if store.error != nil { Section { SyncNotice() } }
            Section("参赛队伍") {
              if compatibleTeams.isEmpty {
                Text("还没有可报名的 \(event.category) 级队伍").font(.headline)
                Text("创建一支队伍后可直接继续报名。已经提交过本赛事的队伍不会重复显示。").font(.subheadline).foregroundStyle(
                  .secondary)
              } else {
                Picker("选择队伍", selection: $teamID) {
                  Text("请选择").tag("")
                  ForEach(compatibleTeams) { Text($0.name).tag($0.id) }
                }
              }
              Button {
                showCreate = true
              } label: {
                Label("创建队伍并继续", systemImage: "plus")
              }.disabled(busy)
            }
            if let team = compatibleTeams.first(where: { $0.id == teamID }) {
              Section {
                ForEach(team.roster, id: \.self) { Text($0) }
              } header: {
                Text("本次报名名单 · \(team.roster.count) 人")
              } footer: {
                Text("提交后保留本次名单，之后编辑队伍不会改变这次报名。")
              }
              Section("确认报名") {
                Text(event.rules).font(.footnote).foregroundStyle(.secondary)
                Toggle("已阅读规则并确认名单", isOn: $accepted)
              }
              if let error { Section { Text(error).foregroundStyle(.red) } }
              Section {
                Button {
                  Task { await submit() }
                } label: {
                  HStack {
                    Spacer()
                    if busy { ProgressView() }
                    Text("确认提交报名").fontWeight(.semibold)
                    Spacer()
                  }.frame(minHeight: 44)
                }.disabled(!accepted || busy)
              }
            }
          }.navigationTitle("确认报名").navigationBarTitleDisplayMode(.inline)
        }
      }
      .toolbar {
        ToolbarItem(placement: .cancellationAction) {
          Button(submitted == nil ? "取消" : "完成") { dismiss() }.disabled(busy)
        }
      }
      .interactiveDismissDisabled(busy)
      .sheet(isPresented: $showCreate) {
        TeamEditor(category: event.category) { team in
          teamID = team.id
          accepted = false
        }
      }
      .onChange(of: teamID) { _, _ in accepted = false }
      .onChange(of: compatibleTeams) { _, _ in accepted = false }
    }
  }
  private func submit() async {
    busy = true
    defer { busy = false }
    error = nil
    do { submitted = try await store.submit(tournamentID: event.id, teamID: teamID) } catch {
      self.error = error.localizedDescription
    }
  }
}
