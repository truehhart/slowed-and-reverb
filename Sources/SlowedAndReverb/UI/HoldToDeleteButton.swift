import SwiftUI

struct HoldToDeleteButton: View {
  let title: String?
  let enabled: Bool
  let accessibilityLabel: String
  let help: String
  let action: () -> Void

  @State private var arming = false
  @State private var fill: CGFloat = 0
  @State private var hovering = false
  @State private var holdTask: Task<Void, Never>?
  @State private var didTrigger = false

  private let holdDuration: TimeInterval = 0.6
  private let brimHeightRatio: CGFloat = 0.72

  init(
    _ title: String? = nil,
    enabled: Bool = true,
    accessibilityLabel: String,
    help: String,
    action: @escaping () -> Void
  ) {
    self.title = title
    self.enabled = enabled
    self.accessibilityLabel = accessibilityLabel
    self.help = help
    self.action = action
  }

  var body: some View {
    HStack(spacing: 6) {
      trashIcon
      if let title {
        Text(title)
          .font(Theme.archivo(10, .semiBold))
      }
    }
    .foregroundStyle(Theme.error)
    .padding(.horizontal, title == nil ? 6 : 9)
    .frame(height: title == nil ? 27 : 34)
    .background {
      shape.fill(backgroundStyle)
    }
    .overlay {
      shape.strokeBorder(
        hovering || arming ? Theme.accentRingStrong : Theme.lineSoft, lineWidth: 1)
    }
    .opacity(enabled ? 1 : 0.35)
    .contentShape(Rectangle())
    .onHover { hovering = enabled && $0 }
    .gesture(
      DragGesture(minimumDistance: 0)
        .onChanged { _ in beginHold() }
        .onEnded { _ in reset() }
    )
    .accessibilityElement(children: .ignore)
    .accessibilityLabel(accessibilityLabel)
    .accessibilityHint("Press and hold to confirm")
    .accessibilityAddTraits(.isButton)
    .accessibilityAction {
      guard enabled else { return }
      action()
    }
    .onDisappear { reset() }
    .help(help)
  }

  private var trashIcon: some View {
    ZStack {
      Image(systemName: "trash")
        .foregroundStyle(hovering || arming ? Theme.error : Theme.labelDim)
      Image(systemName: "trash.fill")
        .foregroundStyle(Theme.error)
        .mask(alignment: .bottom) {
          GeometryReader { proxy in
            VStack(spacing: 0) {
              Spacer(minLength: 0)
              Rectangle()
                .frame(height: proxy.size.height * brimHeightRatio * fill)
            }
          }
        }
        .opacity(arming ? 1 : 0)
    }
    .font(.system(size: 15, weight: .regular))
    .frame(width: 15, height: 15)
  }

  private var backgroundStyle: AnyShapeStyle {
    if title != nil {
      return AnyShapeStyle(
        LinearGradient(
          colors: [Theme.activeTop, Theme.activeBottom], startPoint: .top, endPoint: .bottom))
    }
    return AnyShapeStyle(arming ? Theme.error.opacity(0.06) : .clear)
  }

  private var shape: RoundedRectangle {
    RoundedRectangle(cornerRadius: 7, style: .continuous)
  }

  private func beginHold() {
    guard enabled, holdTask == nil, !didTrigger else { return }
    arming = true
    withAnimation(.linear(duration: holdDuration)) { fill = 1 }
    holdTask = Task {
      try? await Task.sleep(for: .seconds(holdDuration))
      guard !Task.isCancelled else { return }
      didTrigger = true
      holdTask = nil
      action()
    }
  }

  private func reset() {
    holdTask?.cancel()
    holdTask = nil
    arming = false
    didTrigger = false
    withAnimation(.easeOut(duration: 0.12)) { fill = 0 }
  }
}
