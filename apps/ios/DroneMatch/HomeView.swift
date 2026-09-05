import SwiftUI

struct HomeView: View {
    @EnvironmentObject private var store: AppStore
    @State private var showTeams = false
    @State private var showEntries = false
    @State private var showGuide = false
    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment:.leading,spacing:22) {
                    HStack(spacing:9) {
                        Image(systemName:"scope").font(.title.weight(.bold)).foregroundStyle(Theme.green).accessibilityHidden(true)
                        Text("无人机足球").font(.title2.weight(.bold))
                        Spacer()
                        Label("全国赛事",systemImage:"mappin").font(.caption).foregroundStyle(.secondary)
                    }.padding(.top,8)
                    Button { store.selectedTab = 1 } label: {
                        HStack { Image(systemName:"magnifyingglass"); Text("搜索赛事名称或城市"); Spacer() }.font(.subheadline).foregroundStyle(.secondary).padding(14).background(Theme.surface,in:RoundedRectangle(cornerRadius:10))
                    }.buttonStyle(.plain)
                    if let event = store.tournaments.first { NavigationLink(value:event) { EventHero(event:event) }.buttonStyle(.plain) }
                    HStack(alignment:.top,spacing:8) {
                        quickAction("赛事报名",icon:"trophy.fill",color:Theme.green) { store.selectedTab = 1 }
                        quickAction("我的队伍",icon:"person.2.fill",color:.blue) { if store.account == nil { store.showLogin = true } else { showTeams = true } }
                        quickAction("报名记录",icon:"list.clipboard.fill",color:.orange) { if store.account == nil { store.showLogin = true } else { showEntries = true } }
                        quickAction("参赛指南",icon:"book.closed.fill",color:.purple) { showGuide = true }
                    }.padding(.vertical,2)
                    if let error = store.error { ErrorBanner(text:error) { Task { await store.refresh() } } }
                    if let entry = store.registrations.first {
                        Button { showEntries = true } label: {
                            HStack(spacing:12) {
                                Image(systemName:"bell.badge").foregroundStyle(Theme.green)
                                VStack(alignment:.leading,spacing:5) { Text("我的报名进度").font(.caption).foregroundStyle(.secondary); Text(entry.tournamentTitle).font(.subheadline.weight(.medium)).lineLimit(1).foregroundStyle(Theme.ink) }
                                Spacer(minLength:0)
                                StatusBadge(text:entry.statusLabel)
                                Image(systemName:"chevron.right").font(.caption2).foregroundStyle(.secondary)
                            }.padding(15).background(Theme.surface,in:RoundedRectangle(cornerRadius:12))
                        }.buttonStyle(.plain)
                    }
                    HStack { SectionTitle(title:"近期赛事"); Button { store.selectedTab = 1 } label: { HStack(spacing:4) { Text("全部"); Image(systemName:"chevron.right") }.font(.caption).foregroundStyle(.secondary).frame(minHeight:44) } }
                        .padding(.bottom,-14)
                    if store.isLoading && store.tournaments.isEmpty { ProgressView().frame(maxWidth:.infinity).padding(40) }
                    VStack(spacing:10) { ForEach(store.tournaments.prefix(4)) { event in NavigationLink(value:event) { EventCard(event:event) }.buttonStyle(.plain) } }
                    if store.tournaments.isEmpty && !store.isLoading && store.error == nil { ContentUnavailableView("暂无赛事",systemImage:"trophy",description:Text("新的赛事发布后会在这里展示。")) }
                }.padding(.horizontal,20).padding(.bottom,24).frame(maxWidth:680)
            }.frame(maxWidth:.infinity).background(Theme.background).toolbar(.hidden,for:.navigationBar)
                .navigationDestination(for:Tournament.self) { TournamentDetail(initial:$0) }
                .refreshable { await store.refresh() }
                .sheet(isPresented:$showTeams) { NavigationStack { TeamsView().toolbar { ToolbarItem(placement:.cancellationAction) { Button("完成") { showTeams = false } } } }.environmentObject(store) }
                .sheet(isPresented:$showEntries) { NavigationStack { RegistrationsView().toolbar { ToolbarItem(placement:.cancellationAction) { Button("完成") { showEntries = false } } } }.environmentObject(store) }
                .sheet(isPresented:$showGuide) { ParticipationGuide() }
        }
    }
    private func quickAction(_ title: String, icon: String, color: Color, action: @escaping () -> Void) -> some View {
        Button(action:action) {
            VStack(spacing:9) { Image(systemName:icon).font(.system(size:23,weight:.medium)).foregroundStyle(color).frame(width:52,height:52).background(color.opacity(0.09),in:RoundedRectangle(cornerRadius:17)); Text(title).font(.caption).foregroundStyle(Theme.ink) }.frame(maxWidth:.infinity)
        }.buttonStyle(.plain)
    }
}
struct EventsView: View {
    @EnvironmentObject private var store: AppStore
    @State private var search = ""
    @State private var category = "全部"
    @State private var openOnly = false
    private var filtered: [Tournament] { store.tournaments.filter { (category == "全部" || $0.category == category) && (!openOnly || $0.canRegister) && (search.isEmpty || ($0.title + $0.city).localizedCaseInsensitiveContains(search)) } }
    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment:.leading,spacing:18) {
                    HStack { Text("赛事").font(.largeTitle.weight(.bold)); Spacer(); Text("全国赛事").font(.subheadline).foregroundStyle(.secondary) }.padding(.top,8)
                    HStack { Image(systemName:"magnifyingglass").foregroundStyle(.secondary); TextField("搜索赛事或城市",text:$search).submitLabel(.search); if !search.isEmpty { Button("清除",systemImage:"xmark.circle.fill") { search = "" }.labelStyle(.iconOnly).foregroundStyle(.secondary).frame(minWidth:32,minHeight:32) } }.padding(.horizontal,14).frame(minHeight:48).background(Theme.surface,in:RoundedRectangle(cornerRadius:10))
                    HStack(spacing:8) { ForEach(["全部","20cm","40cm"],id:\.self) { value in Button { category = value } label: { Text(value == "全部" ? "全部级别" : value + " 级").font(.subheadline.weight(category == value ? .semibold : .regular)).padding(.horizontal,16).frame(minHeight:44).foregroundStyle(category == value ? Theme.green : .secondary).background(category == value ? Theme.green.opacity(0.09) : .clear,in:Capsule()) }.buttonStyle(.plain).accessibilityAddTraits(category == value ? .isSelected : []) } }
                    HStack { Text("共 \(filtered.count) 场赛事").font(.caption).foregroundStyle(.secondary); Spacer(); Button { openOnly.toggle() } label: { Label("可报名",systemImage:openOnly ? "checkmark.circle.fill" : "circle").font(.caption).frame(minHeight:44) }.foregroundStyle(openOnly ? Theme.green : .secondary) }.padding(.vertical,-8)
                    if let error = store.error { ErrorBanner(text:error) { Task { await store.refresh() } } }
                    if store.isLoading && store.tournaments.isEmpty { ProgressView().frame(maxWidth:.infinity).padding(40) }
                    VStack(spacing:10) { ForEach(filtered) { event in NavigationLink(value:event) { EventCard(event:event) }.buttonStyle(.plain) } }
                    if filtered.isEmpty && !store.isLoading && store.error == nil {
                        ContentUnavailableView { Label("没有符合条件的赛事",systemImage:"magnifyingglass") } description: { Text("试试其他城市、级别或赛事名称。") } actions: { Button("查看全部赛事") { search = ""; category = "全部"; openOnly = false }.buttonStyle(.bordered) }
                    }
                }.padding(.horizontal,20).padding(.bottom,24).frame(maxWidth:680)
            }.frame(maxWidth:.infinity).background(Theme.background).toolbar(.hidden,for:.navigationBar)
                .navigationDestination(for:Tournament.self) { TournamentDetail(initial:$0) }.refreshable { await store.refresh() }
        }
    }
}
struct ParticipationGuide: View {
    @Environment(\.dismiss) private var dismiss
    var body: some View {
        NavigationStack {
            List {
                Section("准备参赛") {
                    guide("1",title:"创建或确认队伍",text:"在“我的队伍”中填写队伍资料和飞手名单。队伍设备级别需要与赛事一致。")
                    guide("2",title:"阅读赛事规则",text:"确认比赛时间、地点、设备级别和报名截止时间。具体参赛条件以该场赛事规程为准。")
                    guide("3",title:"提交队伍报名",text:"选择队伍并核对飞手名单，阅读规则后提交。提交成功后可在“我的报名”查看状态。")
                    guide("4",title:"查看审核结果",text:"主办方审核通过后获得参赛名额。若未通过，请查看审核说明。报名通过不会计入比赛战绩。")
                }
                Section { Text("当前为本地开发版本，仅使用虚构的成年演示人员。正式赛事、身份验证与现场检录流程将在后续版本接入。").font(.footnote).foregroundStyle(.secondary) }
            }.navigationTitle("参赛指南").navigationBarTitleDisplayMode(.inline).toolbar { ToolbarItem(placement:.confirmationAction) { Button("完成") { dismiss() } } }
        }
    }
    private func guide(_ number:String,title:String,text:String)->some View {
        HStack(alignment:.top,spacing:14) { Text(number).font(.headline).foregroundStyle(Theme.green).frame(width:28,height:28).background(Theme.green.opacity(0.08),in:Circle()); VStack(alignment:.leading,spacing:8) { Text(title).font(.headline); Text(text).font(.subheadline).foregroundStyle(.secondary).lineSpacing(4) } }.padding(.vertical,12)
    }
}
