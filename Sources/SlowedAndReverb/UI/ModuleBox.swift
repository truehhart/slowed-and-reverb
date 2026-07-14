import SwiftUI

/// A rack unit: panel gradient, etched label row with a hairline divider,
/// and the module's content stacked below.
struct ModuleBox<Accessory: View, Content: View>: View {
  let title: String
  /// Rack modules fill the row's height; settings modules hug their content.
  var expands = true
  var centeredTitle = false
  @ViewBuilder var accessory: () -> Accessory
  @ViewBuilder var content: () -> Content

  init(
    _ title: String,
    expands: Bool = true,
    centeredTitle: Bool = false,
    @ViewBuilder accessory: @escaping () -> Accessory = { EmptyView() },
    @ViewBuilder content: @escaping () -> Content
  ) {
    self.title = title
    self.expands = expands
    self.centeredTitle = centeredTitle
    self.accessory = accessory
    self.content = content
  }

  var body: some View {
    VStack(alignment: .leading, spacing: 12) {
      if centeredTitle {
        HStack {
          Spacer(minLength: 0)
          titleLabel
          Spacer(minLength: 0)
        }
      } else {
        HStack(spacing: 10) {
          titleLabel
          Rectangle()
            .fill(Theme.line)
            .frame(height: 1)
            .frame(maxWidth: .infinity)
          accessory()
        }
      }
      content()
    }
    .padding(16)
    .frame(maxWidth: .infinity, alignment: .top)
    .frame(maxHeight: expands ? .infinity : nil, alignment: .top)
    .faceplateBackground()
    .background {
      RoundedRectangle(cornerRadius: Theme.radiusLG, style: .continuous)
        .fill(.black.opacity(0.001))
        .shadow(color: .black.opacity(0.5), radius: 3, y: 5)
    }
    .overlay(alignment: .topLeading) { screw.padding(9) }
    .overlay(alignment: .topTrailing) { screw.padding(9) }
    .overlay(alignment: .bottomLeading) { screw.padding(9) }
    .overlay(alignment: .bottomTrailing) { screw.padding(9) }
  }

  private var titleLabel: some View {
    Text(title)
      .font(Theme.mono(13.1, bold: true))
      .kerning(13.1 * 0.16)
      .textCase(.uppercase)
      .foregroundStyle(Theme.label)
      .lineLimit(1)
      .fixedSize()
  }

  private var screw: some View {
    Circle()
      .fill(
        RadialGradient(
          colors: [Theme.knobHi, Theme.rail],
          center: UnitPoint(x: 0.38, y: 0.32),
          startRadius: 0,
          endRadius: 5)
      )
      .overlay(Circle().strokeBorder(.black.opacity(0.5), lineWidth: 1))
      .frame(width: 7, height: 7)
      .allowsHitTesting(false)
  }
}
