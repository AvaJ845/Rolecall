import SwiftUI

/// Every user-facing preference, in one place. On-device only (App Group UserDefaults) —
/// nothing here is an account setting and nothing syncs.
enum AppearanceChoice: String, CaseIterable, Codable, Identifiable {
    case system, light, dark
    var id: String { rawValue }
    var label: String {
        switch self {
        case .system: return "System"
        case .light: return "Light"
        case .dark: return "Dark"
        }
    }
    var colorScheme: ColorScheme? {
        switch self {
        case .system: return nil
        case .light: return .light
        case .dark: return .dark
        }
    }
}

@MainActor
final class AppSettings: ObservableObject {

    @Published var appearance: AppearanceChoice {
        didSet { defaults.set(appearance.rawValue, forKey: Keys.appearance) }
    }
    /// Auto-remove applied roles + not-interested entries older than 90 days.
    @Published var autoClearOldRoles: Bool {
        didSet { defaults.set(autoClearOldRoles, forKey: Keys.autoClear) }
    }
    /// A once-a-day local notification with the count of roles listed in the last 24h.
    @Published var morningRead: Bool {
        didSet { defaults.set(morningRead, forKey: Keys.morningRead) }
    }
    /// A once-a-week local notification recapping the week's new roles.
    @Published var weeklyRecap: Bool {
        didSet { defaults.set(weeklyRecap, forKey: Keys.weeklyRecap) }
    }
    /// Name of the alternate app icon, or nil for the primary.
    @Published var alternateIconName: String? {
        didSet { defaults.set(alternateIconName, forKey: Keys.icon) }
    }

    private let defaults: UserDefaults

    private enum Keys {
        static let appearance = "settings.appearance.v1"
        static let autoClear = "settings.autoClear.v1"
        static let morningRead = "settings.morningRead.v1"
        static let weeklyRecap = "settings.weeklyRecap.v1"
        static let icon = "settings.icon.v1"
    }

    init(defaults: UserDefaults = SharedContainer.defaults) {
        self.defaults = defaults
        self.appearance = (defaults.string(forKey: Keys.appearance))
            .flatMap(AppearanceChoice.init) ?? .system
        self.autoClearOldRoles = defaults.bool(forKey: Keys.autoClear)
        self.morningRead = defaults.bool(forKey: Keys.morningRead)
        self.weeklyRecap = defaults.bool(forKey: Keys.weeklyRecap)
        self.alternateIconName = defaults.string(forKey: Keys.icon)
    }

    /// Settings → "Reset everything". Wipes preferences too; the caller also wipes
    /// TrackedRoles.
    func resetAll() {
        appearance = .system
        autoClearOldRoles = false
        morningRead = false
        weeklyRecap = false
        alternateIconName = nil
    }
}
