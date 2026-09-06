import SwiftUI

struct EventsView: View {
  @EnvironmentObject private var store: AppStore
  @State private var search = ""
  @State private var category = "全部"
  @State private var city = "全国"
  @State private var openOnly = false
  @FocusState private var searching: Bool

  private var cities: [String] { Array(Set(store.tournaments.map(\.city))).sorted() }
  private var filtered: [Tournament] {
    let query = search.trimmingCharacters(in: .whitespacesAndNewlines)
    return store.tournaments.filter {
      (category == "全部" || $0.category == category)
        && (city == "全国" || $0.city == city)
        && (!openOnly || $0.canRegister)
        && (query.isEmpty
          || ($0.title + $0.city + $0.organizerName).localizedCaseInsensitiveContains(query))
    }.sorted { $0.startsAt < $1.startsAt }
  }
  private var months: [String] { Array(Set(filtered.map(\.monthKey))).sorted() }

  var body: some View {
    NavigationStack {
      ScrollView {
        VStack(alignment: .leading, spacing: 0) {
          HStack {
            Text("无人机足球").font(.title2.weight(.bold))
            Spacer()
            Menu {
              Picker("赛事城市", selection: $city) {
                Text("全国").tag("全国")
                ForEach(cities, id: \.self) { Text($0).tag($0) }
              }
            } label: {
              HStack(spacing: 5) {
                Image(systemName: "mappin.and.ellipse")
                Text(city)
                Image(systemName: "chevron.down").font(.caption2)
              }
              .font(.subheadline).frame(minHeight: 44)
            }.accessibilityLabel("选择赛事城市，当前\(city)")
          }.padding(.top, 8).padding(.bottom, 14)
          HStack(spacing: 10) {
            Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
            TextField("搜索赛事、城市或主办方", text: $search)
              .font(.subheadline).focused($searching).submitLabel(.search)
              .onSubmit { searching = false }
            if !search.isEmpty {
              Button {
                search = ""
              } label: {
                Image(systemName: "xmark.circle.fill").foregroundStyle(.secondary).frame(
                  width: 44, height: 44)
              }.accessibilityLabel("清除搜索")
            }
          }.padding(.leading, 14).padding(.trailing, 4).frame(minHeight: 48)
            .background(Theme.background, in: RoundedRectangle(cornerRadius: 10))
          HStack(spacing: 20) {
            ForEach(["全部", "20cm", "40cm"], id: \.self) { value in
              Button {
                category = value
                searching = false
              } label: {
                VStack(spacing: 9) {
                  Text(value == "全部" ? "全部赛事" : value + " 级").font(
                    .subheadline.weight(category == value ? .semibold : .regular))
                  Capsule().fill(category == value ? Theme.green : .clear).frame(height: 3)
                }.padding(.top, 16)
              }.foregroundStyle(category == value ? Theme.green : .secondary)
                .accessibilityAddTraits(category == value ? .isSelected : [])
            }
            Spacer(minLength: 0)
          }
          Divider()
          HStack {
            Text("\(filtered.count) 场赛事").font(.caption).foregroundStyle(.secondary)
            Spacer()
            Button {
              openOnly.toggle()
              searching = false
            } label: {
              Label("只看可报名", systemImage: openOnly ? "checkmark.circle.fill" : "circle")
                .font(.caption).frame(minHeight: 44)
            }.foregroundStyle(openOnly ? Theme.green : .secondary)
              .accessibilityValue(openOnly ? "已开启" : "已关闭")
          }.padding(.vertical, 6)
          SyncNotice()
          if store.isLoading && store.tournaments.isEmpty {
            ProgressView("正在加载赛事").font(.subheadline).frame(maxWidth: .infinity).padding(
              .vertical, 60)
          } else if filtered.isEmpty && store.error == nil {
            ContentUnavailableView {
              Label("暂无符合条件的赛事", systemImage: "magnifyingglass")
            } description: {
              Text("调整城市、设备级别或搜索关键词。")
            } actions: {
              Button("重置筛选") {
                search = ""
                category = "全部"
                city = "全国"
                openOnly = false
              }
            }
          }
          ForEach(months, id: \.self) { month in
            let events = filtered.filter { $0.monthKey == month }
            Text(events.first?.monthTitle ?? month)
              .font(.subheadline.weight(.semibold)).foregroundStyle(.secondary)
              .padding(.top, 18).padding(.bottom, 4)
            ForEach(events) { event in
              NavigationLink(value: event) { EventRow(event: event) }.buttonStyle(.plain)
              Divider().padding(.leading, 58)
            }
          }
        }.padding(.horizontal, 20).padding(.bottom, 28).frame(maxWidth: 680)
      }
      .frame(maxWidth: .infinity).background(Theme.page)
      .scrollDismissesKeyboard(.interactively)
      .toolbar(.hidden, for: .navigationBar)
      .navigationDestination(for: Tournament.self) { TournamentDetail(initial: $0) }
      .refreshable { await store.refresh() }
    }
  }
}

struct ParticipationGuide: View {
  var body: some View {
    List {
      Section("报名流程") {
        step("1", "准备队伍", "创建队伍并逐项填写名单，设备级别需要与赛事一致。")
        step("2", "选择赛事", "确认时间、场地、报名截止和赛事规则。")
        step("3", "提交报名", "选择队伍、核对当前名单并确认规则。提交后名单会保留为本次报名的快照。")
        step("4", "查看审核", "在“我的报名”中查看处理进度和审核说明。审核通过表示获得参赛名额，不代表已实际出场。")
      }
      Section("名单修改") {
        Text("队伍资料和人员名单可以在队伍详情中编辑。编辑只影响之后的报名，不改变已提交的名单。").font(.subheadline)
      }
      Section("当前版本") {
        Text("仅使用虚构的成年演示资料。真实身份、监护关系、赛程和成绩尚未接入。").font(.footnote).foregroundStyle(.secondary)
      }
    }.navigationTitle("参赛指南").navigationBarTitleDisplayMode(.inline)
  }
  private func step(_ number: String, _ title: String, _ text: String) -> some View {
    HStack(alignment: .top, spacing: 14) {
      Text(number).font(.headline).foregroundStyle(Theme.green).frame(width: 24)
      VStack(alignment: .leading, spacing: 8) {
        Text(title).font(.headline)
        Text(text).font(.subheadline).foregroundStyle(.secondary).lineSpacing(3)
      }
    }.padding(.vertical, 10)
  }
}
