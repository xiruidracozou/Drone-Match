import SwiftUI

struct TournamentDetail: View {
    @EnvironmentObject private var store: AppStore
    let initial: Tournament
    @State private var showRegistration = false
    @State private var selectedSection = "赛事介绍"
    private var event: Tournament { store.tournaments.first { $0.id == initial.id } ?? initial }
    private var ownEntry: Registration? { store.registrations.first { $0.tournamentId == event.id } }
    var body: some View {
        ScrollView {
            VStack(alignment:.leading,spacing:24) {
                VStack(alignment:.leading,spacing:20) {
                    HStack { Text("\(event.category) 级 · 成人演示组").font(.caption); Spacer(); Text(event.canRegister ? "报名中" : "报名结束").font(.caption.weight(.bold)) }
                    Text(event.title).font(.title.weight(.bold)).fixedSize(horizontal:false,vertical:true)
                    Label(event.dateLabel,systemImage:"calendar").font(.subheadline)
                    Label(event.city + " · " + event.venue,systemImage:"mappin.and.ellipse").font(.subheadline)
                }.padding(24).frame(maxWidth:.infinity,alignment:.leading).foregroundStyle(.white).background(Theme.hero,in:RoundedRectangle(cornerRadius:20))
                HStack { fact("报名费用",value:"免费"); Spacer(); fact("参赛名额",value:"\(event.approved)/\(event.capacity) 队"); Spacer(); fact("设备级别",value:event.category) }.padding(20).background(Theme.surface,in:RoundedRectangle(cornerRadius:16))
                Picker("详情栏目",selection:$selectedSection) { Text("赛事介绍").tag("赛事介绍"); Text("报名规则").tag("报名规则") }.pickerStyle(.segmented)
                if selectedSection == "赛事介绍" {
                    SectionTitle(title:"关于这场比赛")
                    Text(event.description).font(.body).lineSpacing(7)
                    Divider()
                    fact("主办机构",value:event.organizerName)
                    fact("报名截止",value:Tournament.formatDate(event.deadline))
                    Label("提交申请不等于获得参赛资格，审核通过后占用正式名额。",systemImage:"info.circle").font(.footnote).foregroundStyle(.secondary)
                } else {
                    SectionTitle(title:"报名规则与须知")
                    Text(event.rules).font(.body).lineSpacing(7)
                }
                if let entry = ownEntry { VStack(alignment:.leading,spacing:12) { StatusBadge(text:entry.statusLabel); Text("\(entry.teamName)已提交报名").font(.headline); if !entry.reviewNote.isEmpty { Text(entry.reviewNote).font(.subheadline).foregroundStyle(.secondary) } }.padding(20).frame(maxWidth:.infinity,alignment:.leading).background(Theme.surface,in:RoundedRectangle(cornerRadius:16)) }
            }.padding(20).frame(maxWidth:680)
        }.frame(maxWidth:.infinity).background(Theme.background).navigationTitle("赛事详情").navigationBarTitleDisplayMode(.inline)
            .safeAreaInset(edge:.bottom) {
                Button {
                    if store.account == nil { store.showLogin = true }
                    else if ownEntry != nil { store.selectedTab = 4 }
                    else { showRegistration = true }
                } label: { Text(ownEntry != nil ? "查看我的报名" : store.account == nil ? "登录后报名" : "立即报名").font(.headline).frame(maxWidth:.infinity).padding(.vertical,10) }
                .buttonStyle(.borderedProminent).disabled(ownEntry == nil && !event.canRegister).padding(.horizontal,20).padding(.vertical,12).background(.regularMaterial)
            }
            .sheet(isPresented:$showRegistration) { RegistrationSheet(event:event).environmentObject(store) }
            .refreshable { await store.refresh() }
    }
    private func fact(_ title:String,value:String)->some View { VStack(alignment:.leading,spacing:8) { Text(title).font(.caption).foregroundStyle(.secondary); Text(value).font(.subheadline.weight(.semibold)) } }
}
struct RegistrationSheet: View {
    @EnvironmentObject private var store: AppStore
    @Environment(\.dismiss) private var dismiss
    let event: Tournament
    @State private var teamID = ""
    @State private var accepted = false
    @State private var busy = false
    @State private var error: String?
    @State private var success = false
    private var compatibleTeams: [Team] { store.teams.filter { $0.category == event.category } }
    var body: some View {
        NavigationStack {
            Form {
                Section { Text(event.title).font(.headline); Text("\(event.category) 级 · 免费报名").foregroundStyle(.secondary) }
                if success { Section { Label("报名已提交",systemImage:"checkmark.circle.fill").foregroundStyle(Theme.green); Text("请在“我的报名”中查看审核进度。"); Button("完成") { dismiss() } } }
                else if compatibleTeams.isEmpty { Section { ContentUnavailableView("还没有合适的队伍",systemImage:"person.3",description:Text("请先在“我的队伍”创建 \(event.category) 级队伍，再提交报名。")) } }
                else {
                    Section("选择参赛队伍") {
                        Picker("队伍",selection:$teamID) { Text("请选择队伍").tag(""); ForEach(compatibleTeams) { Text($0.name).tag($0.id) } }
                        if let team = compatibleTeams.first(where:{ $0.id == teamID }) { ForEach(team.roster,id:\.self) { Label($0,systemImage:"person") }.font(.subheadline) }
                    }
                    Section("确认报名") { Text(event.rules).font(.footnote).foregroundStyle(.secondary); Toggle("已阅读规则并确认当前名单",isOn:$accepted) }
                    if let error { Section { Text(error).foregroundStyle(.red) } }
                    Section { Button { Task { await submit() } } label: { HStack { Spacer(); if busy { ProgressView() }; Text("提交报名"); Spacer() } }.disabled(teamID.isEmpty || !accepted || busy) }
                }
            }.navigationTitle("赛事报名").navigationBarTitleDisplayMode(.inline).toolbar { ToolbarItem(placement:.cancellationAction) { Button("关闭") { dismiss() }.disabled(busy) } }.interactiveDismissDisabled(busy)
        }
    }
    private func submit() async {
        busy = true
        defer { busy = false }
        do { let _ = try await store.submit(tournamentID:event.id,teamID:teamID); success = true }
        catch { self.error = error.localizedDescription }
    }
}
