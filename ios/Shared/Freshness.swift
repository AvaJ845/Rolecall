import Foundation

/// Turns a timestamp into the terse "12m ago" tail Rolecall shows on every row, and the
/// full "verified live · 12m ago" line.
///
/// A hand-rolled compact formatter rather than `RelativeDateTimeFormatter` on purpose:
/// the board is a trust surface, so the freshness string must be exact, stable across
/// locales, and unit-testable to the minute. `RelativeDateTimeFormatter` is used instead
/// for the spoken VoiceOver label, where its natural phrasing reads better.
enum Freshness {

    /// "just now" / "12m ago" / "3h ago" / "2d ago" / "5w ago" / "3mo ago" / "1y ago".
    static func compactAgo(_ interval: TimeInterval, now: Bool = true) -> String {
        let seconds = Int(interval.rounded())
        if seconds < 45 { return "just now" }
        let minutes = seconds / 60
        if minutes < 1 { return "just now" }
        if minutes < 60 { return "\(minutes)m ago" }
        let hours = minutes / 60
        if hours < 24 { return "\(hours)h ago" }
        let days = hours / 24
        if days < 7 { return "\(days)d ago" }
        let weeks = days / 7
        if weeks < 5 { return "\(weeks)w ago" }
        let months = days / 30
        if months < 12 { return "\(months)mo ago" }
        return "\(days / 365)y ago"
    }

    static func compactAgo(since date: Date, relativeTo reference: Date = Date()) -> String {
        compactAgo(reference.timeIntervalSince(date))
    }

    /// The full line under a row / on the detail view.
    /// `verified` is true once the engine (or the on-device `FreshnessChecker`) has
    /// confirmed the posting still looks live.
    static func line(for date: Date, verified: Bool, relativeTo reference: Date = Date()) -> String {
        let tail = compactAgo(since: date, relativeTo: reference)
        return verified ? "verified live · \(tail)" : "listed · \(tail)"
    }

    /// Natural-language phrasing for VoiceOver, e.g. "verified live 12 minutes ago".
    static func spokenLine(for date: Date, verified: Bool, relativeTo reference: Date = Date()) -> String {
        let f = RelativeDateTimeFormatter()
        f.unitsStyle = .full
        let phrase = f.localizedString(for: date, relativeTo: reference)
        return verified ? "Verified live \(phrase)" : "Listed \(phrase)"
    }
}
