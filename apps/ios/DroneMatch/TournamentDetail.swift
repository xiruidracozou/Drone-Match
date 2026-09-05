import SwiftUI

struct TournamentDetail: View {
    @EnvironmentObject private var store: AppStore
    let initial: Tournament
    @State private var showRegistration = false
    @State private var showEntries = false
    @State private var selectedSection = "赛事介绍"
    private var event: Tournament { store.tournaments.first { $0.id == initial.id } ?? initial }
    private var ownEntry: Registration? { store.registrations.first { $0.tournamentId == event.id } }
    var body: some View {
        ScrollView {
            VStack(alignment:.leading,spacing:16) {
                VStack(alignment:.leading,spacing:0) {
                    GeometryReader { geo in if let image = Theme.heroImage { Image(uiImage:image).resizable().scaledToFill().frame(width:geo.size.width,height:180).clipped() } }.frame(height:180).background(Theme.hero)
                    VStack(alignment:.leading,spacing:16) {
                        HStack { StatusBadge(text:event.canRegister ? "报名中" : event.status == "closed" ? "报名截止" : "名额已满"); Text(event.category + " 级").font(.caption).foregroundStyle(.secondary); Spacer(); Text("成人演示组").font(.caption).foregroundStyle(.secondary) }
                        Text(event.title).font(.title2.weight(.bold)).fixedSize(horizontal:false,vertical:true)
                        Label(event.dateLabel,systemImage:"calendar").font(.subheadline)
                        Label(event.city + "  " + event.venue,systemImage:"mappin.and.ellipse").font(.subheadline).foregroundStyle(.secondary)
                        Divider()
                        HStack { fact("报名费用",value:"免费"); Spacer(); fact("已通过队伍",value:"\(event.approved) / \(event.capacity)"); Spacer(); fact("报名截止",value:Tournament.formatDate(event.deadline)) }
                    }.padding(20)
                }.background(Theme.surface,in:RoundedRectangle(cornerRadius:16)).clipShape(RoundedRectangle(cornerRadius:16))
                if let entry = ownEntry {
                    HStack(alignment:.top,spacing:12) {
                        Image(systemName:entry.status == "approved" ? "checkmark.seal.fill" : "list.clipboard").font(.title2).foregroundStyle(Theme.green)
                        VStack(alignment:.leading,spacing:8) { HStack { Text(entry.teamName).font(.headline); Spacer(); StatusBadge(text:entry.statusLabel) }; Text(entry.reviewNote.isEmpty ? "报名已提交，可在报名记录中查看处理进度。" : entry.reviewNote).font(.footnote).foregroundStyle(.secondary) }
                    }.padding(18).background(Theme.surface,in:RoundedRectangle(cornerRadius:14))
                }
                VStack(alignment:.leading,spacing:20) {
                    HStack(spacing:26) {
                        ForEach(["赛事介绍","报名规则"],id:\.self) { section in
                            Button { selectedSection = section } label: {
                                VStack(spacing:12) { Text(section).font(.subheadline.weight(selectedSection == section ? .bold : .regular)); Capsule().fill(selectedSection == section ? Theme.green : .clear).frame(height:3) }.fixedSize(horizontal:true,vertical:false)
                            }.foregroundStyle(selectedSection == section ? Theme.green : .secondary).buttonStyle(.plain).frame(minHeight:44)
                        }
                        Spacer()
                    }
                    if selectedSection == "赛事介绍" {
                        Text(event.description).font(.subheadline).lineSpacing(6)
                        Divider()
                        fact("主办机构",value:event.organizerName)
                        Label("审核通过后获得正式参赛名额。",systemImage:"info.circle").font(.footnote).foregroundStyle(.secondary)
                    } else { Text(event.rules).font(.subheadline).lineSpacing(6) }
                }.padding(20).frame(maxWidth:.infinity,alignment:.leading).background(Theme.surface,in:RoundedRectangle(cornerRadius:14))
            }.padding(16).frame(maxWidth:680)
        }.frame(maxWidth:.infinity).background(Theme.background).navigationTitle("赛事详情").navigationBarTitleDisplayMode(.inline).toolbar(.hidden,for:.tabBar)
            .safeAreaInset(edge:.bottom) {
                HStack(spacing:24) {
                    VStack(alignment:.leading,spacing:4) { Text("报名费用").font(.caption).foregroundStyle(.secondary); Text("免费").font(.headline).foregroundStyle(Theme.green) }
                    Button {
                        if store.account == nil { store.showLogin = true }
                        else if ownEntry != nil { showEntries = true }
                        else { showRegistration = true }
                    } label: { Text(ownEntry != nil ? "查看我的报名" : !event.canRegister ? "报名已结束" : store.account == nil ? "登录后报名" : "立即报名").font(.headline).frame(maxWidth:.infinity).padding(.vertical,10) }
                    .buttonStyle(.borderedProminent).disabled(ownEntry == nil && !event.canRegister)
                }.padding(.horizontal,20).padding(.vertical,12).background(.regularMaterial)
            }
            .sheet(isPresented:$showRegistration) { RegistrationSheet(event:event).environmentObject(store) }
            .sheet(isPresented:$showEntries) { NavigationStack { RegistrationsView().toolbar { ToolbarItem(placement:.cancellationAction) { Button("完成") { showEntries = false } } } }.environmentObject(store) }
            .refreshable { await store.refresh() }
    }
    private func fact(_ title:String,value:String)->some View { VStack(alignment:.leading,spacing:7) { Text(title).font(.caption).foregroundStyle(.secondary); Text(value).font(.subheadline.weight(.semibold)).fixedSize(horizontal:false,vertical:true) } }
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
