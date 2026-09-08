import Foundation

/// The role families Rolecall covers. The product vertical is product-design; `pm` is
/// the secondary family the engine also classifies.
enum RoleFamily: String, Codable, CaseIterable, Identifiable, Hashable {
    case design
    case designEng = "design-eng"
    case research
    case pm

    var id: String { rawValue }

    /// Unknown future family values decode without throwing, so one new engine label
    /// never breaks the whole board.
    init(from decoder: Decoder) throws {
        let raw = try decoder.singleValueContainer().decode(String.self)
        self = RoleFamily(rawValue: raw) ?? .design
    }

    /// Shown in the filter sheet and on the detail view.
    var label: String {
        switch self {
        case .design: return "Design"
        case .designEng: return "Design Engineering"
        case .research: return "UX Research"
        case .pm: return "Product Management"
        }
    }

    /// A short form for dense contexts (row accessory, widget).
    var shortLabel: String {
        switch self {
        case .design: return "Design"
        case .designEng: return "Design Eng"
        case .research: return "Research"
        case .pm: return "PM"
        }
    }
}
