import SwiftUI

struct ProfileView: View {
    @EnvironmentObject private var store: AppStore
    @State private var logoutPrompt = false
    @State private var showGuide = false
    @State private var busy = false
    var body: some View {
        NavigationStack {
            List {
                Section {
                    HStack(spacing:16) {
                        ClubAvatar(name:store.account?.name ?? "飞",size:64)
                        VStack(alignment:.leading,spacing:9) {
                            Text(store.account?.name ?? "登录无人机足球").font(.title2.weight(.bold))
                            Text(store.account?.organizationName ?? "管理队伍，报名参加赛事").font(.subheadline).foregroundStyle(.secondary)
                            if store.account != nil { Text("队长").font(.caption).foregroundStyle(Theme.green) }
                        }
                    }.padding(.vertical,16)
                    if store.account == nil { Button("选择演示账号") { store.showLogin = true }.frame(minHeight:44) }
                }.listRowBackground(Color.clear).listRowInsets(EdgeInsets(top:0,leading:0,bottom:0,trailing:0))
                if store.account != nil {
                    Section("我的参赛") {
                        NavigationLink { RegistrationsView() } label: { profileRow("我的报名",icon:"list.clipboard",value:"\(store.registrations.count)") }
                        NavigationLink { TeamsView() } label: { profileRow("我的队伍",icon:"person.2",value:"\(store.teams.count)") }
                    }
                }
                Section("帮助与服务") {
                    Button { showGuide = true } label: { HStack { profileRow("参赛指南",icon:"book.closed",value:""); Image(systemName:"chevron.right").font(.caption.weight(.semibold)).foregroundStyle(.tertiary) } }.foregroundStyle(Theme.ink)
                    NavigationLink { List { Section("当前版本") { LabeledContent("版本",value:"0.1.0"); LabeledContent("运行环境",value:"本地开发预览") }; Section { Text("当前使用虚构的成年飞手资料，验证队伍报名与主办方审核流程。暂不接收真实身份信息。视频、比赛成绩与真实身份登录尚未接入。").font(.subheadline).foregroundStyle(.secondary) } }.navigationTitle("关于无人机足球").navigationBarTitleDisplayMode(.inline) } label: { profileRow("关于无人机足球",icon:"info.circle",value:"") }
                }
                if let error = store.error { Section { ErrorBanner(text:error) { Task { await store.refresh() } }.listRowInsets(EdgeInsets()) } }
                if store.account != nil { Section { Button(role:.destructive) { logoutPrompt = true } label: { HStack { Text("退出登录"); Spacer(); if busy { ProgressView() } } }.disabled(busy) } }
                Section { Text("本地开发预览 · 演示资料").font(.caption).foregroundStyle(.secondary).frame(maxWidth:.infinity) }.listRowBackground(Color.clear)
            }.navigationTitle("我的").refreshable { await store.refresh() }
                .sheet(isPresented:$showGuide) { ParticipationGuide() }
                .confirmationDialog("退出当前账号？",isPresented:$logoutPrompt,titleVisibility:.visible) { Button("退出登录",role:.destructive) { Task { busy = true; defer { busy = false }; do { try await store.logout() } catch { store.handle(error) } } } }
        }
    }
    private func profileRow(_ title:String,icon:String,value:String)->some View {
        HStack(spacing:14) { Image(systemName:icon).font(.system(size:19)).foregroundStyle(Theme.green).frame(width:26); Text(title).font(.body); Spacer(); Text(value).font(.subheadline).foregroundStyle(.secondary) }.padding(.vertical,7)
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
                ForEach(accounts) { account in Button { Task { busy = true; defer { busy = false }; do { try await store.login(account.id) } catch { self.error = error.localizedDescription } } } label: { HStack(spacing:16) { ClubAvatar(name:account.organizationName); VStack(alignment:.leading,spacing:6) { Text(account.name).font(.headline); Text(account.organizationName).font(.caption).foregroundStyle(.secondary) }; Spacer(); if busy { ProgressView() } else { Image(systemName:"chevron.right").font(.caption) } }.padding(.vertical,10) }.disabled(busy) }
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
            ForEach(store.teams) { team in Section { HStack { HStack(spacing:12) { ClubAvatar(name:team.name); Text(team.name).font(.headline) }; Spacer(); Text(team.category).font(.caption).foregroundStyle(Theme.green) }; Text(team.city).font(.caption).foregroundStyle(.secondary); ForEach(team.roster,id:\.self) { Text($0).font(.subheadline) } } }
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
                VStack(alignment:.leading,spacing:24) {
                    HStack(spacing:14) { ClubAvatar(name:store.account?.name ?? "飞",size:56); VStack(alignment:.leading,spacing:6) { Text(store.account?.name ?? "我的参赛档案").font(.title3.weight(.bold)); Text(store.account?.organizationName ?? "登录后查看队伍和报名记录").font(.caption).foregroundStyle(.secondary) } }.padding(.top,8)
                    HStack(spacing:0) {
                        summary("所属队伍",value:store.account == nil ? "—" : "\(store.teams.count)")
                        Divider().frame(height:32)
                        summary("报名记录",value:store.account == nil ? "—" : "\(store.registrations.count)")
                        Divider().frame(height:32)
                        summary("审核通过",value:store.account == nil ? "—" : "\(store.registrations.filter { $0.status == "approved" }.count)")
                    }.padding(.vertical,22).background(Theme.surface,in:RoundedRectangle(cornerRadius:16))
                    SectionTitle(title:"参赛记录")
                    if store.account == nil {
                        ContentUnavailableView { Label("登录后查看参赛记录",systemImage:"person.crop.circle") } description: { Text("队伍、报名与审核结果将汇集在这里。") } actions: { Button("登录") { store.showLogin = true }.buttonStyle(.borderedProminent) }
                    } else if store.registrations.isEmpty {
                        ContentUnavailableView { Label("还没有报名记录",systemImage:"trophy") } description: { Text("选择合适的赛事，完成你的首次队伍报名。") } actions: { Button("查看赛事") { store.selectedTab = 1 }.buttonStyle(.borderedProminent) }
                    } else {
                        VStack(spacing:0) {
                            ForEach(store.registrations) { entry in
                                NavigationLink { RegistrationsView() } label: {
                                    HStack(alignment:.top,spacing:14) {
                                        Image(systemName:"flag.checkered").foregroundStyle(Theme.green).padding(.top,3)
                                        VStack(alignment:.leading,spacing:8) { Text(entry.tournamentTitle).font(.subheadline.weight(.semibold)).foregroundStyle(Theme.ink).multilineTextAlignment(.leading); Text(entry.teamName + "  ·  " + entry.category).font(.caption).foregroundStyle(.secondary); StatusBadge(text:entry.statusLabel) }
                                        Spacer(minLength:0); Image(systemName:"chevron.right").font(.caption2).foregroundStyle(.secondary).padding(.top,4)
                                    }.padding(18)
                                }.buttonStyle(.plain)
                                if entry.id != store.registrations.last?.id { Divider().padding(.leading,48) }
                            }
                        }.background(Theme.surface,in:RoundedRectangle(cornerRadius:14))
                    }
                    Label("比赛成绩尚未接入，报名通过不计入战绩。",systemImage:"info.circle").font(.footnote).foregroundStyle(.secondary)
                }.padding(20).frame(maxWidth:680)
            }.frame(maxWidth:.infinity).background(Theme.background).navigationTitle("生涯").refreshable { await store.refresh() }
        }
    }
    private func summary(_ title:String,value:String)->some View { VStack(spacing:8) { Text(value).font(.title.weight(.bold)).monospacedDigit(); Text(title).font(.caption).foregroundStyle(.secondary) }.frame(maxWidth:.infinity) }
}
struct VideoView: View {
    @EnvironmentObject private var store: AppStore
    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment:.leading,spacing:24) {
                    VStack(alignment:.leading,spacing:12) { Image(systemName:"play.rectangle").font(.system(size:32)).foregroundStyle(Theme.green); Text("赛事视频").font(.title2.weight(.bold)); Text("集中观看比赛直播与赛后回放。").font(.subheadline).foregroundStyle(.secondary) }.padding(24).frame(maxWidth:.infinity,alignment:.leading).background(Theme.surface,in:RoundedRectangle(cornerRadius:16))
                    ContentUnavailableView { Label("视频服务尚未开放",systemImage:"video.slash") } description: { Text("当前版本可查看赛事、创建队伍并提交报名。直播和回放将在接入视频服务后开放。") } actions: { Button("查看赛事") { store.selectedTab = 1 }.buttonStyle(.borderedProminent) }
                }.padding(20).frame(maxWidth:680)
            }.frame(maxWidth:.infinity).background(Theme.background).navigationTitle("视频")
        }
    }
}
