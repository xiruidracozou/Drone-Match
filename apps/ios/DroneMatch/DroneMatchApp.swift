import SwiftUI

@main
struct DroneMatchApp: App {
  @StateObject private var store = AppStore()
  var body: some Scene {
    WindowGroup { RootView().environmentObject(store).tint(Theme.green) }
  }
}

enum Theme {
  static let green = Color(
    uiColor: UIColor { traits in
      traits.userInterfaceStyle == .dark
        ? UIColor(red: 0.35, green: 0.86, blue: 0.56, alpha: 1)
        : UIColor(red: 0, green: 0.46, blue: 0.25, alpha: 1)
    })
  static let background = Color(uiColor: .systemGroupedBackground)
  static let surface = Color(uiColor: .secondarySystemGroupedBackground)
  static let page = Color(uiColor: .systemBackground)
}

struct RootView: View {
  @EnvironmentObject private var store: AppStore
  @Environment(\.scenePhase) private var phase
  var body: some View {
    TabView(selection: $store.selectedTab) {
      EventsView().tabItem { Label("赛事", systemImage: "trophy") }.tag(0)
      NavigationStack { TeamsView() }
        .tabItem { Label("队伍", systemImage: "person.2") }.tag(1)
      ProfileView().tabItem { Label("我的", systemImage: "person.crop.circle") }.tag(2)
    }
    .task { await store.refresh() }
    .onChange(of: phase) { _, value in
      if value == .active { Task { await store.refresh() } }
    }
    .sheet(isPresented: $store.showLogin) { LoginView() }
  }
}

struct SyncNotice: View {
  @EnvironmentObject private var store: AppStore
  var body: some View {
    if let error = store.error {
      VStack(alignment: .leading, spacing: 8) {
        Label(error, systemImage: "wifi.exclamationmark")
          .font(.footnote.weight(.medium))
        if let updated = store.lastUpdated {
          Text("当前显示上次数据，更新于 \(updated.formatted(date: .abbreviated, time: .shortened))")
            .font(.caption).foregroundStyle(.secondary)
        } else {
          Text("数据尚未加载完成，请重试。").font(.caption).foregroundStyle(.secondary)
        }
        Button {
          Task { await store.refresh() }
        } label: {
          if store.isLoading { ProgressView() } else { Text("重新加载") }
        }.font(.subheadline).frame(minHeight: 44).disabled(store.isLoading)
      }
      .frame(maxWidth: .infinity, alignment: .leading)
      .padding(14).background(Theme.green.opacity(0.06), in: RoundedRectangle(cornerRadius: 10))
    }
  }
}

struct StatusBadge: View {
  let text: String
  private var color: Color {
    switch text {
    case "待审核": return Color(uiColor: .systemOrange)
    case "未通过": return Color(uiColor: .systemRed)
    case "报名截止", "名额已满": return .secondary
    default: return Theme.green
    }
  }
  var body: some View {
    HStack(spacing: 5) {
      Circle().fill(color).frame(width: 5, height: 5)
      Text(text).font(.caption.weight(.medium)).foregroundStyle(color)
    }.accessibilityElement(children: .ignore).accessibilityLabel(text)
  }
}

struct ClubAvatar: View {
  let name: String
  var size: CGFloat = 48
  var body: some View {
    Text(String(name.prefix(1)))
      .font(.system(size: size * 0.4, weight: .bold))
      .foregroundStyle(Theme.green)
      .frame(width: size, height: size)
      .background(Theme.green.opacity(0.08), in: RoundedRectangle(cornerRadius: 12))
      .accessibilityHidden(true)
  }
}

struct EventRow: View {
  let event: Tournament
  var body: some View {
    HStack(alignment: .top, spacing: 18) {
      VStack(spacing: 4) {
        Text(event.dayLabel).font(.system(size: 28, weight: .semibold, design: .rounded))
        Text(event.weekdayLabel).font(.caption).foregroundStyle(.secondary)
      }
      .frame(width: 40).accessibilityElement(children: .ignore)
      .accessibilityLabel(event.dateLabel)
      VStack(alignment: .leading, spacing: 9) {
        Text(event.title).font(.headline).foregroundStyle(.primary)
          .fixedSize(horizontal: false, vertical: true)
        Text(event.city + " · " + event.venue)
          .font(.subheadline).foregroundStyle(.secondary)
          .fixedSize(horizontal: false, vertical: true)
        ViewThatFits(in: .horizontal) {
          HStack {
            Text(event.category + " 级")
            Spacer(minLength: 12)
            StatusBadge(text: event.statusLabel)
          }
          VStack(alignment: .leading, spacing: 8) {
            Text(event.category + " 级")
            StatusBadge(text: event.statusLabel)
          }
        }.font(.caption).foregroundStyle(.secondary)
      }
    }
    .padding(.vertical, 20).frame(maxWidth: .infinity, alignment: .leading)
    .contentShape(Rectangle())
  }
}

struct RegistrationRow: View {
  let entry: Registration
  var body: some View {
    VStack(alignment: .leading, spacing: 10) {
      HStack {
        StatusBadge(text: entry.statusLabel)
        Spacer()
        Text(Tournament.formatDate(entry.createdAt)).font(.caption).foregroundStyle(.secondary)
      }
      Text(entry.tournamentTitle).font(.headline).foregroundStyle(.primary)
      Text(entry.teamName + " · " + entry.category + " 级").font(.subheadline).foregroundStyle(
        .secondary)
    }.padding(.vertical, 8)
  }
}
