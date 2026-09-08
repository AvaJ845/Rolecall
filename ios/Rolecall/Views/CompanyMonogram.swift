import SwiftUI

/// A small, calm identity tile for a company — its initial(s) on a tint derived
/// deterministically from the name. No network, no third-party logo service, no
/// fingerprinting: the list stays scannable and the privacy promise stays intact.
struct CompanyMonogram: View {
    let company: String
    var size: CGFloat = 40

    private var initials: String {
        let words = company
            .replacingOccurrences(of: "&", with: " ")
            .split(whereSeparator: { $0 == " " || $0 == "." || $0 == "-" })
            .filter { !$0.isEmpty }
        switch words.count {
        case 0: return "—"
        case 1: return String(words[0].prefix(1)).uppercased()
        default: return (words[0].prefix(1) + words[1].prefix(1)).uppercased()
        }
    }

    /// Stable hue per company so the same name always gets the same tile.
    private var seed: Int {
        company.unicodeScalars.reduce(0) { ($0 &* 31 &+ Int($1.value)) & 0x7fffffff }
    }

    private var tint: Color {
        // A warm, low-saturation palette that sits inside the paper world.
        let hues: [Double] = [0.03, 0.09, 0.13, 0.33, 0.55, 0.62, 0.75, 0.92]
        return Color(hue: hues[seed % hues.count], saturation: 0.22, brightness: 0.82)
    }

    var body: some View {
        RoundedRectangle(cornerRadius: size * 0.28, style: .continuous)
            .fill(tint.opacity(0.9))
            .overlay(
                Text(initials)
                    .font(.system(size: size * (initials.count > 1 ? 0.38 : 0.46),
                                  weight: .semibold, design: .serif))
                    .foregroundStyle(Theme.Palette.ink.opacity(0.85))
            )
            .overlay(
                RoundedRectangle(cornerRadius: size * 0.28, style: .continuous)
                    .stroke(Theme.Palette.ink.opacity(0.06), lineWidth: 1)
            )
            .frame(width: size, height: size)
            .accessibilityHidden(true)
    }
}
