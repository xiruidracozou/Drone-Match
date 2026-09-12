import SwiftUI

struct TeamMember: Decodable, Identifiable {
  let id, name: String
  let isOwner: Bool
}
struct TeamMembersView: View {
  @EnvironmentObject private var store: AppStore
  @Environment(\.dismiss) private var dismiss
  let teamID, teamName: String
  @State private var members: [TeamMember] = []
  @State private var error: String?
  @State private var loading = true
  @State private var removing: TeamMember?
  @State private var busy = false
  private var isOwner: Bool { members.contains { $0.id == store.account?.id && $0.isOwner } }
  var body: some View {
    List {
      Section {
        HStack(spacing: 16) {
          ClubAvatar(name: teamName, size: 64)
          Text(teamName).font(TypeScale.title)
        }.padding(.vertical, 12)
      }
      if let error { Section { InlineFailure(message: error) { Task { await load() } } } }
      Section {
        if loading { ProgressView("正在加载成员") }
        ForEach(members) { member in
          HStack(spacing: 16) {
            ClubAvatar(name: member.name, size: 40)
            VStack(alignment: .leading, spacing: 4) {
              Text(member.name).font(TypeScale.body)
              if member.isOwner {
                Text("负责人").font(TypeScale.caption).foregroundStyle(Theme.accent)
              }
            }
            Spacer()
            if !member.isOwner && (isOwner || member.id == store.account?.id) {
              Button(member.id == store.account?.id ? "退出" : "移除", role: .destructive) {
                removing = member
              }.font(TypeScale.body).frame(minHeight: 44).disabled(busy)
            }
          }
        }
      } header: {
        Text("社区成员 · \(members.count)")
      } footer: {
        Text("社区成员关系与赛事提交的名单分别保存。退出或移除不会改变已提交的报名。")
      }
      NavigationLink {
        CommunityView(kind: .friendly)
      } label: {
        Label("查看训练约赛", systemImage: "sportscourt")
      }
    }.navigationTitle("队伍成员").navigationBarTitleDisplayMode(.inline).task { await load() }
      .refreshable { await load() }
      .confirmationDialog(
        "确认\(removing?.id == store.account?.id ? "退出队伍" : "移除成员")？",
        isPresented: Binding(get: { removing != nil }, set: { if !$0 { removing = nil } }),
        titleVisibility: .visible
      ) {
        if let member = removing {
          Button(member.id == store.account?.id ? "退出队伍" : "移除成员", role: .destructive) {
            Task { await remove(member) }
          }
        }
      }
  }
  private func load() async {
    loading = true
    defer { loading = false }
    do {
      members = try await store.communityRequest("teams/\(teamID)/members")
      error = nil
    } catch {
      members = []
      self.error = error.localizedDescription
    }
  }
  private func remove(_ member: TeamMember) async {
    busy = true
    defer { busy = false }
    do {
      let _: OKResponse = try await store.communityRequest(
        "teams/\(teamID)/members/\(member.id)", method: "DELETE")
      await store.refresh()
      if member.id == store.account?.id { dismiss() } else { await load() }
    } catch { self.error = error.localizedDescription }
  }
}
private struct NameDraft: Encodable { let name: String }
struct AccountEditor: View {
  @EnvironmentObject private var store: AppStore
  @Environment(\.dismiss) private var dismiss
  @State private var name = ""
  @State private var busy = false
  @State private var error: String?
  var body: some View {
    Form {
      Section("显示名称") { TextField("2–40 个字", text: $name).textInputAutocapitalization(.never) }
      if let error { Section { Text(error).foregroundStyle(.red) } }
      Section { Text("显示名称用于队伍与社区交流，不作为实名信息。").font(TypeScale.caption).foregroundStyle(.secondary) }
    }.navigationTitle("个人资料").navigationBarTitleDisplayMode(.inline).task {
      name = store.account?.name ?? ""
    }
    .toolbar {
      ToolbarItem(placement: .confirmationAction) {
        Button("保存") { Task { await save() } }.disabled(
          busy || !(2...40).contains(name.trimmingCharacters(in: .whitespacesAndNewlines).count))
      }
    }
  }
  private func save() async {
    busy = true
    defer { busy = false }
    do {
      let _: Account = try await store.request(
        "me", method: "PATCH", body: JSONEncoder().encode(NameDraft(name: name)))
      await store.refresh()
      dismiss()
    } catch { self.error = error.localizedDescription }
  }
}
struct AppSettingsView: View {
  @AppStorage("appearance") private var appearance = "system"
  var body: some View {
    Form {
      Section("显示") {
        Picker("外观", selection: $appearance) {
          Text("跟随系统").tag("system")
          Text("浅色").tag("light")
          Text("深色").tag("dark")
        }
      }
      Section("关于") {
        LabeledContent(
          "版本",
          value: Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String
            ?? "—")
        Text("当前为本地开发版本，使用演示账号和虚构的成年参赛资料。正式身份认证和平台直播服务尚未接入。").font(TypeScale.body).foregroundStyle(
          .secondary)
      }
      Section("数据使用说明") {
        Text("队伍名单、申请与留言保存在当前连接的服务中。私有申请和留言仅参与账号可见，公开队伍页不展示报名人员名单。").font(TypeScale.body)
        Text("退出登录清除本机登录会话。外观与视频收藏仅保存在此设备。").font(TypeScale.body)
      }
    }.navigationTitle("设置与关于").navigationBarTitleDisplayMode(.inline)
  }
}
private struct FeedbackRecord: Decodable, Identifiable {
  let id, category, body, status, createdAt: String
  let reply: String?
}
private struct FeedbackDraft: Encodable { let category, body: String }
struct FeedbackView: View {
  @EnvironmentObject private var store: AppStore
  @State private var category = "功能问题"
  @State private var text = ""
  @State private var records: [FeedbackRecord] = []
  @State private var error: String?
  @State private var busy = false
  @State private var sent = false
  var body: some View {
    Form {
      if store.account == nil {
        Section {
          Text("登录后提交和查看你的反馈。")
          Button("登录") { store.showLogin = true }
        }
      } else {
        if sent {
          Section {
            Label("反馈已保存", systemImage: "checkmark.circle.fill").foregroundStyle(Theme.accent)
            Text("可在下方查看提交记录。当前没有在线客服接入。").font(TypeScale.body)
          }
        }
        Section("描述问题") {
          Picker("类型", selection: $category) {
            ForEach(["功能问题", "使用建议", "内容举报"], id: \.self) { Text($0) }
          }
          TextField("遇到了什么问题？请填写至少 8 个字。", text: $text, axis: .vertical).lineLimit(5...10)
          Text("请勿填写密码、证件号码等敏感信息。").font(TypeScale.caption).foregroundStyle(.secondary)
        }
        if let error { Section { Text(error).foregroundStyle(.red) } }
        Section {
          Button {
            Task { await submit() }
          } label: {
            HStack {
              Spacer()
              if busy { ProgressView() }
              Text("提交反馈")
              Spacer()
            }.frame(minHeight: 44)
          }.disabled(
            busy || !(8...2000).contains(text.trimmingCharacters(in: .whitespacesAndNewlines).count)
          )
        }
        Section("提交记录") {
          if records.isEmpty { Text("暂无反馈记录").foregroundStyle(.secondary) }
          ForEach(records) { row in
            VStack(alignment: .leading, spacing: 8) {
              HStack {
                Text(row.category).font(TypeScale.heading)
                Spacer()
                Text(
                  ["received": "待处理", "processing": "处理中", "resolved": "已解决"][row.status]
                    ?? row.status
                ).font(TypeScale.caption).foregroundStyle(Theme.accent)
              }
              Text(row.body).font(TypeScale.body)
              if let reply = row.reply, !reply.isEmpty {
                Text("平台回复：" + reply).font(TypeScale.body).foregroundStyle(Theme.accent)
              }
              Text(Tournament.formatDate(row.createdAt)).font(TypeScale.caption).foregroundStyle(
                .secondary)
            }.padding(.vertical, 8)
          }
        }
      }
    }.navigationTitle("问题反馈").navigationBarTitleDisplayMode(.inline).task(id: store.account?.id) {
      records = []
      await load()
    }.refreshable { await load() }
  }
  private func load() async {
    guard store.account != nil else { return }
    do {
      records = try await store.request("feedback")
      error = nil
    } catch { self.error = error.localizedDescription }
  }
  private func submit() async {
    busy = true
    defer { busy = false }
    do {
      let _: FeedbackRecord = try await store.request(
        "feedback", method: "POST",
        body: JSONEncoder().encode(FeedbackDraft(category: category, body: text)))
      text = ""
      sent = true
      await load()
    } catch { self.error = error.localizedDescription }
  }
}
