import SwiftUI

/// The contract the other Fellows build against. None of this gates the free board —
/// it only decides whether a *convenience* feature is available, and, if not, offers the
/// paywall calmly.
///
/// Usage from a feature view:
///
///     @Environment(\.isPlus) private var isPlus
///     @State private var showPaywall = false
///
///     Button("Alert me for this search") {
///         if isPlus { enableAlert() } else { showPaywall = true }
///     }
///     .requiresPlus(.alerts, isPresented: $showPaywall)
///
/// `\.isPlus` is a plain Bool mirrored from `Store.isPlus`. `requiresPlus` presents
/// `PaywallView` as a sheet while `isPresented` is true and the customer is not already
/// subscribed (if they are, it just runs the action-free and dismisses).

// MARK: - PlusFeature

/// Identifies which convenience feature prompted the paywall. Used only for the paywall's
/// contextual headline and for local, telemetry-free logging — there is no analytics SDK
/// in this app and this value is never sent anywhere.
enum PlusFeature: String, CaseIterable, Identifiable {
    case alerts
    case savedSearches
    case advancedFilters
    case reminders
    case notes

    var id: String { rawValue }

    /// Short label for a settings row or an upsell prompt.
    var title: String {
        switch self {
        case .alerts:          return "Saved-search alerts"
        case .savedSearches:   return "Unlimited saved searches"
        case .advancedFilters: return "Advanced filters"
        case .reminders:       return "Follow-up reminders"
        case .notes:           return "Private notes"
        }
    }

    /// One calm sentence describing the feature, no urgency, no guilt.
    var blurb: String {
        switch self {
        case .alerts:
            return "Get a quiet notification when a new role matches a search you've saved."
        case .savedSearches:
            return "Keep as many saved searches as you like, each one checked as the board refreshes."
        case .advancedFilters:
            return "Filter by seniority, team, and compensation band, not just role family."
        case .reminders:
            return "Set a nudge to follow up on an application at the right time."
        case .notes:
            return "Keep a private note on each application — where it stands, who you spoke to."
        }
    }

    var symbol: String {
        switch self {
        case .alerts:          return "bell.badge"
        case .savedSearches:   return "bookmark"
        case .advancedFilters: return "line.3.horizontal.decrease"
        case .reminders:       return "clock.arrow.circlepath"
        case .notes:           return "square.and.pencil"
        }
    }
}

// MARK: - \.isPlus environment value

private struct IsPlusKey: EnvironmentKey {
    static let defaultValue = false
}

extension EnvironmentValues {
    /// Whether "Rolecall Plus" is currently active. Injected once at the app root from
    /// `Store.isPlus`; defaults to `false` everywhere it isn't provided.
    var isPlus: Bool {
        get { self[IsPlusKey.self] }
        set { self[IsPlusKey.self] = newValue }
    }
}

// MARK: - requiresPlus modifier

private struct RequiresPlusModifier: ViewModifier {
    let feature: PlusFeature
    @Binding var isPresented: Bool
    @Environment(\.isPlus) private var isPlus

    func body(content: Content) -> some View {
        content.sheet(isPresented: presentationBinding) {
            PaywallView(feature: feature)
        }
    }

    /// If the customer is already subscribed there is nothing to sell — swallow the
    /// request so a stale binding can never pop an empty paywall.
    private var presentationBinding: Binding<Bool> {
        Binding(
            get: { isPresented && !isPlus },
            set: { isPresented = $0 }
        )
    }
}

extension View {
    /// Presents the Plus paywall (as a sheet) while `isPresented` is true and the customer
    /// is not already subscribed. `feature` only sets the paywall's contextual headline.
    func requiresPlus(_ feature: PlusFeature, isPresented: Binding<Bool>) -> some View {
        modifier(RequiresPlusModifier(feature: feature, isPresented: isPresented))
    }
}

// MARK: - PlusBadge

/// A small "PLUS" marker. Icon + text, never colour alone, so it reads with any colour
/// vision and in both themes.
struct PlusBadge: View {
    var body: some View {
        HStack(spacing: 3) {
            Image(systemName: "sparkles")
                .font(.caption2.weight(.bold))
            Text("PLUS")
                .font(.caption2.weight(.bold))
                .tracking(0.6)
        }
        .foregroundStyle(Theme.Palette.accent)
        .padding(.horizontal, 6)
        .padding(.vertical, 2)
        .background(
            Capsule().stroke(Theme.Palette.accent.opacity(0.5), lineWidth: 1)
        )
        .accessibilityElement()
        .accessibilityLabel("Rolecall Plus feature")
    }
}

// MARK: - PlusUpsellRow

/// A contextual, non-nagging row for Settings or an inline empty state: what the feature
/// is, and a single tap to open the paywall. The caller owns the `isPresented` state and
/// attaches `.requiresPlus(feature, isPresented:)` (or presents `PaywallView` directly).
struct PlusUpsellRow: View {
    let feature: PlusFeature
    var action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 12) {
                Image(systemName: feature.symbol)
                    .font(.body)
                    .foregroundStyle(Theme.Palette.accent)
                    .frame(width: 26)
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 6) {
                        Text(feature.title)
                            .font(.callout.weight(.medium))
                            .foregroundStyle(Theme.Palette.ink)
                        PlusBadge()
                    }
                    Text(feature.blurb)
                        .font(.footnote)
                        .foregroundStyle(Theme.Palette.inkSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 8)
                Image(systemName: "chevron.forward")
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(Theme.Palette.inkTertiary)
                    .accessibilityHidden(true)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityHint("Opens Rolecall Plus")
    }
}
