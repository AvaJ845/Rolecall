import SwiftUI

/// The whole app. Opens straight here — no tab bar, no onboarding, no welcome screen.
struct RoleListView: View {

    @EnvironmentObject private var store: BoardStore
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    @State private var filter = RoleFilter()
    @State private var query = ""
    @State private var showingFilter = false
    @State private var now = Date()

    /// Sections are derived from board + filter + search, not recomputed on the 60s
    /// clock tick — the tick only refreshes the relative-time text inside each row.
    @State private var sections: [RoleSection] = []
    @State private var bannerOutcome: BoardStore.RefreshOutcome = .idle

    private var visibleCount: Int { sections.reduce(0) { $0 + $1.roles.count } }

    var body: some View {
        NavigationStack {
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 0, pinnedViews: [.sectionHeaders]) {
                    header
                    content
                }
                .padding(.bottom, 32)
            }
            .rolecallBackground()
            .overlay(alignment: .top) {
                RefreshBanner(outcome: bannerOutcome)
            }
            .navigationDestination(for: Role.self) { RoleDetailView(role: $0) }
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { toolbarContent }
            .searchable(text: $query, prompt: "Company or role")
            .autocorrectionDisabled()
            .textInputAutocapitalization(.never)
            .refreshable { await store.refresh(userInitiated: true) }
            .sheet(isPresented: $showingFilter, onDismiss: rebuild) {
                FilterSheet(
                    filter: $filter,
                    counts: familyCounts,
                    remoteCount: store.board.roles.filter(\.isRemote).count
                )
                .presentationDetents([.medium, .large])
            }
        }
        .onAppear(perform: rebuild)
        .onChange(of: store.board.generatedUTC) { rebuild() }
        .onChange(of: query) { rebuild() }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active { now = Date(); rebuild() }
        }
        .onChange(of: store.lastRefreshOutcome) { _, outcome in showBanner(outcome) }
        .onReceive(Timer.publish(every: 60, on: .main, in: .common).autoconnect()) { now = $0 }
    }

    // MARK: content

    @ViewBuilder
    private var content: some View {
        if store.board.roles.isEmpty {
            EmptyStateView(
                title: "No roles loaded yet",
                message: "Rolecall couldn't reach the board. It fills in the moment you're back online.",
                actionTitle: "Try again",
                action: { Task { await refresh() } }
            )
            .padding(.top, 40)
        } else if sections.isEmpty {
            filteredEmptyState
                .padding(.top, 40)
        } else {
            ForEach(sections) { section in
                sectionView(section)
            }
        }
    }

    @ViewBuilder
    private var filteredEmptyState: some View {
        let canClear = filter.isActive || !query.isEmpty
        EmptyStateView(
            title: emptyTitle,
            message: emptyMessage,
            actionTitle: canClear ? "Clear" : nil,
            action: canClear ? { clearAll() } : nil
        )
    }

    private func sectionView(_ section: RoleSection) -> some View {
        Section {
            let roles = section.roles
            ForEach(Array(roles.enumerated()), id: \.element.id) { index, role in
                NavigationLink(value: role) {
                    RoleRow(role: role, now: now)
                }
                .buttonStyle(.plain)
                if index < roles.count - 1 {
                    Divider()
                        .overlay(Theme.Palette.hairline)
                        .padding(.leading, Theme.Metric.gutter)
                }
            }
        } header: {
            sectionHeader(section.band.rawValue, count: section.roles.count)
        }
    }

    // MARK: pieces

    private var header: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("\(visibleCount) live \(visibleCount == 1 ? "role" : "roles")")
                .font(.rolecallDisplay(.title))
                .foregroundStyle(Theme.Palette.ink)
                .contentTransition(.numericText())
            Text(subtitle)
                .font(.subheadline)
                .foregroundStyle(Theme.Palette.inkSecondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, Theme.Metric.gutter)
        .padding(.top, 8)
        .padding(.bottom, 20)
        .accessibilityElement(children: .combine)
    }

    private var subtitle: String {
        if !query.isEmpty { return "Matching “\(query)”." }
        var s = "Product-design roles straight from company career pages, each verified still open."
        if filter.isActive { s = "\(filter.summary). " + s }
        return s
    }

    @ToolbarContentBuilder
    private var toolbarContent: some ToolbarContent {
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
        .background(Theme.Palette.paper)
        .accessibilityAddTraits(.isHeader)
    }

    private var emptyTitle: String {
        query.isEmpty ? "Nothing matches this filter" : "No roles match “\(query)”"
    }

    private var emptyMessage: String {
        if !query.isEmpty {
            return "Try a company name, or a role like “product designer”."
        }
        if filter.families.isEmpty {
            return "Choose at least one role family in the filter."
        }
        return "No \(filter.summary.lowercased()) right now. The board refreshes as companies post."
    }

    private var familyCounts: [RoleFamily: Int] {
        Dictionary(grouping: store.board.roles, by: \.family).mapValues(\.count)
    }

    // MARK: actions

    private func rebuild() {
        let searched = Self.search(store.board.roles, query: query)
        let next = RoleSectioning.sections(from: searched, filter: filter, now: now)
        if reduceMotion {
            sections = next
        } else {
            withAnimation(.easeOut(duration: 0.18)) { sections = next }
        }
    }

    private func refresh() async {
        await store.refresh(userInitiated: true)
    }

    private func clearAll() {
        Haptics.selection()
        filter = RoleFilter()
        query = ""
        rebuild()
    }

    private func showBanner(_ outcome: BoardStore.RefreshOutcome) {
        switch outcome {
        case let .updated(added) where added > 0:
            Haptics.success()
        case .unreachable:
            break
        default:
            return
        }
        withAnimation(reduceMotion ? .none : .spring(response: 0.4, dampingFraction: 0.9)) {
            bannerOutcome = outcome
        }
        Task {
            try? await Task.sleep(nanoseconds: 3_200_000_000)
            withAnimation(reduceMotion ? .none : .easeIn(duration: 0.25)) {
                bannerOutcome = .idle
            }
        }
    }

    /// Case- and diacritic-insensitive match on company or title.
    static func search(_ roles: [Role], query: String) -> [Role] {
        let q = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !q.isEmpty else { return roles }
        return roles.filter {
            $0.company.localizedCaseInsensitiveContains(q)
                || $0.title.localizedCaseInsensitiveContains(q)
        }
    }
}

#Preview {
    RoleListView().environmentObject(BoardStore())
}
