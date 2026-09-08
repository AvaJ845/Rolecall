import SwiftUI

/// A slim, self-dismissing line that drops from under the nav bar after a refresh —
/// only when there is something worth saying ("12 new roles", "couldn't refresh").
/// Silent on the common "nothing changed" case.
struct RefreshBanner: View {
    let outcome: BoardStore.RefreshOutcome
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var message: (icon: String, text: String, tint: Color)? {
        switch outcome {
        case let .updated(added) where added > 0:
            return ("arrow.down.circle.fill",
                    "\(added) new \(added == 1 ? "role" : "roles")",
                    Theme.Palette.verified)
        case .unreachable:
            return ("wifi.slash",
                    "Couldn't refresh — showing the last update",
                    Theme.Palette.inkSecondary)
        default:
            return nil
        }
    }

    var body: some View {
        if let message {
            HStack(spacing: 7) {
                Image(systemName: message.icon)
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(message.tint)
                Text(message.text)
                    .font(.footnote.weight(.medium))
                    .foregroundStyle(Theme.Palette.ink)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 8)
            .background(Theme.Palette.surface, in: Capsule())
            .overlay(Capsule().stroke(Theme.Palette.hairline, lineWidth: 1))
            .shadow(color: .black.opacity(0.06), radius: 8, y: 2)
            .padding(.top, 8)
            .transition(reduceMotion
                        ? .opacity
                        : .move(edge: .top).combined(with: .opacity))
            .accessibilityElement(children: .combine)
        }
    }
}
