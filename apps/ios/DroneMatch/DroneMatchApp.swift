import SwiftUI

@main
struct DroneMatchApp: App {
    @StateObject private var store = AppStore()
    var body: some Scene {
        WindowGroup {
            RootView().environmentObject(store).tint(Theme.green)
        }
    }
}
enum Theme {
    static let green = Color(uiColor: UIColor { $0.userInterfaceStyle == .dark ? UIColor(red:0.43,green:0.82,blue:0.56,alpha:1) : UIColor(red:0.08,green:0.43,blue:0.27,alpha:1) })
    static let background = Color(uiColor: .systemGroupedBackground)
    static let surface = Color(uiColor: .secondarySystemGroupedBackground)
    static let ink = Color.primary
    static let hero = Color(red:0.08,green:0.27,blue:0.19)
}
struct RootView: View {
    @EnvironmentObject private var store: AppStore
    @Environment(\.scenePhase) private var phase
    var body: some View {
        TabView(selection:$store.selectedTab) {
            HomeView().tabItem { Label("首页",systemImage:"house") }.tag(0)
            EventsView().tabItem { Label("赛事",systemImage:"trophy") }.tag(1)
            CareerView().tabItem { Label("生涯",systemImage:"chart.bar.xaxis") }.tag(2)
            VideoView().tabItem { Label("视频",systemImage:"play.rectangle") }.tag(3)
            ProfileView().tabItem { Label("我的",systemImage:"person.crop.circle") }.tag(4)
        }
        .task { await store.refresh() }
        .onChange(of:phase) { _, value in if value == .active { Task { await store.refresh() } } }
        .sheet(isPresented:$store.showLogin) { LoginView().environmentObject(store) }
    }
}
struct ErrorBanner: View {
    let text: String
    let retry: () -> Void
    var body: some View {
        VStack(alignment:.leading,spacing:10) {
            Label(text,systemImage:"exclamationmark.circle").font(.subheadline)
            Button("重新加载",action:retry).buttonStyle(.bordered)
        }.padding().frame(maxWidth:.infinity,alignment:.leading).background(Theme.surface,in:RoundedRectangle(cornerRadius:16))
    }
}
struct SectionTitle: View {
    let title: String
    var body: some View { Text(title).font(.title3.weight(.bold)).frame(maxWidth:.infinity,alignment:.leading) }
}
struct StatusBadge: View {
    let text: String
    var body: some View {
        Text(text).font(.caption.weight(.semibold)).padding(.horizontal,10).padding(.vertical,5).foregroundStyle(Theme.green).background(Theme.green.opacity(0.1),in:Capsule())
    }
}
struct EventCard: View {
    let event: Tournament
    var body: some View {
        VStack(alignment:.leading,spacing:0) {
            ZStack(alignment:.leading) {
                (event.category == "40cm" ? Color(red:0.27,green:0.38,blue:0.40) : Theme.hero)
                HStack {
                    VStack(alignment:.leading,spacing:16) {
                        Text("DRONE SOCCER / \(event.category)").font(.system(.caption2,design:.rounded).weight(.medium)).tracking(1)
                        Text(event.city + "飞行赛事").font(.title2.weight(.bold))
                        Text(event.dateLabel).font(.caption)
                    }
                    Spacer()
                    Image(systemName:"sportscourt").font(.system(size:64,weight:.ultraLight)).opacity(0.55).accessibilityHidden(true)
                }.foregroundStyle(.white).padding(22)
            }.frame(minHeight:150)
            VStack(alignment:.leading,spacing:12) {
                HStack { StatusBadge(text:event.canRegister ? "报名中" : event.status == "closed" ? "报名截止" : "名额已满"); Spacer(); Text("免费报名").font(.caption).foregroundStyle(.secondary) }
                Text(event.title).font(.headline).foregroundStyle(Theme.ink).multilineTextAlignment(.leading)
                Label(event.venue,systemImage:"mappin.and.ellipse").font(.caption).foregroundStyle(.secondary)
                Divider()
                HStack { Text("\(event.approved) / \(event.capacity) 队已通过").font(.caption).foregroundStyle(.secondary); Spacer(); Label("查看赛事",systemImage:"arrow.right").font(.caption.weight(.medium)).foregroundStyle(Theme.green) }
            }.padding(18).background(Theme.surface)
        }.clipShape(RoundedRectangle(cornerRadius:20)).overlay(RoundedRectangle(cornerRadius:20).stroke(.primary.opacity(0.04)))
    }
}
