import SwiftUI

struct VideoLibraryView: View {
  @EnvironmentObject private var store: AppStore
  @AppStorage("selectedCity") private var city = "全国"
  @AppStorage("savedVideoIDs") private var savedJSON = "[]"
  @State private var query = ""
  @State private var savedOnly = false
  @State private var opened: PublishedContent?
  private var saved: [String] {
    (try? JSONDecoder().decode([String].self, from: Data(savedJSON.utf8))) ?? []
  }
  var body: some View {
    NavigationStack {
      ScrollView {
        VStack(alignment: .leading, spacing: 24) {
          ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
              FilterChip(title: "官方回放", selected: !savedOnly) { savedOnly = false }
              FilterChip(title: "我的收藏", selected: savedOnly) { savedOnly = true }
            }
          }
          ContentSyncNotice()
          let videos = store.content.filter {
            $0.kind == "video" && $0.visible(in: city) && (!savedOnly || saved.contains($0.id))
              && (query.isEmpty
                || ($0.title + $0.subtitle + $0.attribution).localizedCaseInsensitiveContains(query))
          }
          if videos.isEmpty {
            EmptyPanel(
              title: savedOnly ? "还没有可用的收藏" : "暂无相关视频", detail: "可以切换分类、调整搜索或稍后刷新。",
              icon: "play.rectangle")
          }
          ForEach(videos) { video in
            VStack(alignment: .leading, spacing: 20) {
              Text(video.attribution).font(.caption)
              Text(video.title).font(TypeScale.title)
              Text(video.subtitle).font(TypeScale.body)
              Button("观看官方回放") { opened = video }.buttonStyle(.borderedProminent).tint(.white)
                .foregroundStyle(Theme.navy).disabled(video.externalURL == nil)
            }.foregroundStyle(.white).padding(24).frame(maxWidth: .infinity, alignment: .leading)
              .background(Theme.navy, in: RoundedRectangle(cornerRadius: 16))
            HStack {
              Text("收藏保存在此设备").font(.caption).foregroundStyle(.secondary)
              Spacer()
              Button {
                var ids = saved
                if ids.contains(video.id) {
                  ids.removeAll { $0 == video.id }
                } else {
                  ids.append(video.id)
                }
                savedJSON = String(
                  decoding: (try? JSONEncoder().encode(ids)) ?? Data("[]".utf8), as: UTF8.self)
              } label: {
                Label(
                  saved.contains(video.id) ? "已收藏" : "收藏",
                  systemImage: saved.contains(video.id) ? "bookmark.fill" : "bookmark")
              }.frame(minHeight: 44)
            }
            Text(video.body).font(TypeScale.body).foregroundStyle(.secondary)
            if let url = URL(string: video.sourceURL), url.scheme == "https" {
              Link("赛事资料与视频来源", destination: url).frame(minHeight: 44)
            }
          }
        }.padding(20).frame(maxWidth: 600)
      }.frame(maxWidth: .infinity).background(Theme.background).navigationTitle("视频")
        .navigationBarTitleDisplayMode(.inline)
        .searchable(text: $query, prompt: "搜索赛事或视频来源")
        .sheet(item: $opened) { item in if let url = item.externalURL { ExternalPage(url: url) } }
        .refreshable { await store.refreshContent(city: city) }
        .onAppear {
          if !UserDefaults.standard.bool(forKey: "videoFavoritesMigrated") {
            if UserDefaults.standard.bool(forKey: "savedWorldChampionshipVideo"),
              !saved.contains("world-championship-2025")
            {
              savedJSON = String(
                decoding: (try? JSONEncoder().encode(saved + ["world-championship-2025"]))
                  ?? Data("[]".utf8), as: UTF8.self)
            }
            UserDefaults.standard.set(true, forKey: "videoFavoritesMigrated")
          }
        }
    }
  }
}
