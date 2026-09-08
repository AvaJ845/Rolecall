import SwiftUI

/// The whole app. Opens straight here — no tab bar, no onboarding, no welcome screen.
struct RoleListView: View {

    enum Mode: String, CaseIterable { case board = "Board", saved = "Saved", applied = "Applied" }

    @EnvironmentObject private var store: BoardStore
    @EnvironmentObject private var tracked: TrackedRoles
    @EnvironmentObject private var searches: SavedSearches
    @Environment(\.isPlus) private var isPlus
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    /// Aligns the between-row divider with the start of a row's text, tracking the
    /// monogram tile as it grows with Dynamic Type (tile 40 + 13 spacing at default).
    @ScaledMetric(relativeTo: .body) private var monogramTile: CGFloat = 40

    @State private var filter = RoleFilter.loadPersisted()
    @State private var query = ""
    @State private var showingFilter = false
    @State private var showingSettings = false
    @State private var showingSaveSearch = false
    @State private var showingSavedSearches = false
    @State private var showPaywall = false
    @State private var searchName = ""
    @State private var mode: Mode = .board
    @State private var now = Date()

    /// Sections are derived from board + filter + search + hidden set, not recomputed on
    /// the 60s clock tick — the tick only refreshes the relative-time text in each row.
    @State private var sections: [RoleSection] = []
    @State private var bannerOutcome: BoardStore.RefreshOutcome = .idle

    private var visibleCount: Int { sections.reduce(0) { $0 + $1.roles.count } }

    var body: some View {
        NavigationStack {
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 0, pinnedViews: [.sectionHeaders]) {
                    header
                    if tracked.hasActivity { modePicker }
                    switch mode {
                    case .board:   boardContent
                    case .saved:   TrackedRolesView(kind: .saved)
                    case .applied: TrackedRolesView(kind: .applied)
                    }
                }
                .padding(.bottom, 32)
            }
            .rolecallBackground()
            .overlay(alignment: .top) { RefreshBanner(outcome: bannerOutcome) }
            .navigationDestination(for: Role.self) { RoleDetailView(role: $0) }
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { toolbarContent }
            .searchable(text: $query,
                        placement: .navigationBarDrawer(displayMode: .automatic),
                        prompt: "Company or role")
            .autocorrectionDisabled()
            .textInputAutocapitalization(.never)
            .refreshable { await store.refresh(userInitiated: true) }
            .sheet(isPresented: $showingFilter, onDismiss: rebuild) {
                FilterSheet(
                    filter: $filter,
                    counts: familyCounts,
                    remoteCount: store.board.roles.filter(\.isRemote).count,
                    companies: uniqueCompanies,
                    matchCount: matchCount
                )
                .presentationDetents([.medium, .large])
            }
            .sheet(isPresented: $showingSettings) {
                SettingsView()
            }
            .sheet(isPresented: $showingSavedSearches) {
                NavigationStack {
                    SavedSearchesView { search in
                        filter = search.filter
                        query = search.query
                        rebuild()
                    }
                }
            }
            .sheet(isPresented: $showPaywall) { PaywallView(feature: .savedSearches) }
            .alert("Name this search", isPresented: $showingSaveSearch) {
                TextField("e.g. Staff, remote", text: $searchName)
                Button("Save") {
                    let name = searchName.trimmingCharacters(in: .whitespaces)
                    searches.add(SavedSearch(name: name.isEmpty ? filter.summary : name,
                                             filter: filter, query: query))
                    searchName = ""
                }
                Button("Cancel", role: .cancel) { searchName = "" }
            } message: {
                Text("Rolecall keeps this filter so you can jump back to it.")
            }
        }
        .onAppear(perform: rebuild)
        .onChange(of: store.board.generatedUTC) { rebuild() }
        .onChange(of: query) { rebuild() }
        .onChange(of: filter) { _, f in f.persist(); rebuild() }
        .onChange(of: tracked.states) { rebuild() }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active { now = Date(); rebuild() }
        }
        .onChange(of: store.lastRefreshOutcome) { _, outcome in showBanner(outcome) }
        .onReceive(Timer.publish(every: 300, on: .main, in: .common).autoconnect()) { now = $0 }
    }

    // MARK: board content

    @ViewBuilder
    private var boardContent: some View {
        if store.board.roles.isEmpty {
            EmptyStateView(
                title: "No roles loaded yet",
                message: "Rolecall couldn't reach the board. It fills in the moment you're back online.",
                icon: "wifi.slash",
                actionTitle: "Try again",
                action: { Task { await refresh() } }
            )
            .padding(.top, 40)
        } else if sections.isEmpty {
            filteredEmptyState.padding(.top, 40)
        } else {
            ForEach(sections) { section in
                sectionView(section, showHeader: sections.count > 1)
            }
        }
    }

    @ViewBuilder
    private var filteredEmptyState: some View {
        let canClear = filter.isActive || !query.isEmpty
        EmptyStateView(
            title: emptyTitle,
            message: emptyMessage,
            icon: query.isEmpty ? "line.3.horizontal.decrease" : "text.magnifyingglass",
            actionTitle: canClear ? "Clear" : nil,
            action: canClear ? { clearAll() } : nil
        )
    }

    @ViewBuilder
    private func sectionView(_ section: RoleSection, showHeader: Bool) -> some View {
        Section {
            let roles = section.roles
            ForEach(Array(roles.enumerated()), id: \.element.id) { index, role in
                NavigationLink(value: role) {
                    RoleRow(role: role, now: now,
                            status: tracked.status(for: role),
                            isNew: tracked.isNew(role))
                }
                .buttonStyle(.plain)
                .contextMenu { RoleContextMenu(role: role) }
                if index < roles.count - 1 {
                    Divider()
                        .overlay(Theme.Palette.hairline)
                        .padding(.leading, Theme.Metric.gutter + monogramTile + 13)  // clears the monogram
                }
            }
        } header: {
            if showHeader {
                sectionHeader(section.band.rawValue, count: section.roles.count)
            }
        }
    }

    // MARK: pieces

    private var header: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(headline)
                .font(.rolecallDisplay(.title))
                .foregroundStyle(Theme.Palette.ink)
                .contentTransition(.numericText())
            Text(subtitle)
                .font(.subheadline)
                .foregroundStyle(Theme.Palette.inkSecondary)
                .fixedSize(horizontal: false, vertical: true)

            if mode == .board && !store.board.roles.isEmpty {
                Label {
                    Text("All \(visibleCount) checked live · \(Freshness.compactAgo(since: store.board.generatedUTC, relativeTo: now))")
                } icon: {
                    Image(systemName: "checkmark.seal.fill")
                }
                .font(.footnote.weight(.medium))
                .foregroundStyle(Theme.Palette.verified)
                .padding(.top, 4)
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityLabel("All \(visibleCount) roles were checked against their company's own careers feed \(Freshness.compactAgo(since: store.board.generatedUTC, relativeTo: now)).")
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, Theme.Metric.gutter)
        .padding(.top, 8)
        .padding(.bottom, mode == .board ? 20 : 12)
        .accessibilityElement(children: .combine)
    }

    private var modePicker: some View {
        Picker("View", selection: $mode.animation(.easeInOut(duration: 0.15))) {
            ForEach(Mode.allCases, id: \.self) { m in
                Text(label(for: m)).tag(m)
            }
        }
        .pickerStyle(.segmented)
        .padding(.horizontal, Theme.Metric.gutter)
        .padding(.bottom, 16)
    }

    private func label(for m: Mode) -> String {
        switch m {
        case .board: return "Board"
        case .saved: return tracked.savedCount > 0 ? "Saved \(tracked.savedCount)" : "Saved"
        case .applied: return tracked.appliedCount > 0 ? "Applied \(tracked.appliedCount)" : "Applied"
        }
    }

    private var headline: String {
        switch mode {
        case .board:   return "\(visibleCount) live \(visibleCount == 1 ? "role" : "roles")"
        case .saved:   return "Saved"
        case .applied: return "Applications"
        }
    }

    private var subtitle: String {
        switch mode {
        case .saved:   return "Roles you're keeping an eye on."
        case .applied: return "Track where each one stands."
        case .board:
            if !query.isEmpty { return "Matching “\(query)”." }
            var s = "Product-design roles straight from company career pages, each verified still open."
            if filter.isActive { s = "\(filter.summary). " + s }
            return s
        }
    }

    @ToolbarContentBuilder
    private var toolbarContent: some ToolbarContent {
        ToolbarItem(placement: .principal) {
            Text("Rolecall")
                .font(.rolecallTitle(.headline))
                .foregroundStyle(Theme.Palette.ink)
                .accessibilityAddTraits(.isHeader)
        }
        ToolbarItem(placement: .topBarLeading) {
            Button {
                showingSettings = true
            } label: {
                Image(systemName: "gearshape")
            }
            .accessibilityLabel("Settings")
        }
        ToolbarItem(placement: .topBarTrailing) {
            Menu {
                Button {
                    showingFilter = true
                } label: { Label("Filter", systemImage: "line.3.horizontal.decrease") }

                Button {
                    if searches.canAddWithoutPlus || isPlus {
                        showingSaveSearch = true
                    } else {
                        showPaywall = true
                    }
                } label: { Label("Save this search", systemImage: "bookmark") }
                .disabled(mode != .board)

                if !searches.searches.isEmpty {
                    Button {
                        showingSavedSearches = true
                    } label: { Label("Saved searches (\(searches.searches.count))", systemImage: "bookmark.fill") }
                }
            } label: {
                Image(systemName: filter.isActive
                      ? "line.3.horizontal.decrease.circle.fill"
                      : "line.3.horizontal.decrease.circle")
            }
            .accessibilityLabel(filter.isActive ? "Filter and searches, filter active" : "Filter and searches")
            .disabled(mode != .board)
        }
    }

    private var uniqueCompanies: [String] {
        Array(Set(store.board.roles.map(\.company))).sorted()
    }

    /// Roles a candidate filter would show, honouring the board's current search and the
    /// hidden set — feeds the live count in the filter sheet.
    private func matchCount(_ candidate: RoleFilter) -> Int {
        let visible = store.board.roles.filter { tracked.status(for: $0)?.isHidden != true }
        return Self.search(visible, query: query).filter { candidate.matches($0, now: now) }.count
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
        guard mode == .board else { return }
        let visible = store.board.roles.filter { tracked.status(for: $0)?.isHidden != true }
        let searched = Self.search(visible, query: query)
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
    RoleListView()
        .environmentObject(BoardStore())
        .environmentObject(TrackedRoles())
        .environmentObject(AppSettings())
        .environmentObject(Store())
        .environmentObject(SavedSearches())
}
