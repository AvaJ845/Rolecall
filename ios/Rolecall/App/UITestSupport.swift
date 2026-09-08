#if DEBUG
import SwiftUI

/// Puts the app into a known, populated state for App Store screenshot capture.
/// Only compiled in DEBUG and only runs when `-uitest-seed` is on the launch arguments,
/// so it can never affect a shipping build.
enum UITestSupport {

    static var isScreenshotRun: Bool {
        ProcessInfo.processInfo.arguments.contains("-uitest-seed")
    }

    /// Force the on-device freshness check to a fixed result (no network in the sim).
    static var forcedFreshness: FreshnessChecker.Status? {
        ProcessInfo.processInfo.arguments.contains("-uitest-live") ? .liveJustChecked : nil
    }

    @MainActor
    static func applyIfNeeded(store: BoardStore, tracked: TrackedRoles) {
        guard isScreenshotRun else { return }
        UIView.setAnimationsEnabled(false)
        tracked.wipeAll()   // start from a clean slate every capture run

        let design = store.board.roles.filter { RoleFilter.designFamilies.contains($0.family) }
        guard design.count > 12 else { return }

        // One role per company, so the seeded lists look like a real, varied search.
        var byCompany: [String: Role] = [:]
        for r in design where byCompany[r.company] == nil { byCompany[r.company] = r }
        let picks = byCompany.values.sorted { $0.company < $1.company }
        guard picks.count >= 6 else { return }

        for r in picks[3...5] { tracked.toggleSaved(r) }

        let stages: [(Role, ApplicationStage, Double, Double)] = [
            (picks[0], .recruiterScreen, -3, -1),
            (picks[1], .hiringManager, -8, -2),
            (picks[2], .offer, -16, -4),
        ]
        for (role, stage, appliedDays, updatedDays) in stages {
            var app = Application(appliedOn: Date().addingTimeInterval(appliedDays * 86_400))
            app.stage = stage
            app.updatedOn = Date().addingTimeInterval(updatedDays * 86_400)
            tracked.setStatus(.applied(app), for: role)
        }
    }
}
#endif
