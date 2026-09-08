import SwiftUI

/// Shown when a filter matches nothing, or when the board itself is empty. Calm, and it
/// always offers the one useful action rather than a dead end.
struct EmptyStateView: View {
    let title: String
    let message: String
    var actionTitle: String? = nil
    var action: (() -> Void)? = nil

    var body: some View {
        VStack(spacing: 14) {
            Image(systemName: "circle.dashed")
                .font(.system(size: 34, weight: .light))
                .foregroundStyle(Theme.Palette.inkTertiary)
                .accessibilityHidden(true)

            Text(title)
                .font(.rolecallTitle(.title3))
                .foregroundStyle(Theme.Palette.ink)
                .multilineTextAlignment(.center)

            Text(message)
                .font(.callout)
                .foregroundStyle(Theme.Palette.inkSecondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 320)

            if let actionTitle, let action {
                Button(actionTitle, action: action)
                    .font(.callout.weight(.semibold))
                    .buttonStyle(.borderless)
                    .tint(Theme.Palette.accent)
                    .padding(.top, 2)
            }
        }
        .padding(40)
        .frame(maxWidth: .infinity)
        .accessibilityElement(children: .combine)
    }
}
