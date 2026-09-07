import SwiftUI

struct TournamentParticipant: Decodable, Identifiable {
  let id, teamId, name, city, category, organizationName: String
}
struct TournamentDetail: View {
  @EnvironmentObject private var store: AppStore
  let initial: Tournament
  @State private var showRegistration = false
  @State private var showLogin = false
  @State private var selection = "概览"
  @State private var participants: [TournamentParticipant] = []
  @State private var loading = true
  @State private var error: String?
  private var isOrganizer: Bool { store.account?.role == "organizer" }
  private var event: Tournament { store.tournaments.first { $0.id == initial.id } ?? initial }
  private var entries: [Registration] { store.registrations.filter { $0.tournamentId == event.id } }
  var body: some View {
    ScrollView {
      VStack(alignment: .leading, spacing: 24) {
        VStack(alignment: .leading, spacing: 16) {
          HStack {
            StatusBadge(text: event.statusLabel)
            Spacer()
            Text(event.category + " 级").font(TypeScale.caption).foregroundStyle(.secondary)
          }
          Text(event.title).font(TypeScale.title).fixedSize(horizontal: false, vertical: true)
          Text(event.organizerName).font(TypeScale.body).foregroundStyle(.secondary)
          HStack(alignment: .firstTextBaseline, spacing: 8) {
            Text("\(event.approved)").font(TypeScale.title).monospacedDigit()
            Text("/ \(event.capacity) 队已通过").font(TypeScale.body).foregroundStyle(.secondary)
          }
        }.padding(24).frame(maxWidth: .infinity, alignment: .leading).background(
          Theme.surface, in: RoundedRectangle(cornerRadius: 16))
        ScrollView(.horizontal, showsIndicators: false) {
          HStack(spacing: 8) {
            ForEach(["概览", "规程", "参赛队伍", "赛程"], id: \.self) { item in
              FilterChip(title: item, selected: selection == item) { selection = item }
            }
          }
        }
        SyncNotice()
        if selection == "概览" {
          VStack(alignment: .leading, spacing: 24) {
            info(
              "比赛时间", value: event.monthTitle + event.dayLabel + "日  " + event.dateLabel.suffix(5),
              icon: "calendar")
            info("报名截止", value: Tournament.formatDate(event.deadline), icon: "clock")
            info("比赛场地", value: event.city + " · " + event.venue, icon: "mappin.and.ellipse")
          }
          Divider()
          SectionHeading(title: "赛事介绍")
          Text(event.description).font(TypeScale.body).lineSpacing(4)
          if !entries.isEmpty {
            SectionHeading(title: store.account?.role == "organizer" ? "赛事报名记录" : "我的报名")
            ForEach(entries) { entry in
              NavigationLink {
                RegistrationDetail(initial: entry)
              } label: {
                RegistrationRow(entry: entry)
              }.buttonStyle(.plain)
            }
          }
        } else if selection == "规程" {
          SectionHeading(title: "参赛规程", subtitle: "报名之前请确认以下要求")
          Text(event.rules).font(TypeScale.body).lineSpacing(8)
          NavigationLink("查看报名流程") { ParticipationGuide() }.font(TypeScale.body).frame(
            minHeight: 44)
        } else if selection == "赛程" {
          MatchScheduleView(event: event)
        } else {
          SectionHeading(title: "已通过审核的队伍", subtitle: "仅展示公开队伍信息")
          if loading { ProgressView("正在加载参赛队伍") }
          if let error { InlineFailure(message: error) { Task { await loadParticipants() } } }
          if !loading && error == nil && participants.isEmpty {
            EmptyPanel(title: "参赛队伍尚未公布", detail: "队伍通过报名审核后，将显示在这里。", icon: "person.3")
          }
          ForEach(participants) { team in
            HStack(spacing: 16) {
              ClubAvatar(name: team.name)
              VStack(alignment: .leading, spacing: 8) {
                Text(team.name).font(TypeScale.heading)
                Text(team.city + " · " + team.organizationName).font(TypeScale.caption)
                  .foregroundStyle(.secondary)
              }
              Spacer()
            }.padding(.vertical, 8)
            Divider()
          }
        }
      }.padding(20).frame(maxWidth: 600)
    }.frame(maxWidth: .infinity).background(Theme.background)
      .navigationTitle("赛事详情").navigationBarTitleDisplayMode(.inline).toolbar(.hidden, for: .tabBar)
      .safeAreaInset(edge: .bottom) {
        HStack(spacing: 24) {
          VStack(alignment: .leading, spacing: 4) {
            Text(isOrganizer ? "赛事工作台" : "报名费").font(TypeScale.caption).foregroundStyle(.secondary)
            Text(isOrganizer ? "赛程与结果" : "免费").font(TypeScale.heading)
          }
          Button {
            if isOrganizer {
              selection = "赛程"
            } else if store.account == nil {
              showLogin = true
            } else {
              showRegistration = true
            }
          } label: {
            Text(
              isOrganizer
                ? "查看赛程"
                : !event.canRegister
                  ? event.statusLabel
                  : store.account == nil ? "登录后报名" : entries.isEmpty ? "报名参赛" : "为其他队伍报名"
            ).font(TypeScale.heading).frame(maxWidth: .infinity, minHeight: 48)
          }.buttonStyle(.borderedProminent).tint(Theme.solidAccent).buttonBorderShape(
            .roundedRectangle(radius: 12)
          ).disabled(!isOrganizer && !event.canRegister)
        }.padding(.horizontal, 20).padding(.vertical, 12).background(.bar)
      }
      .sheet(
        isPresented: $showLogin,
        onDismiss: {
          if isOrganizer {
            selection = "赛程"
          } else if store.account != nil && event.canRegister {
            showRegistration = true
          }
        }
      ) { LoginView() }
      .sheet(isPresented: $showRegistration) { RegistrationSheet(event: event) }
      .task { await loadParticipants() }
      .refreshable {
        await store.refresh()
        await loadParticipants()
      }
  }
  private func info(_ title: String, value: String, icon: String) -> some View {
    HStack(alignment: .top, spacing: 16) {
      Image(systemName: icon).foregroundStyle(Theme.accent).frame(width: 24)
      VStack(alignment: .leading, spacing: 8) {
        Text(title).font(TypeScale.caption).foregroundStyle(.secondary)
        Text(value).font(TypeScale.body)
      }
    }.accessibilityElement(children: .combine)
  }
  private func loadParticipants() async {
    loading = true
    defer { loading = false }
    do {
      participants = try await store.request("tournaments/\(event.id)/participants")
      error = nil
    } catch is CancellationError {} catch { self.error = "无法加载参赛队伍，请重试。" }
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
                Text(event.rules).font(TypeScale.caption).foregroundStyle(.secondary)
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
