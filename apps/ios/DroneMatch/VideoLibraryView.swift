import SwiftUI

struct VideoLibraryView: View {
  @State private var query = ""
  @State private var showSource = false
  @State private var savedOnly = false
  @AppStorage("savedWorldChampionshipVideo") private var saved = false
  private let title = "2025 无人机足球世界锦标赛"
  private let replayURL = URL(
    string: "https://youtube.com/playlist?list=PLyXQtZ_gjrxDK_6U2JK1KTlFKIckwwJ7i")!
  var body: some View {
    NavigationStack {
      ScrollView {
        VStack(alignment: .leading, spacing: 24) {
          HStack(spacing: 8) {
            FilterChip(title: "官方回放", selected: !savedOnly) { savedOnly = false }
            FilterChip(title: "我的收藏", selected: savedOnly) { savedOnly = true }
          }
          if (!savedOnly || saved)
            && (query.isEmpty || (title + "FAI 上海 回放").localizedCaseInsensitiveContains(query))
          {
            VStack(alignment: .leading, spacing: 24) {
              HStack {
                Text("FAI 世界航空运动联合会").font(TypeScale.caption)
                Spacer()
                Image(systemName: "arrow.up.right")
              }
              Text(title).font(TypeScale.title).fixedSize(horizontal: false, vertical: true)
              Text("上海 · 2025.11.15 – 11.18").font(TypeScale.body)
              Button {
                showSource = true
              } label: {
                Label("观看官方回放合集", systemImage: "play.fill").font(TypeScale.heading).frame(
                  maxWidth: .infinity, minHeight: 48)
              }.buttonStyle(.borderedProminent).tint(.white).foregroundStyle(Theme.navy)
            }.foregroundStyle(.white).padding(24).background(
              Theme.navy, in: RoundedRectangle(cornerRadius: 16))
            HStack {
              Text("来源：FAI 官方赛事页面").font(TypeScale.caption).foregroundStyle(.secondary)
              Spacer()
              Button {
                saved.toggle()
              } label: {
                Label(saved ? "已收藏" : "收藏", systemImage: saved ? "bookmark.fill" : "bookmark").font(
                  TypeScale.body
                ).frame(minHeight: 44)
              }.sensoryFeedback(.selection, trigger: saved)
            }
            Text("在官方 YouTube 页面观看，播放与网络可用性由来源平台提供。收藏保存在此设备。").font(TypeScale.body).foregroundStyle(
              .secondary)
            Link(
              "赛事资料与视频来源", destination: URL(string: "https://www-2025.fai.org/wdsc2025-livestream")!
            ).font(TypeScale.body).frame(minHeight: 44)
          } else {
            EmptyPanel(
              title: savedOnly ? "还没有收藏的回放" : "没有找到相关视频", detail: "切换到官方回放，或换一个关键词。",
              icon: "play.rectangle")
            Button("查看官方回放") {
              query = ""
              savedOnly = false
            }.frame(minHeight: 44)
          }
        }.padding(20).frame(maxWidth: 600)
      }.frame(maxWidth: .infinity).background(Theme.background).navigationTitle("视频")
        .navigationBarTitleDisplayMode(.inline)
        .searchable(text: $query, prompt: "搜索赛事或视频来源")
        .sheet(isPresented: $showSource) { ExternalPage(url: replayURL) }
    }
  }
}
