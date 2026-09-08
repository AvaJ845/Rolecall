import SwiftUI

/// Shown when a filter matches nothing, or when the board itself is empty. Calm, and it
/// always offers the one useful action rather than a dead end.
struct EmptyStateView: View {
    let title: String
    let message: String
    /// A quiet SF Symbol that names the situation — "text.magnifyingglass" for a search
    /// that found nothing, "wifi.slash" when the board is unreachable, and so on.
    var icon: String = "circle.dashed"
    var actionTitle: String? = nil
    var action: (() -> Void)? = nil

    var body: some View {
        VStack(spacing: 14) {
            Image(systemName: icon)
                .font(.system(size: 32, weight: .light))
                .foregroundStyle(Theme.Palette.inkTertiary)
                .symbolRenderingMode(.hierarchical)
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
