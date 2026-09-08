import SwiftUI

@main
struct RolecallApp: App {

    @StateObject private var store = BoardStore()
    @StateObject private var tracked = TrackedRoles()
    @StateObject private var settings = AppSettings()
    @Environment(\.scenePhase) private var scenePhase

    var body: some Scene {
        WindowGroup {
            RoleListView()
                .environmentObject(store)
                .environmentObject(tracked)
                .environmentObject(settings)
                .tint(Theme.Palette.accent)
                .preferredColorScheme(settings.appearance.colorScheme)
                .task {
                    await store.refresh()
                    tracked.prune(against: store.board)
                    if settings.autoClearOldRoles { tracked.autoClear() }
                }
                .onChange(of: scenePhase) { _, phase in
                    // Mark the visit as the app leaves the foreground, so the next launch
                    // can quietly flag what arrived since.
                    if phase != .active { tracked.recordVisit() }
                }
        }
    }
}
