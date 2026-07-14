import SwiftUI

struct LibraryCarousel<Item: Identifiable, Content: View>: View {
  let items: [Item]
  @ViewBuilder let content: (Item) -> Content

  @State private var leadingItemID: Item.ID?

  private let cardWidth: CGFloat = 160
  private let spacing: CGFloat = 12

  var body: some View {
    GeometryReader { geometry in
      let visibleCount = max(1, Int((geometry.size.width + spacing) / (cardWidth + spacing)))
      ZStack {
        ScrollView(.horizontal) {
          LazyHStack(alignment: .top, spacing: spacing) {
            ForEach(items) { item in
              content(item)
                .id(item.id)
            }
          }
          .scrollTargetLayout()
          .padding(.vertical, 7)
          .padding(.horizontal, 2)
        }
        .scrollIndicators(.hidden)
        .scrollTargetBehavior(.viewAligned(limitBehavior: .alwaysByOne))
        .scrollPosition(id: $leadingItemID, anchor: .leading)
        .mask(
          edgeMask(
            showsLeading: currentIndex > 0,
            showsTrailing: currentIndex + visibleCount < items.count))

        if currentIndex > 0 {
          chevron(systemName: "chevron.left", label: "Previous card") {
            leadingItemID = items[currentIndex - 1].id
          }
          .frame(maxWidth: .infinity, alignment: .leading)
        }
        if currentIndex + visibleCount < items.count {
          chevron(systemName: "chevron.right", label: "Next card") {
            leadingItemID = items[currentIndex + 1].id
          }
          .frame(maxWidth: .infinity, alignment: .trailing)
        }
      }
      .animation(.easeOut(duration: 0.18), value: leadingItemID)
      .onChange(of: items.map(\.id)) {
        if let leadingItemID, !items.contains(where: { $0.id == leadingItemID }) {
          self.leadingItemID = items.first?.id
        }
      }
    }
  }

  private var currentIndex: Int {
    guard let leadingItemID else { return 0 }
    return items.firstIndex(where: { $0.id == leadingItemID }) ?? 0
  }

  private func edgeMask(showsLeading: Bool, showsTrailing: Bool) -> some View {
    HStack(spacing: 0) {
      LinearGradient(colors: [.clear, .black], startPoint: .leading, endPoint: .trailing)
        .frame(width: showsLeading ? 20 : 0)
      Rectangle().fill(.black)
      LinearGradient(colors: [.black, .clear], startPoint: .leading, endPoint: .trailing)
        .frame(width: showsTrailing ? 20 : 0)
    }
  }

  private func chevron(
    systemName: String, label: String, action: @escaping () -> Void
  ) -> some View {
    Button(action: action) {
      Image(systemName: systemName)
        .font(.system(size: 12, weight: .bold))
        .foregroundStyle(Theme.ivory)
        .frame(width: 28, height: 42)
        .background(
          LinearGradient(
            colors: [Theme.activeTop, Theme.rail], startPoint: .top, endPoint: .bottom),
          in: Capsule()
        )
        .overlay(Capsule().strokeBorder(Theme.line, lineWidth: 1))
        .shadow(color: .black.opacity(0.7), radius: 4, y: 2)
    }
    .buttonStyle(.plain)
    .accessibilityLabel(label)
  }
}
