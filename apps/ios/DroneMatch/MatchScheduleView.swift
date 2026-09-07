import SwiftUI

struct ScheduledMatch: Codable, Identifiable {
  let id, tournamentId, homeRegistrationId, awayRegistrationId, homeName, awayName, startsAt,
    endsAt, venue, stage, status, note: String
  let tournamentTitle: String?
  let homeScore, awayScore: Int?
  let version: Int
  var statusLabel: String {
    ["scheduled": "未开赛", "final": "已结束", "cancelled": "已取消"][status] ?? status
  }
}
private struct MatchDraft: Encodable {
  let homeRegistrationId, awayRegistrationId, startsAt, endsAt, venue, stage, status, note: String
  let homeScore, awayScore, version: Int?
}
struct MatchScheduleView: View {
  @EnvironmentObject private var store: AppStore
  let event: Tournament
  @State private var matches: [ScheduledMatch] = []
  @State private var loading = true
  @State private var error: String?
  @State private var showCreate = false
  @State private var selected: ScheduledMatch?
  private var canManage: Bool {
    store.account?.role == "organizer" && store.account?.organizationId == event.organizationId
  }
  var body: some View {
    VStack(alignment: .leading, spacing: 16) {
      SectionHeading(title: "赛程与结果", subtitle: "由主办方发布，比分按本赛事规程记录")
      if loading { ProgressView("正在加载赛程") }
      if let error { InlineFailure(message: error) { Task { await load() } } }
      if !loading && matches.isEmpty && error == nil {
        EmptyPanel(title: "赛程尚未公布", detail: "主办方发布对阵后，可以在这里查看时间、场地和比赛结果。", icon: "calendar")
      }
      ForEach(matches) { match in
        Button {
          selected = match
        } label: {
          MatchCard(match: match)
        }.buttonStyle(.plain)
      }
      if canManage {
        Button {
          showCreate = true
        } label: {
          Label("发布赛程", systemImage: "plus").font(TypeScale.heading).frame(
            maxWidth: .infinity, minHeight: 48)
        }.buttonStyle(.borderedProminent).tint(Theme.solidAccent)
      }
    }.task { await load() }
      .sheet(isPresented: $showCreate, onDismiss: { Task { await load() } }) {
        MatchEditor(event: event, match: nil)
      }
      .sheet(item: $selected, onDismiss: { Task { await load() } }) { match in
        if canManage {
          MatchEditor(event: event, match: match)
        } else {
          NavigationStack {
            MatchInformation(match: match).toolbar {
              ToolbarItem(placement: .confirmationAction) { Button("完成") { selected = nil } }
            }
          }
        }
      }
  }
  private func load() async {
    loading = true
    defer { loading = false }
    do {
      matches = try await store.request("tournaments/\(event.id)/matches")
      error = nil
    } catch is CancellationError {} catch { self.error = "赛程加载失败，请重试。" }
  }
}
struct MatchCard: View {
  let match: ScheduledMatch
  var body: some View {
    VStack(spacing: 16) {
      HStack {
        Text(match.stage)
        Spacer()
        Text(match.statusLabel).foregroundStyle(
          match.status == "cancelled" ? .secondary : Theme.accent)
      }.font(TypeScale.caption)
      HStack(alignment: .center, spacing: 12) {
        team(match.homeName)
        VStack(spacing: 4) {
          Text(match.status == "final" ? "\(match.homeScore ?? 0) : \(match.awayScore ?? 0)" : "VS")
            .font(TypeScale.title).monospacedDigit()
          Text(match.status == "final" ? "比赛结果" : "对阵").font(TypeScale.caption).foregroundStyle(
            .secondary)
        }
        team(match.awayName)
      }
      Divider()
      HStack {
        Text(Tournament.formatDate(match.startsAt))
        Spacer()
        Text(match.venue)
      }.font(TypeScale.caption).foregroundStyle(.secondary)
    }.padding(20).background(Theme.surface, in: RoundedRectangle(cornerRadius: 16))
  }
  private func team(_ name: String) -> some View {
    VStack(spacing: 8) {
      ClubAvatar(name: name, size: 44)
      Text(name).font(TypeScale.body.weight(.semibold)).multilineTextAlignment(.center)
    }.frame(maxWidth: .infinity)
  }
}
struct MatchInformation: View {
  let match: ScheduledMatch
  var body: some View {
    List {
      Section { MatchCard(match: match).listRowInsets(EdgeInsets()) }
      Section("比赛安排") {
        if let title = match.tournamentTitle { LabeledContent("所属赛事", value: title) }
        LabeledContent("开始时间", value: Tournament.formatDate(match.startsAt))
        LabeledContent("结束时间", value: Tournament.formatDate(match.endsAt))
        LabeledContent("比赛场地", value: match.venue)
      }
      if !match.note.isEmpty { Section("主办方说明") { Text(match.note).font(TypeScale.body) } }
    }.navigationTitle("对阵详情").navigationBarTitleDisplayMode(.inline)
  }
}
private struct MatchEditor: View {
  @EnvironmentObject private var store: AppStore
  @Environment(\.dismiss) private var dismiss
  let event: Tournament
  let match: ScheduledMatch?
  @State private var teams: [TournamentParticipant] = []
  @State private var home = ""
  @State private var away = ""
  @State private var venue = ""
  @State private var stage = "小组赛"
  @State private var status = "scheduled"
  @State private var note = ""
  @State private var starts = Date()
  @State private var ends = Date().addingTimeInterval(1800)
  @State private var homeScore = 0
  @State private var awayScore = 0
  @State private var busy = false
  @State private var loading = true
  @State private var error: String?
  private var valid: Bool {
    !home.isEmpty && !away.isEmpty && home != away
      && venue.trimmingCharacters(in: .whitespaces).count >= 2
      && stage.trimmingCharacters(in: .whitespaces).count >= 2 && ends > starts
      && (status != "final" || ends <= Date())
  }
  var body: some View {
    NavigationStack {
      Form {
        if loading { ProgressView("正在加载参赛队伍") }
        Section("对阵队伍") {
          Picker("队伍 A", selection: $home) {
            Text("请选择").tag("")
            ForEach(teams) { Text($0.name).tag($0.id) }
          }
          Picker("队伍 B", selection: $away) {
            Text("请选择").tag("")
            ForEach(teams.filter { $0.id != home }) { Text($0.name).tag($0.id) }
          }
          if !loading && teams.count < 2 {
            Text("需先有两支队伍通过报名审核，才可发布对阵。").font(TypeScale.body).foregroundStyle(.secondary)
          }
        }
        Section("时间与场地") {
          TextField("比赛阶段", text: $stage)
          TextField("具体场地", text: $venue)
          DatePicker("开始", selection: $starts)
          DatePicker("结束", selection: $ends)
          if ends <= starts { Text("结束时间应晚于开始时间").foregroundStyle(.red) }
        }
        Section("比赛状态") {
          Picker("状态", selection: $status) {
            Text("未开赛").tag("scheduled")
            Text("已结束").tag("final")
            Text("已取消").tag("cancelled")
          }
          if status == "final" {
            Stepper("队伍 A 比分：\(homeScore)", value: $homeScore, in: 0...999)
            Stepper("队伍 B 比分：\(awayScore)", value: $awayScore, in: 0...999)
            Text("按已确认的本赛事规程填写最终结果，系统不会将此结果换算为飞手个人战绩。").font(TypeScale.caption).foregroundStyle(
              .secondary)
            if ends > Date() {
              Text("比赛结束时间尚未到达，请核对时间或选择未开赛。").font(TypeScale.body).foregroundStyle(.red)
            }
          }
          TextField("比赛说明或取消原因", text: $note, axis: .vertical).lineLimit(3...6)
        }
        if let error { Section { Text(error).foregroundStyle(.red) } }
      }.disabled(busy).navigationTitle(match == nil ? "发布赛程" : "编辑赛程")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
          ToolbarItem(placement: .cancellationAction) { Button("取消") { dismiss() }.disabled(busy) }
          ToolbarItem(placement: .confirmationAction) {
            Button {
              Task { await save() }
            } label: {
              if busy { ProgressView() } else { Text("保存") }
            }.disabled(busy || loading || !valid)
          }
        }.interactiveDismissDisabled(busy).task {
          if let match {
            home = match.homeRegistrationId
            away = match.awayRegistrationId
            venue = match.venue
            stage = match.stage
            status = match.status
            note = match.note
            starts = Tournament.dateFrom(match.startsAt) ?? Date()
            ends = Tournament.dateFrom(match.endsAt) ?? starts.addingTimeInterval(1800)
            homeScore = match.homeScore ?? 0
            awayScore = match.awayScore ?? 0
          } else {
            venue = event.venue
            starts = event.date ?? Date()
            ends = starts.addingTimeInterval(1800)
          }
          do { teams = try await store.request("tournaments/\(event.id)/participants") } catch {
            self.error = error.localizedDescription
          }
          loading = false
        }
    }
  }
  private func save() async {
    busy = true
    defer { busy = false }
    let payload = MatchDraft(
      homeRegistrationId: home, awayRegistrationId: away,
      startsAt: ISO8601DateFormatter().string(from: starts),
      endsAt: ISO8601DateFormatter().string(from: ends), venue: venue, stage: stage, status: status,
      note: note, homeScore: status == "final" ? homeScore : nil,
      awayScore: status == "final" ? awayScore : nil, version: match?.version)
    do {
      let _: ScheduledMatch = try await store.request(
        "tournaments/\(event.id)/matches" + (match.map { "/" + $0.id } ?? ""),
        method: match == nil ? "POST" : "PUT", body: JSONEncoder().encode(payload))
      dismiss()
    } catch { self.error = error.localizedDescription }
  }
}
