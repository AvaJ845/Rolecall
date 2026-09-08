import UIKit

/// The whole haptic vocabulary of the app, in one place, kept deliberately sparse:
/// a light tick when the reader changes what they're looking at, and one notification
/// when the freshness check comes back with something they need to know. Nothing fires
/// on scroll, launch, or navigation — that would be noise, not craft.
@MainActor
enum Haptics {

    /// Filter toggled, filter reset.
    static func selection() {
        let g = UISelectionFeedbackGenerator()
        g.selectionChanged()
    }

    /// A pull-to-refresh that actually brought in new roles.
    static func success() {
        UINotificationFeedbackGenerator().notificationOccurred(.success)
    }

    /// The on-device check found the posting may have closed.
    static func warning() {
        UINotificationFeedbackGenerator().notificationOccurred(.warning)
    }
}
