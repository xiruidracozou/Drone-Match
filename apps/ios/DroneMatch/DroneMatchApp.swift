import SwiftUI

@main
struct DroneMatchApp: App {
  @StateObject private var store = AppStore()
  var body: some Scene {
    WindowGroup { RootView().environmentObject(store).tint(Theme.accent) }
  }
}

enum Theme {
  static let accent = Color(
    uiColor: UIColor { traits in
      traits.userInterfaceStyle == .dark
        ? UIColor(red: 0.48, green: 0.67, blue: 1, alpha: 1)
        : UIColor(red: 0.14, green: 0.36, blue: 0.96, alpha: 1)
    })
  static let solidAccent = Color(red: 0.14, green: 0.36, blue: 0.96)
  static let onAccent = Color.white
  static let background = Color(uiColor: .systemGroupedBackground)
  static let surface = Color(uiColor: .secondarySystemGroupedBackground)
  static let navy = Color(red: 0.063, green: 0.165, blue: 0.337)
  static let ice = Color(red: 0.918, green: 0.945, blue: 1)
  static let page = Color(uiColor: .systemBackground)
}

struct RootView: View {
  @EnvironmentObject private var store: AppStore
  @Environment(\.scenePhase) private var phase
  @AppStorage("appearance") private var appearance = "system"
  var body: some View {
    TabView(selection: $store.selectedTab) {
      DiscoveryView().tabItem { Label("首页", systemImage: "house") }.tag(3)
      EventsView().tabItem { Label("赛事", systemImage: "trophy") }.tag(0)
      CareerView().tabItem { Label("生涯", systemImage: "person.crop.rectangle") }.tag(1)
      VideoLibraryView().tabItem { Label("视频", systemImage: "play.rectangle") }.tag(4)
      ProfileView().tabItem { Label("我的", systemImage: "person.crop.circle") }.badge(
        store.unreadCount
      ).tag(2)
    }
    .preferredColorScheme(appearance == "light" ? .light : appearance == "dark" ? .dark : nil)
    .task(id: phase) {
      guard phase == .active else { return }
      while !Task.isCancelled {
        await store.refresh()
        do { try await Task.sleep(for: .seconds(20)) } catch { return }
      }
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
      .padding(16).background(Theme.accent.opacity(0.06), in: RoundedRectangle(cornerRadius: 12))
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
    default: return Theme.accent
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
      .font(.system(size: size * 0.36, weight: .semibold))
      .foregroundStyle(Theme.accent)
      .frame(width: size, height: size)
      .background(Theme.accent.opacity(0.08), in: Circle())
      .accessibilityHidden(true)
  }
}

struct EventRow: View {
  @Environment(\.dynamicTypeSize) private var typeSize
  let event: Tournament
  var showsMonth = false
  var body: some View {
    (typeSize.isAccessibilitySize
      ? AnyLayout(VStackLayout(alignment: .leading, spacing: 16))
      : AnyLayout(HStackLayout(alignment: .top, spacing: 16))) {
        (typeSize.isAccessibilitySize
          ? AnyLayout(HStackLayout(spacing: 12)) : AnyLayout(VStackLayout(spacing: 4))) {
            if showsMonth {
              Text(event.monthLabel).font(TypeScale.caption).foregroundStyle(.secondary)
            }
            Text(event.dayLabel).font(TypeScale.title).monospacedDigit()
            Text(event.weekdayLabel).font(.caption).foregroundStyle(.secondary)
          }
          .fixedSize().frame(width: typeSize.isAccessibilitySize ? nil : 40).accessibilityElement(
            children: .ignore
          )
          .accessibilityLabel(event.dateLabel)
        VStack(alignment: .leading, spacing: 8) {
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
    VStack(alignment: .leading, spacing: 12) {
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
