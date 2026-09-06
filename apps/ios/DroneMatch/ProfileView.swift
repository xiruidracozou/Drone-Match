import SwiftUI

struct ProfileView: View {
  @EnvironmentObject private var store: AppStore
  @State private var logoutPrompt = false
  @State private var busy = false
  var body: some View {
    NavigationStack {
      List {
        Section {
          HStack(spacing: 16) {
            ClubAvatar(name: store.account?.name ?? "我", size: 58)
            VStack(alignment: .leading, spacing: 7) {
              Text(store.account?.name ?? "登录后管理参赛").font(.title3.weight(.semibold))
              Text(store.account?.organizationName ?? "创建队伍、报名赛事和查看审核结果")
                .font(.subheadline).foregroundStyle(.secondary)
            }
          }.padding(.vertical, 14)
          if store.account == nil { Button("登录") { store.showLogin = true }.frame(minHeight: 44) }
        }
        if store.account != nil {
          Section {
            NavigationLink {
              CommunityInbox()
            } label: {
              Label("申请与消息", systemImage: "tray").padding(.vertical, 6)
            }
            NavigationLink {
              RegistrationsView()
            } label: {
              HStack {
                Label("我的报名", systemImage: "list.clipboard")
                Spacer()
                Text("\(store.registrations.count)").foregroundStyle(.secondary)
              }.padding(.vertical, 6)
            }
          }
        }
        Section {
          NavigationLink {
            ParticipationGuide()
          } label: {
            Label("参赛指南", systemImage: "book.closed").padding(.vertical, 6)
          }
          NavigationLink {
            List {
              Section("当前版本") {
                LabeledContent("版本", value: "0.1.0")
                LabeledContent("运行环境", value: "本地开发")
              }
              Section {
                Text("目前仅使用虚构的成年演示资料。可创建及编辑队伍、提交赛事报名、查看审核结果。真实身份和正式比赛服务尚未接入。").font(.subheadline)
                  .foregroundStyle(.secondary)
              }
            }.navigationTitle("关于").navigationBarTitleDisplayMode(.inline)
          } label: {
            Label("关于无人机足球", systemImage: "info.circle").padding(.vertical, 6)
          }
        }
        if store.error != nil { Section { SyncNotice() }.listRowInsets(EdgeInsets()) }
        if store.account != nil {
          Section {
            Button(role: .destructive) {
              logoutPrompt = true
            } label: {
              HStack {
                Text("退出登录")
                Spacer()
                if busy { ProgressView() }
              }
            }.disabled(busy)
          }
        }
        Section {
          Text("开发环境 · 仅使用演示资料").font(.caption).foregroundStyle(.secondary).frame(
            maxWidth: .infinity)
        }.listRowBackground(Color.clear)
      }
      .navigationTitle("我的").refreshable { await store.refresh() }
      .confirmationDialog("退出当前账号？", isPresented: $logoutPrompt, titleVisibility: .visible) {
        Button("退出登录", role: .destructive) {
          Task {
            busy = true
            defer { busy = false }
            do { try await store.logout() } catch { store.handle(error) }
          }
        }
      }
    }
  }
}

struct RegistrationsView: View {
  @EnvironmentObject private var store: AppStore
  @State private var status = "全部"
  private var filtered: [Registration] {
    store.registrations.filter { status == "全部" || $0.statusLabel == status }
  }
  var body: some View {
    List {
      if store.error != nil { Section { SyncNotice() } }
      if store.account == nil {
        Section {
          Text("登录后查看报名记录")
          Button("登录") { store.showLogin = true }
        }
      } else {
        Section {
          Picker("报名状态", selection: $status) {
            ForEach(["全部", "待审核", "已通过", "未通过"], id: \.self) { Text($0).tag($0) }
          }
        }
        if store.isLoading && store.registrations.isEmpty {
          ProgressView("正在加载报名")
        } else if filtered.isEmpty && store.error == nil {
          ContentUnavailableView {
            Label("暂无\(status == "全部" ? "" : status)报名", systemImage: "list.clipboard")
          } description: {
            Text(status == "全部" ? "选择赛事后，以队伍身份提交报名。" : "可以切换状态查看其他报名。")
          } actions: {
            if status != "全部" {
              Button("查看全部报名") { status = "全部" }
            } else {
              Button("查看赛事") { store.selectedTab = 0 }
            }
          }
        }
        ForEach(filtered) { entry in
          NavigationLink {
            RegistrationDetail(initial: entry)
          } label: {
            RegistrationRow(entry: entry)
          }
        }
      }
    }
    .navigationTitle("我的报名").navigationBarTitleDisplayMode(.inline)
    .refreshable { await store.refresh() }.task { await store.refresh() }
    .toolbar {
      ToolbarItem(placement: .primaryAction) {
        Button("刷新报名", systemImage: "arrow.clockwise") { Task { await store.refresh() } }.disabled(
          store.isLoading)
      }
    }
  }
}

struct RegistrationDetail: View {
  @EnvironmentObject private var store: AppStore
  let initial: Registration
  private var entry: Registration { store.registrations.first { $0.id == initial.id } ?? initial }
  var body: some View {
    List {
      if store.account == nil {
        Section {
          Text("登录后查看报名详情")
          Button("登录") { store.showLogin = true }
        }
      } else if !store.registrations.contains(where: { $0.id == initial.id }) {
        ContentUnavailableView(
          "报名暂不可用", systemImage: "list.clipboard", description: Text("请返回报名列表并刷新。"))
      } else {
        if store.error != nil { Section { SyncNotice() } }
        Section {
          StatusBadge(text: entry.statusLabel)
          Text(entry.tournamentTitle).font(.headline)
          Text(statusDescription).font(.subheadline).foregroundStyle(.secondary)
        }
        Section("报名信息") {
          LabeledContent("参赛队伍", value: entry.teamName)
          LabeledContent("设备级别", value: entry.category + " 级")
          LabeledContent("提交时间", value: Tournament.formatDate(entry.createdAt))
          if !entry.reviewNote.isEmpty {
            VStack(alignment: .leading, spacing: 8) {
              Text("审核说明").font(.caption).foregroundStyle(.secondary)
              Text(entry.reviewNote).font(.subheadline)
            }.padding(.vertical, 6)
          }
        }
        Section {
          ForEach(entry.roster, id: \.self) { Text($0) }
        } header: {
          Text("提交时的名单 · \(entry.roster.count) 人")
        } footer: {
          Text("此名单为报名时的记录，之后编辑队伍不会改变它。")
        }
        Section {
          NavigationLink {
            TournamentDestination(id: entry.tournamentId)
          } label: {
            Label("查看对应赛事", systemImage: "trophy")
          }
        }
      }
    }
    .navigationTitle("报名详情").navigationBarTitleDisplayMode(.inline)
    .toolbar(.hidden, for: .tabBar)
    .refreshable { await store.refresh() }
  }
  private var statusDescription: String {
    switch entry.status {
    case "approved": return "报名审核已通过，赛事时间和场地可在对应赛事中查看。"
    case "rejected": return "报名未通过，请查看主办方的审核说明。"
    default: return "报名已提交，等待主办方审核。下拉可刷新审核结果。"
    }
  }
}

struct LoginView: View {
  @EnvironmentObject private var store: AppStore
  @Environment(\.dismiss) private var dismiss
  @State private var accounts: [Account] = []
  @State private var error: String?
  @State private var busyID: String?
  var body: some View {
    NavigationStack {
      List {
        Section {
          Text("选择本地演示账号").font(.headline)
          Text("账号代表队伍负责人，人员资料均为虚构。当前不接收真实身份信息。").font(.subheadline).foregroundStyle(.secondary)
        }
        if accounts.isEmpty && error == nil { ProgressView("正在加载账号") }
        ForEach(accounts) { account in
          Button {
            Task {
              busyID = account.id
              defer { busyID = nil }
              do {
                try await store.login(account.id)
                dismiss()
              } catch { self.error = error.localizedDescription }
            }
          } label: {
            HStack(spacing: 14) {
              ClubAvatar(name: account.organizationName)
              VStack(alignment: .leading, spacing: 6) {
                Text(account.name).font(.headline).foregroundStyle(.primary)
                Text(account.organizationName).font(.subheadline).foregroundStyle(.secondary)
              }
              Spacer()
              if busyID == account.id {
                ProgressView()
              } else {
                Image(systemName: "chevron.right").font(.caption).foregroundStyle(.secondary)
              }
            }.padding(.vertical, 8)
          }.disabled(busyID != nil)
        }
        if let error {
          Section {
            Text(error).foregroundStyle(.red)
            Button("重新加载") { Task { await load() } }
          }
        }
      }
      .navigationTitle("登录").navigationBarTitleDisplayMode(.inline)
      .toolbar {
        ToolbarItem(placement: .cancellationAction) {
          Button("取消") { dismiss() }.disabled(busyID != nil)
        }
      }
      .task { await load() }.interactiveDismissDisabled(busyID != nil)
    }
  }
  private func load() async {
    error = nil
    do { accounts = try await store.demoAccounts() } catch { self.error = "无法加载账号，请确认本地服务已启动。" }
  }
}
