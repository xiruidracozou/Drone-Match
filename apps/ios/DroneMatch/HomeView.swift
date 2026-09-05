import SwiftUI

struct HomeView: View {
    @EnvironmentObject private var store: AppStore
    @State private var showTeams = false
    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment:.leading,spacing:24) {
                    HStack { Label("DRONE MATCH",systemImage:"bolt.horizontal.circle.fill").font(.system(.subheadline,design:.rounded).weight(.bold)).tracking(1); Spacer(); Text("无人机足球").font(.caption).foregroundStyle(.secondary) }.foregroundStyle(Theme.green)
                    VStack(alignment:.leading,spacing:10) {
                        Text("让热爱，\n在空中相遇。").font(.system(.largeTitle,design:.rounded).weight(.bold))
                        Text("连接飞手、俱乐部与每一场精彩赛事。 ").font(.subheadline).foregroundStyle(.secondary)
                    }
                    HStack(spacing:14) {
                        quickAction("发现赛事",subtitle:"下一场，一起出发",icon:"trophy") { store.selectedTab = 1 }
                        quickAction("我的队伍",subtitle:"和队友一起飞行",icon:"person.3") { if store.account == nil { store.showLogin = true } else { showTeams = true } }
                    }
                    if let error = store.error { ErrorBanner(text:error) { Task { await store.refresh() } } }
                    HStack { SectionTitle(title:"精选赛事"); Button("查看全部") { store.selectedTab = 1 }.font(.subheadline).frame(minHeight:44) }
                    if store.isLoading && store.tournaments.isEmpty { ProgressView().frame(maxWidth:.infinity).padding(40) }
                    ForEach(store.tournaments.prefix(3)) { event in NavigationLink(value:event) { EventCard(event:event) }.buttonStyle(.plain) }
                    if store.tournaments.isEmpty && !store.isLoading && store.error == nil { ContentUnavailableView("暂无赛事",systemImage:"trophy",description:Text("新的赛事发布后会在这里展示。")) }
                    HStack(spacing:12) { Image(systemName:"checkmark.shield").font(.title2).foregroundStyle(Theme.green); VStack(alignment:.leading,spacing:5) { Text("每一次参与，都值得记录").font(.subheadline.weight(.semibold)); Text("从报名出发，积累属于你的飞行旅程。").font(.caption).foregroundStyle(.secondary) } }.padding(20).frame(maxWidth:.infinity,alignment:.leading).background(Theme.surface,in:RoundedRectangle(cornerRadius:18))
                }.padding(20).frame(maxWidth:680)
            }.frame(maxWidth:.infinity).background(Theme.background).toolbar(.hidden,for:.navigationBar)
                .navigationDestination(for:Tournament.self) { TournamentDetail(initial:$0) }
                .refreshable { await store.refresh() }
                .sheet(isPresented:$showTeams) { NavigationStack { TeamsView().toolbar { ToolbarItem(placement:.cancellationAction) { Button("完成") { showTeams = false } } } }.environmentObject(store) }
        }
    }
    private func quickAction(_ title: String, subtitle: String, icon: String, action: @escaping () -> Void) -> some View {
        Button(action:action) { VStack(alignment:.leading,spacing:10) { Image(systemName:icon).font(.title2).foregroundStyle(Theme.green); Text(title).font(.subheadline.weight(.semibold)).foregroundStyle(Theme.ink); Text(subtitle).font(.caption2).foregroundStyle(.secondary) }.frame(maxWidth:.infinity,alignment:.leading).padding(18).background(Theme.surface,in:RoundedRectangle(cornerRadius:18)) }.buttonStyle(.plain)
    }
}
struct EventsView: View {
    @EnvironmentObject private var store: AppStore
    @State private var search = ""
    @State private var category = "全部"
    private var filtered: [Tournament] { store.tournaments.filter { (category == "全部" || $0.category == category) && (search.isEmpty || ($0.title + $0.city).localizedCaseInsensitiveContains(search)) } }
    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing:20) {
                    Picker("设备级别",selection:$category) { Text("全部赛事").tag("全部"); Text("20cm 级").tag("20cm"); Text("40cm 级").tag("40cm") }.pickerStyle(.segmented)
                    if let error = store.error { ErrorBanner(text:error) { Task { await store.refresh() } } }
                    ForEach(filtered) { event in NavigationLink(value:event) { EventCard(event:event) }.buttonStyle(.plain) }
                    if filtered.isEmpty && !store.isLoading { ContentUnavailableView.search(text:search) }
                }.padding(20).frame(maxWidth:680)
            }.frame(maxWidth:.infinity).background(Theme.background).navigationTitle("赛事").searchable(text:$search,prompt:"搜索赛事或城市")
                .navigationDestination(for:Tournament.self) { TournamentDetail(initial:$0) }.refreshable { await store.refresh() }
        }
    }
}
