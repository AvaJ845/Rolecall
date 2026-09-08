import SwiftUI

@main
struct RolecallApp: App {

    @StateObject private var store = BoardStore()

    var body: some Scene {
        WindowGroup {
            RoleListView()
                .environmentObject(store)
                .tint(Theme.Palette.accent)
                .task { await store.refresh() }
        }
    }
}
