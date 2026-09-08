import SwiftUI

/// A row of three tappable icon previews for Settings. The check mark is drawn (same
/// geometry as the real icon) so there's no dependency on loading app-icon assets.
struct IconPickerRow: View {
    @Binding var selection: AppIconOption
    var onChange: (AppIconOption) -> Void

    var body: some View {
        HStack(spacing: 16) {
            ForEach(AppIconOption.allCases) { option in
                VStack(spacing: 6) {
                    IconPreview(option: option)
                        .frame(width: 58, height: 58)
                        .overlay(
                            RoundedRectangle(cornerRadius: 13, style: .continuous)
                                .stroke(selection == option ? Theme.Palette.accent : .clear,
                                        lineWidth: 2.5)
                                .padding(-3)
                        )
                    Text(option.label)
                        .font(.caption2)
                        .foregroundStyle(selection == option ? Theme.Palette.accent : .secondary)
                }
                .contentShape(Rectangle())
                .onTapGesture {
                    guard selection != option else { return }
                    Haptics.selection()
                    selection = option
                    onChange(option)
                }
                .accessibilityElement(children: .ignore)
                .accessibilityLabel("\(option.label) icon")
                .accessibilityAddTraits(selection == option ? [.isSelected, .isButton] : .isButton)
            }
            Spacer(minLength: 0)
        }
        .padding(.vertical, 4)
    }
}

private struct IconPreview: View {
    let option: AppIconOption

    var body: some View {
        let (ground, mark) = option.colors
        RoundedRectangle(cornerRadius: 13, style: .continuous)
            .fill(Color(ground))
            .overlay(
                GeometryReader { geo in
                    let s = geo.size.width / 1024
                    Path { p in
                        p.move(to: CGPoint(x: 218 * s, y: 520 * s))
                        p.addLine(to: CGPoint(x: 292 * s, y: 594 * s))
                        p.addLine(to: CGPoint(x: 686 * s, y: 208 * s))
                    }
                    .stroke(Color(mark),
                            style: StrokeStyle(lineWidth: 104 * s, lineCap: .round, lineJoin: .round))
                }
            )
            .overlay(
                RoundedRectangle(cornerRadius: 13, style: .continuous)
                    .stroke(.black.opacity(0.08), lineWidth: 1)
            )
    }
}
