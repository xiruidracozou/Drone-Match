import SwiftUI

private struct CommunityMessage: Decodable, Identifiable {
  let id, senderId, senderName, body, createdAt: String
}
private struct MessageDraft: Encodable { let body: String }
struct CommunityConversation: View {
  @EnvironmentObject private var store: AppStore
  @Environment(\.scenePhase) private var phase
  let application: CommunityApplication
  @State private var messages: [CommunityMessage] = []
  @State private var draft = ""
  @State private var error: String?
  @State private var sending = false
  @State private var loaded = false
  var body: some View {
    Group {
      if store.account?.id == application.authorId || store.account?.id == application.applicantId {
        VStack(spacing: 0) {
          NavigationLink {
            CommunityDestination(id: application.postId)
          } label: {
            HStack {
              VStack(alignment: .leading, spacing: 8) {
                Text(application.postTitle).font(.subheadline.weight(.semibold))
                Text("查看活动与申请处理状态").font(.caption).foregroundStyle(.secondary)
              }
              Spacer()
              Image(systemName: "chevron.right").font(.caption)
            }.padding(16)
          }.background(Theme.surface)
          ScrollViewReader { proxy in
            ScrollView {
              VStack(spacing: 16) {
                if !loaded && error == nil { ProgressView("正在加载留言") }
                if let error { InlineFailure(message: error) { Task { await load() } } }
                VStack(alignment: .leading, spacing: 8) {
                  Text("申请留言 · " + application.applicantName).font(.caption).foregroundStyle(
                    .secondary)
                  Text(application.message).font(.subheadline)
                }.padding(16).frame(maxWidth: .infinity, alignment: .leading).background(
                  Theme.surface, in: RoundedRectangle(cornerRadius: 12))
                ForEach(messages) { message in
                  VStack(
                    alignment: message.senderId == store.account?.id ? .trailing : .leading,
                    spacing: 8
                  ) {
                    Text(message.senderName + "  " + Tournament.formatDate(message.createdAt)).font(
                      .caption2
                    ).foregroundStyle(.secondary)
                    Text(message.body).font(TypeScale.body).padding(16).foregroundStyle(
                      message.senderId == store.account?.id ? .white : .primary
                    ).background(
                      message.senderId == store.account?.id ? Theme.solidAccent : Theme.surface,
                      in: RoundedRectangle(cornerRadius: 12))
                  }.frame(
                    maxWidth: .infinity,
                    alignment: message.senderId == store.account?.id ? .trailing : .leading
                  ).id(message.id)
                }
              }.padding(16)
            }.scrollDismissesKeyboard(.interactively).refreshable { await load() }
              .onChange(of: messages.count) { _, _ in
                if let id = messages.last?.id { proxy.scrollTo(id, anchor: .bottom) }
              }
          }
          HStack(alignment: .bottom, spacing: 12) {
            TextField("发送留言（最多1000字）", text: $draft, axis: .vertical).lineLimit(1...4).padding(12)
              .background(Theme.background, in: RoundedRectangle(cornerRadius: 12))
            Button {
              Task { await send() }
            } label: {
              if sending {
                ProgressView()
              } else {
                Image(systemName: "arrow.up").font(.headline).frame(width: 44, height: 44)
              }
            }.buttonStyle(.borderedProminent).tint(Theme.solidAccent).disabled(
              !loaded || draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                || draft.count > 1000 || sending)
          }.padding(16).background(.bar)
        }.background(Theme.background).navigationTitle("活动留言").navigationBarTitleDisplayMode(
          .inline
        ).toolbar {
          ToolbarItem(placement: .primaryAction) {
            Button("刷新留言", systemImage: "arrow.clockwise") { Task { await load() } }
          }
        }
        .task(id: phase) {
          guard phase == .active else { return }
          while !Task.isCancelled {
            await load()
            do { try await Task.sleep(for: .seconds(5)) } catch { return }
          }
        }.onChange(of: store.account?.id) { _, _ in
          messages = []
          loaded = false
          Task { await load() }
        }
      } else {
        ContentUnavailableView("请使用参与该申请的账号登录", systemImage: "person.crop.circle")
      }
    }
  }
  private func load() async {
    let owner = store.account?.id
    do {
      let rows: [CommunityMessage] = try await store.communityRequest(
        "applications/\(application.id)/messages")
      guard store.account?.id == owner else { return }
      messages = rows
      for start in stride(from: 0, to: rows.count, by: 1000) {
        let ids = Array(rows.dropFirst(start).prefix(1000)).map(\.id)
        let _: OKResponse = try await store.communityRequest(
          "applications/\(application.id)/read", method: "POST",
          body: JSONEncoder().encode(["messageIds": ids]))
      }
      error = nil
      loaded = true
    } catch is CancellationError {
      return
    } catch {
      self.error = "无法加载留言，请确认账号后重试。"
      loaded = false
    }
  }
  private func send() async {
    sending = true
    defer { sending = false }
    do {
      let _: OKResponse = try await store.communityRequest(
        "applications/\(application.id)/messages", method: "POST",
        body: JSONEncoder().encode(MessageDraft(body: draft)))
      draft = ""
      await load()
      await store.refresh()
    } catch { self.error = error.localizedDescription }
  }
}
