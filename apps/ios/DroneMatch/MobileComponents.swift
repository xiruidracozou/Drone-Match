import SafariServices
import SwiftUI

enum TypeScale {
  static let title = Font.system(.title2, design: .default).weight(.semibold)
  static let heading = Font.system(.headline, design: .default).weight(.semibold)
  static let body = Font.system(.subheadline, design: .default)
  static let caption = Font.system(.caption, design: .default)
}
struct SectionHeading: View {
  let title: String
  var subtitle: String? = nil
  var body: some View {
    VStack(alignment: .leading, spacing: 4) {
      Text(title).font(TypeScale.heading).foregroundStyle(.primary)
      if let subtitle { Text(subtitle).font(TypeScale.caption).foregroundStyle(.secondary) }
    }.frame(maxWidth: .infinity, alignment: .leading)
  }
}
struct EmptyPanel: View {
  let title, detail, icon: String
  var body: some View {
    VStack(alignment: .leading, spacing: 12) {
      Image(systemName: icon).font(TypeScale.title).foregroundStyle(Theme.accent)
      Text(title).font(TypeScale.heading)
      Text(detail).font(TypeScale.body).foregroundStyle(.secondary).fixedSize(
        horizontal: false, vertical: true)
    }.frame(maxWidth: .infinity, alignment: .leading).padding(24)
      .background(Theme.surface, in: RoundedRectangle(cornerRadius: 16))
  }
}
struct FilterChip: View {
  let title: String
  let selected: Bool
  let action: () -> Void
  var body: some View {
    Button(action: action) {
      Text(title).font(TypeScale.body.weight(selected ? .semibold : .regular))
        .padding(.horizontal, 16).frame(minHeight: 44)
        .foregroundStyle(selected ? Theme.onAccent : .primary)
        .background(selected ? Theme.solidAccent : Theme.surface, in: Capsule())
    }.buttonStyle(.plain).accessibilityAddTraits(selected ? .isSelected : [])
  }
}
struct ExternalPage: UIViewControllerRepresentable {
  let url: URL
  func makeUIViewController(context: Context) -> SFSafariViewController {
    SFSafariViewController(url: url)
  }
  func updateUIViewController(_ controller: SFSafariViewController, context: Context) {}
}
struct UnreadBadge: View {
  let count: Int
  var body: some View {
    if count > 0 {
      Text(count > 99 ? "99+" : String(count)).font(TypeScale.caption.weight(.semibold))
        .foregroundStyle(.white).padding(.horizontal, 8).padding(.vertical, 4)
        .background(Theme.solidAccent, in: Capsule()).accessibilityLabel("\(count) 条未读留言")
    }
  }
}
