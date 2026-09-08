import Foundation
import UserNotifications

/// Follow-up nudges for applications (Rolecall Plus). One local notification per
/// application, keyed by role id. Idempotent: `sync` schedules, reschedules or cancels to
/// match `application.followUpAt`.
enum Reminders {

    private static func id(for role: Role) -> String {
        "rolecall.followup." + String(role.id.hashValue, radix: 16)
    }

    /// Make the pending notification match the application's `followUpAt`. Cancels it when
    /// the date is nil, in the past, or the application has closed.
    @MainActor
    static func sync(role: Role, application: Application?) async {
        let center = UNUserNotificationCenter.current()
        let key = id(for: role)

        guard let app = application, let when = app.followUpAt,
              when > Date(), !app.stage.isClosed else {
            center.removePendingNotificationRequests(withIdentifiers: [key])
            return
        }
        guard await Digest.ensureAuthorised() else { return }

        let content = UNMutableNotificationContent()
        content.title = "Follow up with \(role.company)"
        content.body = "\(role.title) — you're at “\(app.stage.label)”."
        content.sound = .default

        let comps = Calendar.current.dateComponents(
            [.year, .month, .day, .hour, .minute], from: when)
        let trigger = UNCalendarNotificationTrigger(dateMatching: comps, repeats: false)
        try? await center.add(UNNotificationRequest(identifier: key, content: content, trigger: trigger))
    }

    @MainActor
    static func cancel(role: Role) {
        UNUserNotificationCenter.current()
            .removePendingNotificationRequests(withIdentifiers: [id(for: role)])
    }
}
