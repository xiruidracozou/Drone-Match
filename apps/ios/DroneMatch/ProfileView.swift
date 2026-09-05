import SwiftUI

struct ProfileView: View {
    @EnvironmentObject private var store: AppStore
    @State private var logoutPrompt = false
    @State private var busy = false
    var body: some View {
        NavigationStack {
            List {
                Section {
                    HStack(spacing:16) { Image(systemName:"person.crop.circle.fill").font(.system(size:52)).foregroundStyle(Theme.green); VStack(alignment:.leading,spacing:8) { Text(store.account?.name ?? "欢迎来到 Drone Match").font(.headline); Text(store.account?.organizationName ?? "登录后，开启你的飞行旅程").font(.caption).foregroundStyle(.secondary) } }.padding(.vertical,12)
                    if store.account == nil { Button("选择演示账号") { store.showLogin = true }.frame(minHeight:44) }
                }
                if store.account != nil {
                    Section {
                        NavigationLink { RegistrationsView() } label: { Label("我的报名",systemImage:"list.bullet.rectangle") }
                        NavigationLink { TeamsView() } label: { Label("我的队伍",systemImage:"person.3") }
                    }
                }
                Section("关于当前版本") {
                    Label("本地开发预览",systemImage:"hammer").font(.subheadline)
                    Text("当前使用虚构的成年飞手资料，验证报名与审核流程。暂不接收真实身份信息。").font(.footnote).foregroundStyle(.secondary)
                }
                if let error = store.error { Section { ErrorBanner(text:error) { Task { await store.refresh() } }.listRowInsets(EdgeInsets()) } }
                if store.account != nil { Section { Button(role:.destructive) { logoutPrompt = true } label: { HStack { Text("退出登录"); if busy { ProgressView() } } }.disabled(busy) } }
            }.navigationTitle("我的").refreshable { await store.refresh() }
                .confirmationDialog("退出当前账号？",isPresented:$logoutPrompt,titleVisibility:.visible) { Button("退出登录",role:.destructive) { Task { busy = true; defer { busy = false }; do { try await store.logout() } catch { store.handle(error) } } } }
        }
    }
}
struct RegistrationsView: View {
    @EnvironmentObject private var store: AppStore
    var body: some View {
        List {
            if store.registrations.isEmpty { ContentUnavailableView("还没有报名记录",systemImage:"trophy",description:Text("选择一场赛事，和队伍一起出发。")) }
            ForEach(store.registrations) { registration in
                VStack(alignment:.leading,spacing:12) { HStack { Text(registration.teamName).font(.headline); Spacer(); StatusBadge(text:registration.statusLabel) }; Text(registration.tournamentTitle).font(.subheadline); Text("\(registration.roster.count) 名飞手 · \(registration.category)").font(.caption).foregroundStyle(.secondary); if !registration.reviewNote.isEmpty { Text("审核说明：\(registration.reviewNote)").font(.footnote) } }.padding(.vertical,8)
            }
        }.navigationTitle("我的报名").navigationBarTitleDisplayMode(.inline).refreshable { await store.refresh() }.task { await store.refresh() }
            .toolbar { ToolbarItem(placement:.primaryAction) { Button("刷新报名",systemImage:"arrow.clockwise") { Task { await store.refresh() } }.disabled(store.isLoading) } }
    }
}
struct LoginView: View {
    @EnvironmentObject private var store: AppStore
    @Environment(\.dismiss) private var dismiss
    @State private var accounts: [Account] = []
    @State private var error: String?
    @State private var busy = false
    var body: some View {
        NavigationStack {
            List {
                Section { Text("选择一个队长身份，体验队伍报名。主办方请使用 Web 后台。").font(.subheadline).foregroundStyle(.secondary) }
                if accounts.isEmpty && error == nil { ProgressView().frame(maxWidth:.infinity) }
                ForEach(accounts) { account in Button { Task { busy = true; defer { busy = false }; do { try await store.login(account.id) } catch { self.error = error.localizedDescription } } } label: { HStack(spacing:16) { Image(systemName:"person.crop.circle").font(.title); VStack(alignment:.leading,spacing:6) { Text(account.name).font(.headline); Text(account.organizationName).font(.caption).foregroundStyle(.secondary) }; Spacer(); if busy { ProgressView() } else { Image(systemName:"chevron.right").font(.caption) } }.padding(.vertical,10) }.disabled(busy) }
                if let error { Section { Text(error).foregroundStyle(.red); Button("重新加载") { Task { await load() } } } }
                Section { Text("本地演示账号不等同于真实身份登录。所有示例人员均为虚构。").font(.footnote).foregroundStyle(.secondary) }
            }.navigationTitle("演示账号").navigationBarTitleDisplayMode(.inline).toolbar { ToolbarItem(placement:.cancellationAction) { Button("取消") { dismiss() }.disabled(busy) } }.task { await load() }.interactiveDismissDisabled(busy)
        }
    }
    private func load() async { error = nil; do { accounts = try await store.demoAccounts() } catch { self.error = "无法加载演示账号，请确认本地服务已启动。" } }
}
struct TeamsView: View {
    @EnvironmentObject private var store: AppStore
    @State private var showCreate = false
    var body: some View {
        List {
            if store.teams.isEmpty { ContentUnavailableView("创建你的第一支队伍",systemImage:"person.3",description:Text("添加成年演示飞手，开始体验赛事报名。")) }
            ForEach(store.teams) { team in Section { HStack { Label(team.name,systemImage:"person.3.fill").font(.headline); Spacer(); Text(team.category).font(.caption).foregroundStyle(Theme.green) }; Text(team.city).font(.caption).foregroundStyle(.secondary); ForEach(team.roster,id:\.self) { Text($0).font(.subheadline) } } }
        }.navigationTitle("我的队伍").navigationBarTitleDisplayMode(.inline).toolbar { ToolbarItem(placement:.primaryAction) { Button("创建队伍",systemImage:"plus") { showCreate = true } } }.sheet(isPresented:$showCreate) { CreateTeamView().environmentObject(store) }.refreshable { await store.refresh() }
    }
}
struct CreateTeamView: View {
    @EnvironmentObject private var store: AppStore
    @Environment(\.dismiss) private var dismiss
    @State private var name = ""
    @State private var city = ""
    @State private var category = "20cm"
    @State private var roster = ""
    @State private var adultOnly = false
    @State private var busy = false
    @State private var error: String?
    private var names: [String] { roster.split(separator:"\n").map { $0.trimmingCharacters(in:.whitespaces) }.filter { !$0.isEmpty } }
    private var valid: Bool { name.trimmingCharacters(in:.whitespaces).count >= 2 && city.trimmingCharacters(in:.whitespaces).count >= 2 && !names.isEmpty && names.count <= 10 && Set(names).count == names.count && adultOnly }
    var body: some View {
        NavigationStack {
            Form {
                Section("队伍资料") { TextField("队伍名称（至少 2 字）",text:$name); TextField("城市",text:$city); Picker("设备级别",selection:$category) { Text("20cm 级").tag("20cm"); Text("40cm 级").tag("40cm") } }
                Section("飞手名单 · 每行一名，1–10 名") { TextField("填写成年演示飞手姓名",text:$roster,axis:.vertical).lineLimit(4...10); Toggle("仅使用虚构的成年演示资料",isOn:$adultOnly) }
                if let error { Section { Text(error).foregroundStyle(.red) } }
            }.navigationTitle("创建队伍").navigationBarTitleDisplayMode(.inline).toolbar {
                ToolbarItem(placement:.cancellationAction) { Button("取消") { dismiss() }.disabled(busy) }
                ToolbarItem(placement:.confirmationAction) { Button { Task { await save() } } label: { if busy { ProgressView() } else { Text("创建") } }.disabled(!valid || busy) }
            }.interactiveDismissDisabled(busy)
        }
    }
    private func save() async { busy = true; defer { busy = false }; do { try await store.createTeam(CreateTeam(name:name,city:city,category:category,roster:names)); dismiss() } catch { self.error = error.localizedDescription } }
}
struct CareerView: View {
    @EnvironmentObject private var store: AppStore
    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing:24) {
                    VStack(alignment:.leading,spacing:18) { Text("每一次出发，\n都在书写你的生涯。").font(.title.weight(.bold)); HStack { Text(store.account?.name ?? "我的飞行旅程"); Spacer(); Image(systemName:"paperplane") }.font(.subheadline) }.padding(28).frame(maxWidth:.infinity,alignment:.leading).foregroundStyle(.white).background(Theme.hero,in:RoundedRectangle(cornerRadius:24))
                    ContentUnavailableView("等待第一场比赛",systemImage:"medal",description:Text("正式比赛成绩发布后，你的出场与战绩将在这里留下记录。报名通过不计入比赛战绩。"))
                    if store.account != nil { NavigationLink { RegistrationsView() } label: { Label("查看我的报名",systemImage:"list.bullet.rectangle").frame(minHeight:44) }.buttonStyle(.bordered) }
                    else { Button("登录，开启旅程") { store.showLogin = true }.buttonStyle(.borderedProminent) }
                }.padding(20).frame(maxWidth:680)
            }.frame(maxWidth:.infinity).background(Theme.background).navigationTitle("生涯")
        }
    }
}
struct VideoView: View {
    var body: some View {
        NavigationStack { ContentUnavailableView("精彩，等待开场",systemImage:"play.rectangle",description:Text("暂无已发布的视频。赛事直播与比赛回放将在这里集中展示。" )).background(Theme.background).navigationTitle("视频") }
    }
}
