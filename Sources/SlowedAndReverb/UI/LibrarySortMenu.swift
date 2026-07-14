import SwiftUI

struct LibrarySortMenu: View {
  let options: [String]
  @Binding var selection: String
  @Binding var isExpanded: Bool

  @FocusState private var focusedOption: String?
  @FocusState private var triggerFocused: Bool
  @State private var hovering = false

  var body: some View {
    Button {
      isExpanded.toggle()
    } label: {
      HStack(spacing: 6) {
        Text(selection.capitalized)
          .font(Theme.archivo(10.5, .semiBold))
          .lineLimit(1)
        Spacer(minLength: 2)
        Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
          .font(.system(size: 8, weight: .bold))
      }
      .foregroundStyle(hovering || isExpanded ? Theme.ivory : Theme.etch)
      .padding(.horizontal, 10)
      .frame(height: 36)
      .frame(maxWidth: .infinity)
      .background(
        LinearGradient(
          colors: [Theme.activeTop, Theme.activeBottom], startPoint: .top, endPoint: .bottom),
        in: RoundedRectangle(cornerRadius: 7, style: .continuous)
      )
      .overlay {
        RoundedRectangle(cornerRadius: 7, style: .continuous)
          .strokeBorder(isExpanded || hovering ? Theme.accentRing : Theme.line, lineWidth: 1)
      }
      .shadow(color: .black.opacity(0.6), radius: 2, y: 2)
    }
    .buttonStyle(.plain)
    .focused($triggerFocused)
    .onHover { hovering = $0 }
    .overlay(alignment: .topLeading) {
      if isExpanded {
        optionsPanel
          .offset(y: 40)
          .zIndex(1)
      }
    }
    .onChange(of: isExpanded) { _, expanded in
      if expanded {
        focusedOption = selection
      } else {
        focusedOption = nil
        triggerFocused = true
      }
    }
    .onExitCommand { isExpanded = false }
    .accessibilityLabel("Sort by")
    .accessibilityValue(selection.capitalized)
    .accessibilityHint(isExpanded ? "Choose a sort field" : "Show sort fields")
  }

  private var optionsPanel: some View {
    VStack(spacing: 3) {
      ForEach(options, id: \.self) { option in
        LibrarySortOption(
          label: option.capitalized,
          isSelected: selection == option
        ) {
          selection = option
          isExpanded = false
        }
        .focused($focusedOption, equals: option)
      }
    }
    .padding(4)
    .frame(maxWidth: .infinity)
    .fixedSize(horizontal: false, vertical: true)
    .background(
      LinearGradient(
        colors: [Theme.activeTop, Theme.panel2], startPoint: .top, endPoint: .bottom),
      in: RoundedRectangle(cornerRadius: 8, style: .continuous)
    )
    .overlay {
      RoundedRectangle(cornerRadius: 8, style: .continuous)
        .strokeBorder(Theme.accentRing.opacity(0.75), lineWidth: 1)
    }
    .shadow(color: .black.opacity(0.8), radius: 8, y: 5)
  }
}

private struct LibrarySortOption: View {
  let label: String
  let isSelected: Bool
  let action: () -> Void

  @State private var hovering = false

  var body: some View {
    Button(action: action) {
      HStack(spacing: 7) {
        Image(systemName: "checkmark")
          .font(.system(size: 8, weight: .bold))
          .opacity(isSelected ? 1 : 0)
        Text(label)
          .font(Theme.archivo(10.5, isSelected ? .semiBold : .medium))
          .lineLimit(1)
        Spacer(minLength: 0)
      }
      .foregroundStyle(isSelected || hovering ? Theme.ivory : Theme.etch)
      .padding(.horizontal, 8)
      .frame(height: 29)
      .frame(maxWidth: .infinity)
      .background {
        let shape = RoundedRectangle(cornerRadius: 5, style: .continuous)
        if isSelected {
          shape
            .fill(Theme.burgundy.opacity(0.15))
            .overlay(shape.strokeBorder(Theme.accentRing, lineWidth: 1))
        } else if hovering {
          shape.fill(Theme.metalHi)
        }
      }
      .contentShape(Rectangle())
    }
    .buttonStyle(.plain)
    .onHover { hovering = $0 }
    .accessibilityAddTraits(isSelected ? .isSelected : [])
  }
}
