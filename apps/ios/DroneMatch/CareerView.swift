import SwiftUI

struct CareerView: View {
  @EnvironmentObject private var store: AppStore
  @State private var selection = "队伍赛程"
  var body: some View {
    NavigationStack {
      ScrollView {
        VStack(alignment: .leading, spacing: 24) {
          if let account = store.account {
            HStack(spacing: 16) {
              ClubAvatar(name: account.name, size: 64)
              VStack(alignment: .leading, spacing: 8) {
                Text(account.name).font(TypeScale.title)
                Text(account.organizationName).font(TypeScale.body).foregroundStyle(.secondary)
              }
              Spacer()
            }.padding(.vertical, 16)
            HStack(spacing: 0) {
              metric("管理队伍", value: store.teams.count)
              Divider().frame(height: 32)
              metric("加入队伍", value: store.memberships.count)
              Divider().frame(height: 32)
              metric("赛事报名", value: store.registrations.count)
            }.padding(.vertical, 20).background(
              Theme.surface, in: RoundedRectangle(cornerRadius: 16))
            NavigationLink {
              TeamsView()
            } label: {
              HStack {
                Label("我的队伍", systemImage: "person.3")
                Spacer()
                Text("管理与成员")
                Image(systemName: "chevron.right")
              }.font(TypeScale.body).frame(minHeight: 44)
            }
            ScrollView(.horizontal, showsIndicators: false) {
              HStack(spacing: 8) {
                ForEach(["队伍赛程", "赛事记录", "社区活动"], id: \.self) { value in
                  FilterChip(title: value, selected: selection == value) { selection = value }
                }
              }
            }
            SyncNotice()
            if selection == "队伍赛程" {
              SectionHeading(
                title: account.role == "organizer" ? "本机构赛事赛程" : "队伍的比赛",
                subtitle: account.role == "organizer" ? "本机构主办赛事的比赛安排" : "根据当前队伍关系显示，不代表个人实际出场")
              if store.isLoading && store.myMatches.isEmpty {
                ProgressView("正在加载赛程")
              } else if store.myMatches.isEmpty && store.error == nil {
                EmptyPanel(title: "暂时没有比赛安排", detail: "队伍的赛事公布赛程后，会同步到这里。", icon: "calendar")
                Button("浏览赛事") { store.selectedTab = 0 }.frame(minHeight: 44)
              }
              ForEach(store.myMatches) { match in
                NavigationLink {
                  MatchInformation(match: match)
                } label: {
                  VStack(alignment: .leading, spacing: 8) {
                    if let title = match.tournamentTitle {
                      Text(title).font(TypeScale.caption).foregroundStyle(.secondary)
                    }
                    MatchCard(match: match)
                  }
                }.buttonStyle(.plain)
              }
            } else if selection == "赛事记录" {
              SectionHeading(
                title: account.role == "organizer" ? "本机构报名记录" : "我的参赛安排",
                subtitle: "报名审核记录，不计为实际出场或战绩")
              if store.isLoading && store.registrations.isEmpty {
                ProgressView("正在加载记录")
              } else if store.registrations.isEmpty && store.error == nil {
                EmptyPanel(title: "从第一场比赛开始", detail: "选择赛事、确认队伍名单后提交报名。进度会保存在这里。", icon: "trophy")
                Button("寻找赛事") { store.selectedTab = 0 }.buttonStyle(.borderedProminent).frame(
                  minHeight: 44)
              }
              ForEach(store.registrations) { entry in
                NavigationLink {
                  RegistrationDetail(initial: entry)
                } label: {
                  RegistrationRow(entry: entry)
                }.buttonStyle(.plain)
                Divider()
              }
            } else {
              SectionHeading(title: "招募与活动", subtitle: "保留申请、接受与撤回记录")
              if store.isLoading && store.applications.isEmpty {
                ProgressView("正在加载活动")
              } else if store.applications.filter({ $0.applicantId == account.id }).isEmpty
                && store.error == nil
              {
                EmptyPanel(title: "还没有活动记录", detail: "招募飞手、加入队伍，或约一场训练赛。", icon: "calendar")
              }
              ForEach(store.applications.filter { $0.applicantId == account.id }) { application in
                NavigationLink {
                  CommunityDestination(id: application.postId)
                } label: {
                  HStack(alignment: .top, spacing: 16) {
                    Image(systemName: PostKind(rawValue: application.kind)?.icon ?? "calendar")
                      .foregroundStyle(Theme.accent).frame(width: 32)
                    VStack(alignment: .leading, spacing: 8) {
                      Text(application.postTitle).font(TypeScale.heading)
                      Text(application.city + " · " + application.statusLabel).font(TypeScale.body)
                        .foregroundStyle(.secondary)
                    }
                    Spacer()
                    Image(systemName: "chevron.right").font(TypeScale.caption)
                  }.padding(.vertical, 12)
                }.buttonStyle(.plain)
              }
              NavigationLink("查看全部申请与发布") { CommunityInbox() }.frame(minHeight: 44)
            }
          } else {
            EmptyPanel(
              title: "记录你的每一次参与", detail: "登录后，队伍、报名进展和社区活动会汇集在这里。", icon: "person.crop.rectangle")
            Button("登录并查看") { store.showLogin = true }.buttonStyle(.borderedProminent).frame(
              minHeight: 44)
            NavigationLink("先了解参赛流程") { ParticipationGuide() }.frame(minHeight: 44)
          }
        }.padding(20).frame(maxWidth: 600)
      }.frame(maxWidth: .infinity).background(Theme.background).navigationTitle("我的生涯")
        .navigationBarTitleDisplayMode(.inline)
        .refreshable { await store.refresh() }
    }
  }
  private func metric(_ label: String, value: Int) -> some View {
    VStack(spacing: 8) {
      Text(String(value)).font(TypeScale.title).monospacedDigit()
      Text(label).font(TypeScale.caption).foregroundStyle(.secondary)
    }.frame(maxWidth: .infinity)
  }
}
