import CoreLocation
import SwiftUI

@MainActor
final class CityLocator: NSObject, ObservableObject, @preconcurrency CLLocationManagerDelegate {
  @Published private(set) var locating = false
  @Published private(set) var city: String?
  @Published private(set) var district: String?
  @Published private(set) var message: String?
  @Published private(set) var denied = false
  private let manager = CLLocationManager()
  private let geocoder = CLGeocoder()
  private var timeout: Task<Void, Never>?
  private var requestID = UUID()
  override init() {
    super.init()
    manager.delegate = self
    manager.desiredAccuracy = kCLLocationAccuracyThreeKilometers
  }
  func locate() {
    cancel()
    city = nil
    district = nil
    message = nil
    denied = false
    locating = true
    switch manager.authorizationStatus {
    case .notDetermined: manager.requestWhenInUseAuthorization()
    case .authorizedWhenInUse, .authorizedAlways: requestFix()
    default: unavailable()
    }
  }
  func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
    guard locating else { return }
    switch manager.authorizationStatus {
    case .authorizedWhenInUse, .authorizedAlways: requestFix()
    case .denied, .restricted: unavailable()
    default: break
    }
  }
  private func requestFix() {
    timeout?.cancel()
    timeout = Task { [weak self] in
      do { try await Task.sleep(for: .seconds(20)) } catch { return }
      guard let self else { return }
      self.cancel()
      self.message = "暂时无法获取位置，可以重新定位或手动选择城市。"
    }
    manager.requestLocation()
  }
  private func unavailable() {
    cancel()
    denied = true
    message = "定位未开启，仍可手动选择城市。"
  }
  func cancel() {
    requestID = UUID()
    timeout?.cancel()
    timeout = nil
    manager.stopUpdatingLocation()
    geocoder.cancelGeocode()
    locating = false
  }
  func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
    guard locating, let location = locations.last else { return }
    let id = requestID
    Task {
      do {
        let places = try await geocoder.reverseGeocodeLocation(
          location, preferredLocale: Locale(identifier: "zh_CN"))
        guard id == requestID, locating else { return }
        timeout?.cancel()
        locating = false
        guard let place = places.first, let name = place.locality ?? place.administrativeArea else {
          message = "没有识别到城市，请手动选择。"
          return
        }
        let normalized = BrowseCity.normalized(name)
        guard BrowseCity.catalog.contains(where: { $0.name == normalized }) else {
          message = "定位城市暂不在目录内，可选择其他城市或浏览全国内容。"
          return
        }
        city = normalized
        district = place.subLocality
      } catch {
        guard id == requestID else { return }
        cancel()
        message = "位置解析失败，请重新定位或手动选择城市。"
      }
    }
  }
  func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
    guard locating else { return }
    if manager.authorizationStatus == .denied {
      unavailable()
      return
    }
    cancel()
    message = "暂时无法获取位置，可以重新定位或手动选择城市。"
  }
}

struct CitySelection: View {
  @Environment(\.dynamicTypeSize) private var typeSize
  @EnvironmentObject private var store: AppStore
  @Environment(\.dismiss) private var dismiss
  @AppStorage("selectedCity") private var selectedCity = "全国"
  @AppStorage("recentBrowseCities") private var recentJSON = "[]"
  @StateObject private var locator = CityLocator()
  @State private var query = ""
  @State private var directoryCities: [String] = []
  private var recent: [String] {
    (try? JSONDecoder().decode([String].self, from: Data(recentJSON.utf8))) ?? []
  }
  private var available: [String] {
    Array(Set(store.tournaments.map(\.city) + directoryCities)).sorted()
  }
  var body: some View {
    NavigationStack {
      List {
        if query.isEmpty {
          Section {
            (typeSize.isAccessibilitySize
              ? AnyLayout(VStackLayout(alignment: .leading, spacing: 8))
              : AnyLayout(HStackLayout())) {
                VStack(alignment: .leading, spacing: 8) {
                  Text("当前浏览").font(.caption).foregroundStyle(.secondary)
                  Text(selectedCity).font(.title2.weight(.semibold))
                }
                Spacer()
                Button("全国") { select("全国") }.frame(minHeight: 44)
                  .accessibilityLabel("浏览全国内容")
              }
          }
          Section("定位当前位置") {
            Button {
              locator.locate()
            } label: {
              HStack(spacing: 12) {
                if locator.locating { ProgressView() } else { Image(systemName: "location.fill") }
                Text(locator.locating ? "正在定位…" : locator.city == nil ? "使用当前位置" : "重新定位")
              }.frame(minHeight: 44)
            }.disabled(locator.locating)
            if let city = locator.city {
              Button {
                select(city)
              } label: {
                VStack(alignment: .leading, spacing: 8) {
                  Text("定位到：" + city + (locator.district.map { " · " + $0 } ?? ""))
                    .foregroundStyle(.primary)
                  Text(city == selectedCity ? "继续浏览该城市" : "切换到" + city).font(.subheadline)
                }.padding(.vertical, 8)
              }
            }
            if let message = locator.message {
              Text(message).font(.subheadline).foregroundStyle(.secondary)
            }
            if locator.denied {
              Button("前往系统设置") {
                if let url = URL(string: UIApplication.openSettingsURLString) {
                  UIApplication.shared.open(url)
                }
              }.frame(minHeight: 44)
            }
          }
          if !recent.isEmpty { citySection("最近选择", values: recent) }
          if !available.isEmpty { citySection("有赛事或俱乐部的城市", values: available) }
          Section {
            Text("首页、赛事、招募和俱乐部按所选城市展示。可搜索城市、拼音或区县；区县搜索会定位到所属城市。").font(.footnote).foregroundStyle(
              .secondary)
          }
        }
        Section(query.isEmpty ? "城市目录" : "搜索结果") {
          let matches = BrowseCity.catalog.filter { $0.matches(query) }
          if matches.isEmpty {
            Text("未找到相关城市，试试城市名或拼音。").foregroundStyle(.secondary)
          }
          ForEach(matches) { city in
            Button {
              select(city.name)
            } label: {
              HStack {
                VStack(alignment: .leading, spacing: 4) {
                  Text(city.name).foregroundStyle(.primary)
                  Text(city.province).font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
                if city.name == selectedCity { Image(systemName: "checkmark") }
              }.frame(minHeight: 44)
            }
          }
        }
      }.navigationTitle("选择位置").navigationBarTitleDisplayMode(.inline)
        .searchable(text: $query, prompt: "城市 / 拼音 / 区县")
        .toolbar { ToolbarItem(placement: .cancellationAction) { Button("取消") { dismiss() } } }
        .onDisappear { locator.cancel() }
        .task {
          let organizations: [PublicOrganization]? = try? await store.communityPages(
            "organizations")
          directoryCities = organizations?.map(\.city) ?? []
        }
    }
  }
  private func citySection(_ title: String, values: [String]) -> some View {
    Section(title) {
      LazyVGrid(
        columns: [GridItem(.adaptive(minimum: typeSize.isAccessibilitySize ? 260 : 88))], spacing: 8
      ) {
        ForEach(values, id: \.self) { city in
          Button {
            select(city)
          } label: {
            Text(city).font(.subheadline).fixedSize(horizontal: false, vertical: true).frame(
              maxWidth: .infinity, minHeight: 44
            )
            .background(
              selectedCity == city ? Theme.accent.opacity(0.1) : Theme.background,
              in: RoundedRectangle(cornerRadius: 8))
          }.buttonStyle(.plain).foregroundStyle(selectedCity == city ? Theme.accent : .primary)
        }
      }.padding(.vertical, 4)
    }
  }
  private func select(_ city: String) {
    locator.cancel()
    selectedCity = city
    if let data = try? JSONEncoder().encode(BrowseCity.recent(city, previous: recent)) {
      recentJSON = String(decoding: data, as: UTF8.self)
    }
    dismiss()
  }
}
