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
  let items: [PublishedContent]
  let suspended: Bool
  let onSelect: (PublishedContent) -> Void
  @State private var page = 0
  @State private var paused = false
  @State private var touching = false
  @State private var visible = false
  @State private var nextRotation = Date().addingTimeInterval(6)
  private var rotating: Bool {
    items.count > 1 && visible && phase == .active && !reduceMotion && !voiceOver && !paused
      && !suspended
  }
  var body: some View {
    VStack(spacing: 0) {
      TabView(selection: $page) {
        ForEach(Array(items.enumerated()), id: \.element.id) { index, item in
          highlight(item: item).tag(index)
        }
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
          Text(items.indices.contains(page) ? items[page].attribution : "").font(.caption2)
            .foregroundStyle(.secondary)
          if !typeSize.isAccessibilitySize { Spacer() }
          HStack(spacing: 0) {
            ForEach(0..<items.count, id: \.self) { index in
              Button {
                withAnimation(reduceMotion ? nil : .easeInOut(duration: 0.25)) { page = index }
              } label: {
                Capsule().fill(page == index ? Theme.accent : Color.secondary.opacity(0.25))
                  .frame(width: page == index ? 16 : 6, height: 4).frame(width: 44, height: 44)
              }.accessibilityLabel("轮播第\(index + 1)页")
                .accessibilityAddTraits(page == index ? .isSelected : [])
            }
            if items.count > 1 && !reduceMotion && !voiceOver {
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
    .onChange(of: items) { _, _ in page = 0 }
    .onChange(of: page) { _, _ in nextRotation = Date().addingTimeInterval(6) }
    .task(id: rotating) {
      guard rotating else { return }
      nextRotation = Date().addingTimeInterval(6)
      while !Task.isCancelled {
        do { try await Task.sleep(for: .seconds(1)) } catch { return }
        if !touching && Date() >= nextRotation {
          withAnimation(.easeInOut(duration: 0.35)) { page = (page + 1) % items.count }
          nextRotation = Date().addingTimeInterval(6)
        }
      }
    }
  }
  private func highlight(item: PublishedContent) -> some View {
    Button {
      onSelect(item)
    } label: {
      ZStack(alignment: .leading) {
        GeometryReader { proxy in
          PublishedImage(assetId: item.assetId).frame(
            width: proxy.size.width, height: proxy.size.height
          ).clipped()
        }
        LinearGradient(
          colors: [Color.black.opacity(0.75), Color.black.opacity(0.3), .clear],
          startPoint: .leading, endPoint: .trailing)
        VStack(alignment: .leading, spacing: 8) {
          Text(item.kind == "hero" ? "无人机足球" : "").font(.caption.weight(.medium)).foregroundStyle(
            .white.opacity(0.85))
          Text(item.title).font(.headline).fixedSize(horizontal: false, vertical: true)
          Label(item.subtitle, systemImage: "arrow.right.circle.fill").font(
            .caption.weight(.medium)
          )
          .padding(.top, 4)
        }.padding(20).foregroundStyle(.white)
      }.frame(maxWidth: .infinity, alignment: .leading).contentShape(Rectangle())
    }.buttonStyle(.plain).accessibilityLabel(item.title + "，" + item.subtitle)
  }
}

struct HomePromotionSlot: View {
  let promotion: PublishedContent
  var body: some View {
    if let url = promotion.externalURL {
      Link(destination: url) {
        HStack(spacing: 16) {
          PublishedImage(assetId: promotion.assetId).frame(width: 88, height: 72).clipped()
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
}
