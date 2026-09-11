import SwiftUI

struct HomePhoto: View {
  let name: String
  var body: some View {
    if let url = Bundle.main.url(forResource: name, withExtension: "jpg", subdirectory: "Media"),
      let image = UIImage(contentsOfFile: url.path)
    {
      Image(uiImage: image).resizable().scaledToFill()
    }
  }
}

struct HomeHighlights: View {
  @Environment(\.dynamicTypeSize) private var typeSize
  @Environment(\.scenePhase) private var phase
  @Environment(\.accessibilityReduceMotion) private var reduceMotion
  @Environment(\.accessibilityVoiceOverEnabled) private var voiceOver
  @ScaledMetric(relativeTo: .headline) private var height = 148.0
  let suspended: Bool
  let onReplay, onGuide: () -> Void
  @State private var page = 0
  @State private var paused = false
  @State private var touching = false
  @State private var visible = false
  @State private var nextRotation = Date().addingTimeInterval(6)
  private var rotating: Bool {
    visible && phase == .active && !reduceMotion && !voiceOver && !paused && !suspended
  }
  var body: some View {
    VStack(spacing: 0) {
      TabView(selection: $page) {
        highlight(
          image: "DroneSoccerField", eyebrow: "赛事影像 · 全国", title: "感受空中对抗的魅力", action: "观看官方回放",
          onTap: onReplay
        ).tag(0)
        highlight(
          image: "DroneSoccer", eyebrow: "新手入门", title: "认识你的第一颗飞行球", action: "器材与参赛准备",
          onTap: onGuide
        ).tag(1)
      }.tabViewStyle(.page(indexDisplayMode: .never)).frame(height: height)
        .clipShape(RoundedRectangle(cornerRadius: 16))
        .simultaneousGesture(
          DragGesture(minimumDistance: 0).onChanged { _ in
            touching = true
            nextRotation = Date().addingTimeInterval(6)
          }.onEnded { _ in
            touching = false
            nextRotation = Date().addingTimeInterval(6)
          })
      (typeSize.isAccessibilitySize
        ? AnyLayout(VStackLayout(alignment: .leading, spacing: 0))
        : AnyLayout(HStackLayout(spacing: 0))) {
          Text("项目实拍资料图").font(.caption2).foregroundStyle(.secondary)
          if !typeSize.isAccessibilitySize { Spacer() }
          HStack(spacing: 0) {
            ForEach(0..<2) { index in
              Button {
                withAnimation(reduceMotion ? nil : .easeInOut(duration: 0.25)) { page = index }
              } label: {
                Capsule().fill(page == index ? Theme.accent : Color.secondary.opacity(0.25))
                  .frame(width: page == index ? 16 : 6, height: 4).frame(width: 44, height: 44)
              }.accessibilityLabel("轮播第\(index + 1)页")
                .accessibilityAddTraits(page == index ? .isSelected : [])
            }
            if !reduceMotion && !voiceOver {
              Button {
                paused.toggle()
              } label: {
                Image(systemName: paused ? "play.fill" : "pause.fill").font(.system(size: 12))
                  .frame(
                    width: 44, height: 44)
              }.accessibilityLabel(paused ? "继续自动轮播" : "暂停自动轮播")
            }
          }
        }.frame(maxWidth: .infinity, alignment: .leading)
    }.onAppear {
      visible = true
      nextRotation = Date().addingTimeInterval(6)
    }
    .onDisappear {
      visible = false
      touching = false
    }
    .onChange(of: page) { _, _ in nextRotation = Date().addingTimeInterval(6) }
    .task(id: rotating) {
      guard rotating else { return }
      nextRotation = Date().addingTimeInterval(6)
      while !Task.isCancelled {
        do { try await Task.sleep(for: .seconds(1)) } catch { return }
        if !touching && Date() >= nextRotation {
          withAnimation(.easeInOut(duration: 0.35)) { page = (page + 1) % 2 }
          nextRotation = Date().addingTimeInterval(6)
        }
      }
    }
  }
  private func highlight(
    image: String, eyebrow: String, title: String, action: String, onTap: @escaping () -> Void
  ) -> some View {
    Button(action: onTap) {
      ZStack(alignment: .leading) {
        GeometryReader { proxy in
          HomePhoto(name: image).frame(width: proxy.size.width, height: proxy.size.height).clipped()
        }
        LinearGradient(
          colors: [Color.black.opacity(0.75), Color.black.opacity(0.3), .clear],
          startPoint: .leading, endPoint: .trailing)
        VStack(alignment: .leading, spacing: 8) {
          Text(eyebrow).font(.caption.weight(.medium)).foregroundStyle(.white.opacity(0.85))
          Text(title).font(.headline).fixedSize(horizontal: false, vertical: true)
          Label(action, systemImage: "arrow.right.circle.fill").font(.caption.weight(.medium))
            .padding(.top, 4)
        }.padding(20).foregroundStyle(.white)
      }.frame(maxWidth: .infinity, alignment: .leading).contentShape(Rectangle())
    }.buttonStyle(.plain).accessibilityLabel(eyebrow + "，" + title + "，" + action)
  }
}

struct HomePromotionSlot: View {
  let promotion: HomePromotion
  var body: some View {
    Link(destination: promotion.destination) {
      HStack(spacing: 16) {
        HomePhoto(name: promotion.imageName).frame(width: 88, height: 72).clipped()
          .clipShape(RoundedRectangle(cornerRadius: 8))
        VStack(alignment: .leading, spacing: 6) {
          Text(promotion.title).font(.headline).foregroundStyle(.primary)
          Text(promotion.subtitle).font(.caption).foregroundStyle(.secondary)
          Text("广告").font(.caption2).foregroundStyle(.secondary)
        }
        Spacer(minLength: 0)
        Image(systemName: "arrow.up.right").font(.caption)
      }.padding(12).background(Theme.surface, in: RoundedRectangle(cornerRadius: 12))
    }.buttonStyle(.plain)
  }
}
