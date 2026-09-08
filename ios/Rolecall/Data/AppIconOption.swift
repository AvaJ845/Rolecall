import UIKit

/// The alternate app icons offered in Settings. The primary ("Classic") ships from the
/// user's icon package; Midnight and Mono are the same roll-call tick recoloured.
enum AppIconOption: String, CaseIterable, Identifiable {
    case classic, midnight, mono

    var id: String { rawValue }

    var label: String {
        switch self {
        case .classic: return "Classic"
        case .midnight: return "Midnight"
        case .mono: return "Mono"
        }
    }

    /// The asset-catalog app-icon set name, or nil for the primary icon.
    var alternateName: String? {
        switch self {
        case .classic: return nil
        case .midnight: return "AppIcon-Midnight"
        case .mono: return "AppIcon-Mono"
        }
    }

    /// Ground and mark colours, mirroring `generate_variants.py`, for the in-app preview.
    var colors: (ground: UIColor, mark: UIColor) {
        switch self {
        case .classic:  return (UIColor(red: 0.953, green: 0.933, blue: 0.890, alpha: 1),
                                UIColor(red: 0.129, green: 0.122, blue: 0.110, alpha: 1))
        case .midnight: return (UIColor(red: 0.122, green: 0.110, blue: 0.102, alpha: 1),
                                UIColor(red: 0.953, green: 0.933, blue: 0.890, alpha: 1))
        case .mono:     return (.white, .black)
        }
    }

    @MainActor
    static var current: AppIconOption {
        let name = UIApplication.shared.alternateIconName
        return allCases.first { $0.alternateName == name } ?? .classic
    }

    @MainActor
    static func apply(_ option: AppIconOption) async {
        guard UIApplication.shared.supportsAlternateIcons else { return }
        guard UIApplication.shared.alternateIconName != option.alternateName else { return }
        try? await UIApplication.shared.setAlternateIconName(option.alternateName)
    }
}
