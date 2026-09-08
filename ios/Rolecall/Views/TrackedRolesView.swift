import SwiftUI

/// The reader's own lists: roles they saved, and roles they've applied to. Flat and
/// curated — no date bands. Reached from the segmented control on the main screen, which
/// only appears once there's something here.
struct TrackedRolesView: View {
    enum Kind { case saved, applied }

    let kind: Kind
    @EnvironmentObject private var store: BoardStore
    @EnvironmentObject private var tracked: TrackedRoles
    @State private var now = Date()

    /// Matches RoleListView: divider starts where the row text starts.
    @ScaledMetric(relativeTo: .body) private var monogramTile: CGFloat = 40

    private var roles: [Role] {
        let matching: (RoleStatus) -> Bool = kind == .saved ? \.isSaved : \.isApplied
        return tracked.roles(in: store.board, matching: matching)
            .sorted { lhs, rhs in
                switch kind {
                case .saved:
                    return lhs.freshnessDate > rhs.freshnessDate
                case .applied:
                    let l = tracked.status(for: lhs)?.appliedDate ?? .distantPast
                    let r = tracked.status(for: rhs)?.appliedDate ?? .distantPast
                    return l > r
                }
            }
    }

    var body: some View {
        Group {
            if roles.isEmpty {
                EmptyStateView(title: emptyTitle, message: emptyMessage,
                               icon: kind == .saved ? "heart" : "checkmark.circle")
                    .padding(.top, 40)
            } else {
                LazyVStack(alignment: .leading, spacing: 0) {
                    ForEach(Array(roles.enumerated()), id: \.element.id) { index, role in
                        NavigationLink(value: role) {
                            RoleRow(role: role, now: now, status: tracked.status(for: role),
                                    showsStatusBadge: false)
                        }
                        .buttonStyle(.plain)
                        .contextMenu { RoleContextMenu(role: role) }
                        if index < roles.count - 1 {
                            Divider().overlay(Theme.Palette.hairline)
                                .padding(.leading, Theme.Metric.gutter + monogramTile + 13)
                        }
                    }
                }
            }
        }
        .onReceive(Timer.publish(every: 300, on: .main, in: .common).autoconnect()) { now = $0 }
    }

    private var emptyTitle: String {
        kind == .saved ? "No saved roles yet" : "No applications tracked yet"
    }

    private var emptyMessage: String {
        kind == .saved
            ? "Press and hold any role, or tap the heart on a role, to save it here."
            : "Open a role, tap Apply, then mark it applied to keep track of it here."
    }
}

/// Shared long-press menu for a role — used on every list.
struct RoleContextMenu: View {
    let role: Role
    @EnvironmentObject private var tracked: TrackedRoles

    var body: some View {
        let status = tracked.status(for: role)

        Button {
            Haptics.selection()
            tracked.toggleSaved(role)
        } label: {
            Label(status?.isSaved == true ? "Remove from Saved" : "Save",
                  systemImage: status?.isSaved == true ? "heart.slash" : "heart")
        }

        if status?.isApplied == true {
            Button {
                tracked.unmarkApplied(role)
            } label: {
                Label("Unmark as applied", systemImage: "arrow.uturn.backward")
            }
        } else {
            Button {
                Haptics.selection()
                tracked.markApplied(role)
            } label: {
                Label("Mark as applied", systemImage: "checkmark.circle")
            }
        }

        ShareLink(item: role.url,
                  subject: Text("\(role.title) — \(role.company)"),
                  message: Text("\(role.title) at \(role.company), open on Rolecall")) {
            Label("Share role", systemImage: "square.and.arrow.up")
        }

        if status != .notInterested {
            Divider()
            Button(role: .destructive) {
                Haptics.selection()
                tracked.setNotInterested(role)
            } label: {
                Label("Not interested", systemImage: "eye.slash")
            }
        }
    }
}
