import SwiftUI

@main
struct RolecallApp: App {

    @StateObject private var store = BoardStore()
    @StateObject private var tracked = TrackedRoles()
    @Environment(\.scenePhase) private var scenePhase

    var body: some Scene {
        WindowGroup {
            RoleListView()
                .environmentObject(store)
                .environmentObject(tracked)
                .tint(Theme.Palette.accent)
                .task {
                    await store.refresh()
                    tracked.prune(against: store.board)
                }
                .onChange(of: scenePhase) { _, phase in
                    // Mark the visit as the app leaves the foreground, so the next launch
                    // can quietly flag what arrived since.
                    if phase != .active { tracked.recordVisit() }
                }
        }
    }
}
