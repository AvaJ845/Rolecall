import AppIntents
import Foundation

/// Siri / Shortcuts entry points. Everything reads the board snapshot the app writes to
/// the App Group container — no network, no account, works with the app closed.

struct OpenBoardIntent: AppIntent {
    static var title: LocalizedStringResource = "Open the board"
    static var description = IntentDescription("Opens Rolecall to today's verified design roles.")
    static var openAppWhenRun = true

    func perform() async throws -> some IntentResult { .result() }
}

struct NewRolesCountIntent: AppIntent {
    static var title: LocalizedStringResource = "Count new design roles"
    static var description = IntentDescription("How many product-design roles were listed in the last day.")
    static var openAppWhenRun = false

    func perform() async throws -> some IntentResult & ProvidesDialog {
        let board = SharedContainer.currentBoard() ?? .empty
        let dayAgo = Date().addingTimeInterval(-86_400)
        let n = board.roles.filter {
            RoleFilter.designFamilies.contains($0.family) && !$0.looksNonUS && $0.firstSeen > dayAgo
        }.count
        let dialog: IntentDialog = n == 0
            ? "No new product-design roles in the last day."
            : "\(n) new product-design \(n == 1 ? "role" : "roles") in the last day, all verified live."
        return .result(dialog: dialog)
    }
}

struct RolesAtCompanyIntent: AppIntent {
    static var title: LocalizedStringResource = "Design roles at a company"
    static var description = IntentDescription("Check how many design roles a company has open on Rolecall.")
    static var openAppWhenRun = false

    @Parameter(title: "Company") var company: String

    static var parameterSummary: some ParameterSummary {
        Summary("Design roles at \(\.$company)")
    }

    func perform() async throws -> some IntentResult & ProvidesDialog {
        let board = SharedContainer.currentBoard() ?? .empty
        let matches = board.roles.filter {
            $0.company.localizedCaseInsensitiveContains(company)
                && RoleFilter.designFamilies.contains($0.family)
                && !$0.looksNonUS
        }
        let dialog: IntentDialog
        if let name = matches.first?.company, !matches.isEmpty {
            dialog = "\(matches.count) product-design \(matches.count == 1 ? "role" : "roles") at \(name)."
        } else {
            dialog = "No product-design roles at \(company) on Rolecall right now."
        }
        return .result(dialog: dialog)
    }
}

struct SavedRolesCountIntent: AppIntent {
    static var title: LocalizedStringResource = "Count saved roles"
    static var openAppWhenRun = false

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        let tracked = TrackedRoles()
        let s = tracked.savedCount, a = tracked.appliedCount
        var parts: [String] = []
        if s > 0 { parts.append("\(s) saved") }
        if a > 0 { parts.append("\(a) \(a == 1 ? "application" : "applications") in progress") }
        let dialog: IntentDialog = parts.isEmpty
            ? "You haven't saved any roles yet."
            : "You have \(parts.joined(separator: " and "))."
        return .result(dialog: dialog)
    }
}

struct RolecallShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(
            intent: OpenBoardIntent(),
            phrases: [
                "Open \(.applicationName)",
                "Show my \(.applicationName) board",
                "Show design jobs in \(.applicationName)",
            ],
            shortTitle: "Open board",
            systemImageName: "checkmark.seal.fill"
        )
        AppShortcut(
            intent: NewRolesCountIntent(),
            phrases: [
                "How many new roles in \(.applicationName)",
                "What's new in \(.applicationName)",
                "New design jobs in \(.applicationName)",
            ],
            shortTitle: "New roles",
            systemImageName: "sparkles"
        )
        AppShortcut(
            intent: SavedRolesCountIntent(),
            phrases: [
                "How many roles have I saved in \(.applicationName)",
                "My saved roles in \(.applicationName)",
            ],
            shortTitle: "Saved roles",
            systemImageName: "heart.fill"
        )
    }
}
