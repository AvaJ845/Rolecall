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

    /// Job-search / recruiting products we must **never** seed as an employer. A
    /// competitor's name shown prominently on our own App Store screenshots is both an
    /// App Review risk and bad optics. Kept as an explicit exclusion set so a future edit
    /// to `curatedCompanies` can't quietly reintroduce one.
    private static let competitorCompanies: Set<String> = [
        "LinkedIn", "Indeed", "Dribbble", "Wellfound", "AngelList", "Glassdoor", "Otta",
        "ZipRecruiter", "Hired", "Monster", "Ladders", "Built In", "Handshake", "Welcome to the Jungle",
    ]

    /// Hand-picked, recognizable product-design employers with deliberately varied first
    /// letters — so the seeded lists look like a real, wide-ranging search and every
    /// company monogram renders a different initial (the old alphabetical sort made every
    /// tile an "A", which read like a rendering bug). None is a job-search competitor.
    /// Each is matched to a real posting from the bundled board below, so titles and
    /// locations stay authentic.
    private static let curatedCompanies: [String] = [
        "Figma", "Linear", "Notion", "Stripe", "Ramp", "Duolingo", "Airbnb",
        "Vercel", "Discord", "Robinhood", "Patreon", "Pinterest", "Reddit",
        "Brex", "Coinbase", "Chime",
    ]

    @MainActor
    static func applyIfNeeded(store: BoardStore, tracked: TrackedRoles) {
        guard isScreenshotRun else { return }
        UIView.setAnimationsEnabled(false)
        tracked.wipeAll()   // start from a clean slate every capture run

        let design = store.board.roles.filter { RoleFilter.designFamilies.contains($0.family) }
        guard design.count > 12 else { return }

        // One authentic posting per curated company. Prefer a US / US-remote role (the
        // board's promise, and what screenshot 04 is about), newest first; skip a company
        // the board has nothing clean for, and defensively skip any competitor.
        func bestRole(for company: String) -> Role? {
            let mine = design
                .filter { $0.company.caseInsensitiveCompare(company) == .orderedSame && !$0.looksNonUS }
                .sorted { $0.firstSeen > $1.firstSeen }
            let usLike = mine.first { role in
                role.isRemote || Self.usTokens.contains { (role.location ?? "").lowercased().contains($0) }
            }
            return usLike ?? mine.first
        }

        var pick: [Role] = []
        for company in curatedCompanies where !competitorCompanies.contains(company) {
            if let role = bestRole(for: company) { pick.append(role) }
        }
        guard pick.count >= 12 else { return }

        // Saved — a handful across visibly different companies / letters.
        for role in pick.suffix(5) { tracked.toggleSaved(role) }

        // Applications — the whole funnel, one company per stage, spread across the
        // alphabet. The Applied list sorts newest-applied first, so lay the `appliedOn`
        // offsets out so the list reads early-stage at the top down to an offer at the
        // bottom.
        let plan: [(stage: ApplicationStage, applied: Double, updated: Double)] = [
            (.applied,         -2,  -1),
            (.recruiterScreen, -4,  -1),
            (.hiringManager,   -8,  -3),
            (.interviewing,    -13, -2),
            (.finalRound,      -18, -4),
            (.offer,           -25, -6),
            (.recruiterScreen, -30, -7),
        ]
        for (i, step) in plan.enumerated() where i < pick.count {
            var app = Application(appliedOn: Date().addingTimeInterval(step.applied * 86_400))
            app.stage = step.stage
            app.updatedOn = Date().addingTimeInterval(step.updated * 86_400)
            tracked.setStatus(.applied(app), for: pick[i])
        }
    }

    /// Lowercased substrings that mark a location as US / US-remote for the seed's
    /// role preference. Not a filter — `Role.looksNonUS` already does the real work.
    private static let usTokens: [String] = [
        "united states", "usa", "u.s", "remote", "san francisco", "new york", "nyc",
        "seattle", "austin", "chicago", "boston", "los angeles", "denver", "atlanta",
        "portland", "pittsburgh", "north america",
    ]
}
#endif
