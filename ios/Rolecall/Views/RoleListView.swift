import SwiftUI

/// The whole app. Opens straight here — no tab bar, no onboarding, no welcome screen.
struct RoleListView: View {

    @EnvironmentObject private var store: BoardStore
    @State private var filter = RoleFilter()
    @State private var showingFilter = false
    @State private var now = Date()

    private var sections: [RoleSection] {
        RoleSectioning.sections(from: store.board.roles, filter: filter, now: now)
    }

    private var visibleCount: Int {
        sections.reduce(0) { $0 + $1.roles.count }
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 0, pinnedViews: [.sectionHeaders]) {
                    header

                    if store.board.roles.isEmpty {
                        EmptyStateView(
                            title: "No roles loaded yet",
                            message: "Rolecall could not reach the board. It will fill in as soon as you are back online.",
                            actionTitle: "Try again",
                            action: { Task { await store.refresh() } }
                        )
                        .padding(.top, 40)
                    } else if sections.isEmpty {
                        EmptyStateView(
                            title: "Nothing matches this filter",
                            message: "No \(filter.summary.lowercased()) right now. The board refreshes as companies post.",
                            actionTitle: filter.isActive ? "Clear filter" : nil,
                            action: filter.isActive ? { filter = RoleFilter() } : nil
                        )
                        .padding(.top, 40)
                    } else {
                        ForEach(sections) { section in
                            Section {
                                ForEach(Array(section.roles.enumerated()), id: \.element.id) { index, role in
                                    NavigationLink(value: role) {
                                        RoleRow(role: role, now: now)
                                    }
                                    .buttonStyle(.plain)
                                    if index < section.roles.count - 1 {
                                        Divider()
                                            .overlay(Theme.Palette.hairline)
                                            .padding(.leading, Theme.Metric.gutter)
                                    }
                                }
                            } header: {
                                sectionHeader(section.band.rawValue, count: section.roles.count)
                            }
                        }
                    }
                }
                .padding(.bottom, 32)
            }
            .rolecallBackground()
            .navigationDestination(for: Role.self) { role in
                RoleDetailView(role: role)
            }
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .principal) {
                    Text("Rolecall")
                        .font(.rolecallTitle(.headline))
                        .foregroundStyle(Theme.Palette.ink)
                        .accessibilityAddTraits(.isHeader)
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        showingFilter = true
                    } label: {
                        Image(systemName: filter.isActive
                              ? "line.3.horizontal.decrease.circle.fill"
                              : "line.3.horizontal.decrease.circle")
                    }
                    .accessibilityLabel(filter.isActive ? "Filter, active" : "Filter")
                }
            }
            .refreshable { await store.refresh() }
            .sheet(isPresented: $showingFilter) {
                FilterSheet(
                    filter: $filter,
                    counts: familyCounts,
                    remoteCount: store.board.roles.filter(\.isRemote).count
                )
                .presentationDetents([.medium, .large])
            }
        }
        .onReceive(Timer.publish(every: 60, on: .main, in: .common).autoconnect()) { now = $0 }
    }

    // MARK: pieces

    private var header: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("\(visibleCount) live \(visibleCount == 1 ? "role" : "roles")")
                .font(.rolecallDisplay(.title))
                .foregroundStyle(Theme.Palette.ink)
            Text(subtitle)
                .font(.subheadline)
                .foregroundStyle(Theme.Palette.inkSecondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, Theme.Metric.gutter)
        .padding(.top, 8)
        .padding(.bottom, 20)
        .accessibilityElement(children: .combine)
    }

    private var subtitle: String {
        var s = "Product-design roles straight from company career pages, each verified still open."
        if filter.isActive { s = "\(filter.summary). " + s }
        return s
    }

    private func sectionHeader(_ title: String, count: Int) -> some View {
        HStack(alignment: .firstTextBaseline) {
            Text(title)
                .font(.footnote.weight(.semibold))
                .foregroundStyle(Theme.Palette.inkSecondary)
                .textCase(.uppercase)
                .tracking(0.8)
            Spacer()
            Text("\(count)")
                .font(.footnote)
                .foregroundStyle(Theme.Palette.inkTertiary)
                .monospacedDigit()
        }
        .padding(.horizontal, Theme.Metric.gutter)
        .padding(.vertical, 8)
        .frame(maxWidth: .infinity)
        .background(Theme.Palette.paper.opacity(0.98))
        .accessibilityAddTraits(.isHeader)
    }

    private var familyCounts: [RoleFamily: Int] {
        Dictionary(grouping: store.board.roles, by: \.family).mapValues(\.count)
    }
}

#Preview {
    RoleListView().environmentObject(BoardStore())
}
