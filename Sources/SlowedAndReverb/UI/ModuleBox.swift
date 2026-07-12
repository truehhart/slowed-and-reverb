import SwiftUI

/// A rack unit: panel gradient, etched label row with a hairline divider,
/// and the module's content stacked below.
struct ModuleBox<Accessory: View, Content: View>: View {
  let title: String
  /// Rack modules fill the row's height; settings modules hug their content.
  var expands = true
  @ViewBuilder var accessory: () -> Accessory
  @ViewBuilder var content: () -> Content

  init(
    _ title: String,
    expands: Bool = true,
    @ViewBuilder accessory: @escaping () -> Accessory = { EmptyView() },
    @ViewBuilder content: @escaping () -> Content
  ) {
    self.title = title
    self.expands = expands
    self.accessory = accessory
    self.content = content
  }

  var body: some View {
    VStack(alignment: .leading, spacing: 16) {
      HStack(spacing: 10) {
        Text(title)
          .font(Theme.mono(13.1, bold: true))
          .kerning(13.1 * 0.16)
          .textCase(.uppercase)
          .foregroundStyle(Theme.label)
          .lineLimit(1)
          .fixedSize()
        Rectangle()
          .fill(Theme.line)
          .frame(height: 1)
          .frame(maxWidth: .infinity)
        accessory()
      }
      content()
    }
    .padding(Theme.pad)
    .frame(maxWidth: .infinity, alignment: .top)
    .frame(maxHeight: expands ? .infinity : nil, alignment: .top)
    .panelBackground()
    .compositingGroup()
    .shadow(color: .black.opacity(0.5), radius: 3, y: 5)
  }
}
