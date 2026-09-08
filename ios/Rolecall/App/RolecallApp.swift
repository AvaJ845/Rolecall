import SwiftUI

@main
struct RolecallApp: App {

    @StateObject private var store = BoardStore()
    @StateObject private var tracked = TrackedRoles()
    @StateObject private var settings = AppSettings()
    @StateObject private var plus = Store()
    @Environment(\.scenePhase) private var scenePhase

    var body: some Scene {
        WindowGroup {
            RoleListView()
                .environmentObject(store)
                .environmentObject(tracked)
                .environmentObject(settings)
                .environmentObject(plus)
                .environment(\.isPlus, plus.isPlus)
                .tint(Theme.Palette.accent)
                .preferredColorScheme(settings.appearance.colorScheme)
                .task {
                    #if DEBUG
                    if UITestSupport.isScreenshotRun {
                        UITestSupport.applyIfNeeded(store: store, tracked: tracked)
                        return
                    }
                    #endif
                    await store.refresh()
                    tracked.prune(against: store.board)
                    if settings.autoClearOldRoles { tracked.autoClear() }
                }
                .onChange(of: scenePhase) { _, phase in
                    guard phase != .active else { return }
                    // Mark the visit so the next launch can flag what's new, and refresh
                    // the digests against the board we currently hold.
                    tracked.recordVisit()
                    Digest.scheduleBackgroundRefresh()
                    Task {
                        await Digest.reschedule(board: store.board, tracked: tracked, settings: settings)
                    }
                }
        }
        .backgroundTask(.appRefresh(Digest.refreshTaskID)) {
            await Digest.runBackgroundRefresh()
        }
    }
}
