import SwiftUI

struct PublishedImage: View {
  let assetId: String
  var body: some View {
    AsyncImage(url: APIClient.assetURL(assetId)) { phase in
      if let image = phase.image {
        image.resizable().scaledToFill()
      } else if assetId == "field-photo" {
        HomePhoto(name: "DroneSoccerField")
      } else if assetId == "equipment-photo" {
        HomePhoto(name: "DroneSoccer")
      } else {
        Rectangle().fill(Theme.background).overlay(
          Image(systemName: "photo").foregroundStyle(.secondary))
      }
    }
  }
}
struct ContentSyncNotice: View {
  @EnvironmentObject private var store: AppStore
  @AppStorage("selectedCity") private var city = "全国"
  var body: some View {
    if let error = store.contentError {
      VStack(alignment: .leading, spacing: 8) {
        Text(error).font(.footnote).foregroundStyle(.secondary)
        Button("重新加载内容") { Task { await store.refreshContent(city: city) } }.frame(minHeight: 44)
      }
    }
  }
}
struct PublishedGuide: View {
  @EnvironmentObject private var store: AppStore
  @AppStorage("selectedCity") private var city = "全国"
  let id: String
  var body: some View {
    ScrollView {
      VStack(alignment: .leading, spacing: 20) {
        ContentSyncNotice()
        if let item = store.content.first(where: {
          $0.id == id && $0.kind == "guide" && $0.visible(in: city)
        }) {
          if !item.assetId.isEmpty {
            PublishedImage(assetId: item.assetId).frame(height: 220).clipped().clipShape(
              RoundedRectangle(cornerRadius: 12))
          }
          Text(item.title).font(TypeScale.title)
          if !item.subtitle.isEmpty {
            Text(item.subtitle).font(TypeScale.body).foregroundStyle(.secondary)
          }
          Text(item.body).font(TypeScale.body).lineSpacing(6)
          if !item.attribution.isEmpty {
            Text(item.attribution).font(.caption).foregroundStyle(.secondary)
          }
          if let url = URL(string: item.sourceURL), url.scheme == "https" {
            Link("查看官方来源", destination: url).frame(minHeight: 44)
          }
        } else {
          EmptyPanel(title: "内容暂不可用", detail: "内容可能尚未发布或已下架，请稍后刷新。", icon: "doc.text")
        }
      }.padding(20).frame(maxWidth: 600)
    }.navigationTitle("指南").navigationBarTitleDisplayMode(.inline)
      .refreshable { await store.refreshContent(city: city) }
  }
}
struct ContentDestination: View {
  let content: PublishedContent
  var body: some View {
    switch content.action.type {
    case "guide": PublishedGuide(id: content.action.id)
    case "video": VideoLibraryView()
    case "community": CommunityView(kind: .recruit)
    case "tournament": PublishedTournament(id: content.action.id)
    default:
      if let url = content.externalURL {
        ExternalPage(url: url).ignoresSafeArea(edges: .bottom)
      } else {
        EmptyPanel(title: "暂无跳转内容", detail: "请返回继续浏览。", icon: "doc.text")
      }
    }
  }
}
struct PublishedTournament: View {
  @EnvironmentObject private var store: AppStore
  let id: String
  @State private var event: Tournament?
  @State private var error: String?
  var body: some View {
    Group {
      if let event {
        TournamentDetail(initial: event)
      } else if let error {
        Text(error).padding()
      } else {
        ProgressView("正在加载赛事")
      }
    }.task(id: id) {
      do { event = try await store.request("tournaments/" + id) } catch {
        self.error = error.localizedDescription
      }
    }
  }
}
