import SwiftUI

@main
struct DroneMatchApp: App {
    @StateObject private var store = AppStore()
    var body: some Scene {
        WindowGroup { RootView().environmentObject(store).tint(Theme.green) }
    }
}
enum Theme {
    static let green = Color(uiColor: UIColor { $0.userInterfaceStyle == .dark ? UIColor(red:0.35,green:0.86,blue:0.56,alpha:1) : UIColor(red:0,green:0.54,blue:0.275,alpha:1) })
    static let background = Color(uiColor: .systemGroupedBackground)
    static let surface = Color(uiColor: .secondarySystemGroupedBackground)
    static let ink = Color.primary
    static let heroImage = Bundle.main.url(forResource:"SoccerHero",withExtension:"jpg").flatMap { UIImage(contentsOfFile:$0.path) }
    static let hero = Color(red:0.025,green:0.25,blue:0.15)
}
struct RootView: View {
    @EnvironmentObject private var store: AppStore
    @Environment(\.scenePhase) private var phase
    var body: some View {
        TabView(selection:$store.selectedTab) {
            HomeView().tabItem { Label("首页",systemImage:"house.fill") }.tag(0)
            EventsView().tabItem { Label("赛事",systemImage:"trophy.fill") }.tag(1)
            CareerView().tabItem { Label("生涯",systemImage:"chart.bar.xaxis") }.tag(2)
            VideoView().tabItem { Label("视频",systemImage:"play.rectangle.fill") }.tag(3)
            ProfileView().tabItem { Label("我的",systemImage:"person.fill") }.tag(4)
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
        }.padding().frame(maxWidth:.infinity,alignment:.leading).background(Theme.surface,in:RoundedRectangle(cornerRadius:12))
    }
}
struct SectionTitle: View {
    let title: String
    var body: some View { Text(title).font(.title3.weight(.bold)).frame(maxWidth:.infinity,alignment:.leading) }
}
struct StatusBadge: View {
    let text: String
    private var color: Color {
        if text == "待审核" { return Color(uiColor:.systemOrange) }
        if text == "未通过" { return Color(uiColor:.systemRed) }
        if text == "报名截止" || text == "名额已满" { return .secondary }
        return Theme.green
    }
    var body: some View {
        Text(text).font(.caption.weight(.medium)).padding(.horizontal,8).padding(.vertical,4).foregroundStyle(color).background(color.opacity(0.10),in:RoundedRectangle(cornerRadius:5))
    }
}
struct ClubAvatar: View {
    let name: String
    var size: CGFloat = 48
    var body: some View {
        Text(String(name.prefix(1))).font(.system(size:size * 0.4,weight:.bold)).foregroundStyle(Theme.green)
            .frame(width:size,height:size).background(Theme.green.opacity(0.1),in:RoundedRectangle(cornerRadius:size * 0.28))
            .accessibilityHidden(true)
    }
}
struct EventCard: View {
    let event: Tournament
    var body: some View {
        HStack(alignment:.top,spacing:14) {
            VStack(spacing:5) {
                Text(event.monthLabel).font(.caption.weight(.medium))
                Text(event.dayLabel).font(.system(size:30,weight:.bold,design:.rounded)).monospacedDigit()
                Text(event.category).font(.caption2.weight(.medium)).padding(.top,2)
            }.foregroundStyle(Theme.green).frame(width:76).padding(.vertical,12)
                .background(Theme.green.opacity(0.07),in:RoundedRectangle(cornerRadius:10)).accessibilityElement(children:.ignore).accessibilityLabel(event.dateLabel)
            VStack(alignment:.leading,spacing:8) {
                Text(event.title).font(.system(.subheadline).weight(.semibold)).foregroundStyle(Theme.ink).multilineTextAlignment(.leading).fixedSize(horizontal:false,vertical:true)
                Text("\(event.city)  ·  \(event.venue)").font(.caption).foregroundStyle(.secondary).lineLimit(1)
                HStack(spacing:6) {
                    StatusBadge(text:event.canRegister ? "报名中" : event.status == "closed" ? "报名截止" : "名额已满")
                    Spacer(minLength:0)
                    Text("\(event.approved)/\(event.capacity) 队").font(.caption).foregroundStyle(.secondary)
                }
            }.padding(.vertical,3)
        }.padding(16).frame(maxWidth:.infinity,alignment:.leading).background(Theme.surface,in:RoundedRectangle(cornerRadius:14))
    }
}
struct EventHero: View {
    let event: Tournament
    var body: some View {
        ZStack(alignment:.bottomLeading) {
            GeometryReader { geometry in
                if let image = Theme.heroImage { Image(uiImage:image).resizable().scaledToFill().frame(width:geometry.size.width,height:geometry.size.height).clipped() }
            }
            LinearGradient(colors:[.clear,.black.opacity(0.65)],startPoint:.center,endPoint:.bottom)
            VStack(alignment:.leading,spacing:10) {
                Text("赛事推荐").font(.caption.weight(.semibold)).padding(.horizontal,9).padding(.vertical,5).background(.white.opacity(0.18),in:Capsule())
                Spacer(minLength:20)
                Text(event.title).font(.title3.weight(.bold)).lineLimit(2).multilineTextAlignment(.leading)
                HStack { Text("\(event.city)  ·  \(event.dateLabel)").font(.caption); Spacer(); Image(systemName:"arrow.up.right").font(.subheadline.weight(.semibold)) }
            }.foregroundStyle(.white).padding(20)
        }.frame(height:226).background(Theme.hero).clipShape(RoundedRectangle(cornerRadius:16))
    }
}
