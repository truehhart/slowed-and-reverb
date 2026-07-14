import SwiftUI

struct LibrarySortMenu: View {
  let options: [String]
  @Binding var selection: String

  var body: some View {
    Menu {
      ForEach(options, id: \.self) { option in
        Button {
          selection = option
        } label: {
          if selection == option {
            Label(option.capitalized, systemImage: "checkmark")
          } else {
            Text(option.capitalized)
          }
        }
      }
    } label: {
      HStack(spacing: 6) {
        Text(selection.capitalized)
          .font(Theme.archivo(10.5, .semiBold))
          .lineLimit(1)
        Spacer(minLength: 2)
        Image(systemName: "chevron.down")
          .font(.system(size: 8, weight: .bold))
      }
      .foregroundStyle(Theme.etch)
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
          .strokeBorder(Theme.line, lineWidth: 1)
      }
      .shadow(color: .black.opacity(0.6), radius: 2, y: 2)
    }
    .menuStyle(.borderlessButton)
    .accessibilityLabel("Sort by")
    .accessibilityValue(selection.capitalized)
  }
}
