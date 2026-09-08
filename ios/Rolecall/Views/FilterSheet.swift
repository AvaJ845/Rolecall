import SwiftUI

/// Role-family multi-select and a remote-only toggle. A sheet, not a screen — it is a
/// refinement of the one list, and dismisses straight back to it.
struct FilterSheet: View {
    @Binding var filter: RoleFilter
    let counts: [RoleFamily: Int]
    let remoteCount: Int
    /// Companies on the board, for the "exclude" picker.
    var companies: [String] = []
    /// How many roles the given filter (plus the board's current search) would show —
    /// so the sheet can echo the result live as you adjust it.
    var matchCount: ((RoleFilter) -> Int)? = nil
    @Environment(\.dismiss) private var dismiss
    @Environment(\.isPlus) private var isPlus
    @State private var showPaywall = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: Theme.Metric.sectionGap) {
                    if let matchCount {
                        countLine(matchCount(filter))
                    }

                    section("Role family") {
                        VStack(spacing: 0) {
                            ForEach(RoleFamily.allCases) { family in
                                familyRow(family)
                                if family != RoleFamily.allCases.last {
                                    Divider().overlay(Theme.Palette.hairline)
                                }
                            }
                        }
                        .cardSurface()
                    }

                    section("Location") {
                        VStack(spacing: 0) {
                            Toggle(isOn: $filter.usAndRemoteOnly) {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text("US & remote only").foregroundStyle(Theme.Palette.ink)
                                    Text("Hide roles based outside the US")
                                        .font(.footnote)
                                        .foregroundStyle(Theme.Palette.inkSecondary)
                                }
                            }
                            .padding(16)
                            Divider().overlay(Theme.Palette.hairline)
                            Toggle(isOn: $filter.remoteOnly) {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text("Remote only").foregroundStyle(Theme.Palette.ink)
                                    Text("\(remoteCount) remote roles")
                                        .font(.footnote)
                                        .foregroundStyle(Theme.Palette.inkSecondary)
                                }
                            }
                            .padding(16)
                        }
                        .tint(Theme.Palette.accent)
                        .cardSurface()
                    }

                    advancedSection
                }
                .padding(Theme.Metric.gutter)
            }
            .rolecallBackground()
            .navigationTitle("Filter")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Reset") { filter = RoleFilter() }
                        .disabled(!filter.isActive)
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }.fontWeight(.semibold)
                }
            }
            .sheet(isPresented: $showPaywall) { PaywallView(feature: .advancedFilters) }
        }
    }

    /// Live count of what the current filter would show, at the top of the sheet.
    private func countLine(_ n: Int) -> some View {
        let noun = n == 1 ? "role" : "roles"
        let text = n == 0 ? "No roles match — loosen a filter"
            : filter.isActive ? "\(n) \(noun) match"
            : "\(n) \(noun)"
        return Text(text)
            .font(.subheadline.weight(.medium))
            .foregroundStyle(n == 0 ? Theme.Palette.caution : Theme.Palette.inkSecondary)
            .contentTransition(.numericText())
            .animation(.easeOut(duration: 0.2), value: n)
            .accessibilityLabel(n == 0 ? "No roles match the current filter"
                                : "\(n) \(noun) match the current filter")
    }

    // MARK: advanced (Plus)

    @ViewBuilder
    private var advancedSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 6) {
                Text("ADVANCED")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(Theme.Palette.inkTertiary)
                    .tracking(0.6)
                PlusBadge()
            }

            if isPlus {
                VStack(spacing: 0) {
                    seniorityRow
                    Divider().overlay(Theme.Palette.hairline)
                    postedWithinRow
                    if !excludedList.isEmpty {
                        Divider().overlay(Theme.Palette.hairline)
                        excludedRow
                    }
                }
                .cardSurface()
            } else {
                Button {
                    showPaywall = true
                } label: {
                    HStack(spacing: 12) {
                        Text("Filter by seniority, how recently a role was posted, and hide companies you're not interested in.")
                            .font(.footnote)
                            .foregroundStyle(Theme.Palette.inkSecondary)
                            .frame(maxWidth: .infinity, alignment: .leading)
                        Image(systemName: "chevron.forward")
                            .font(.footnote.weight(.semibold))
                            .foregroundStyle(Theme.Palette.inkTertiary)
                    }
                    .padding(16)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .cardSurface()
                .accessibilityHint("Opens Rolecall Plus")
            }
        }
    }

    private var seniorityRow: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Seniority").foregroundStyle(Theme.Palette.ink)
            FlowChips(Seniority.allCases.map(\.label),
                      isOn: { label in filter.seniorities.contains(where: { $0.label == label }) },
                      toggle: { label in
                          guard let s = Seniority.allCases.first(where: { $0.label == label }) else { return }
                          Haptics.selection()
                          if filter.seniorities.contains(s) { filter.seniorities.remove(s) }
                          else { filter.seniorities.insert(s) }
                      })
        }
        .padding(16)
    }

    private var postedWithinRow: some View {
        let options: [(String, Int?)] = [("Any time", nil), ("24 hours", 1), ("3 days", 3), ("Week", 7), ("Month", 30)]
        return VStack(alignment: .leading, spacing: 8) {
            Text("Posted within").foregroundStyle(Theme.Palette.ink)
            FlowChips(options.map(\.0),
                      isOn: { label in options.first(where: { $0.0 == label })?.1 == filter.postedWithinDays },
                      toggle: { label in
                          Haptics.selection()
                          filter.postedWithinDays = options.first(where: { $0.0 == label })?.1 ?? nil
                      })
        }
        .padding(16)
    }

    private var excludedList: [String] {
        companies.filter { !$0.isEmpty }.sorted().prefix(80).map { $0 }
    }

    private var excludedRow: some View {
        NavigationLink {
            ExcludedCompaniesView(excluded: $filter.excludedCompanies, all: excludedList)
        } label: {
            HStack {
                Text("Hidden companies").foregroundStyle(Theme.Palette.ink)
                Spacer()
                Text(filter.excludedCompanies.isEmpty ? "None" : "\(filter.excludedCompanies.count)")
                    .foregroundStyle(Theme.Palette.inkSecondary)
            }
            .padding(16)
        }
    }

    @ViewBuilder
    private func section<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title.uppercased())
                .font(.caption.weight(.semibold))
                .foregroundStyle(Theme.Palette.inkTertiary)
                .tracking(0.6)
            content()
        }
    }

    private func familyRow(_ family: RoleFamily) -> some View {
        let selected = filter.families.contains(family)
        return Button {
            Haptics.selection()
            if selected { filter.families.remove(family) } else { filter.families.insert(family) }
        } label: {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text(family.label).foregroundStyle(Theme.Palette.ink)
                    Text("\(counts[family] ?? 0) roles")
                        .font(.footnote)
                        .foregroundStyle(Theme.Palette.inkSecondary)
                }
                Spacer()
                Image(systemName: selected ? "checkmark.circle.fill" : "circle")
                    .foregroundStyle(selected ? Theme.Palette.accent : Theme.Palette.inkTertiary)
                    .font(.title3)
            }
            .padding(16)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(selected ? [.isSelected] : [])
    }
}

private extension View {
    func cardSurface() -> some View {
        background(Theme.Palette.surface)
            .clipShape(RoundedRectangle(cornerRadius: Theme.Metric.cardRadius, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: Theme.Metric.cardRadius, style: .continuous)
                    .stroke(Theme.Palette.hairline, lineWidth: 1)
            )
    }
}

/// A wrapping row of selectable chips.
struct FlowChips: View {
    let labels: [String]
    let isOn: (String) -> Bool
    let toggle: (String) -> Void

    init(_ labels: [String], isOn: @escaping (String) -> Bool, toggle: @escaping (String) -> Void) {
        self.labels = labels
        self.isOn = isOn
        self.toggle = toggle
    }

    var body: some View {
        FlowLayout(spacing: 8) {
            ForEach(labels, id: \.self) { label in
                let on = isOn(label)
                Button { toggle(label) } label: {
                    Text(label)
                        .font(.footnote.weight(.medium))
                        .padding(.horizontal, 12)
                        .padding(.vertical, 7)
                        .background(on ? Theme.Palette.accent : Theme.Palette.surfaceRaised)
                        .foregroundStyle(on ? .white : Theme.Palette.ink)
                        .clipShape(Capsule())
                        .overlay(Capsule().stroke(Theme.Palette.hairline, lineWidth: on ? 0 : 1))
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(on ? [.isSelected] : [])
            }
        }
    }
}

/// Minimal flow layout (iOS 16+ Layout).
struct FlowLayout: Layout {
    var spacing: CGFloat = 8

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let maxW = proposal.width ?? .infinity
        var x: CGFloat = 0, y: CGFloat = 0, rowH: CGFloat = 0
        for v in subviews {
            let s = v.sizeThatFits(.unspecified)
            if x + s.width > maxW, x > 0 { x = 0; y += rowH + spacing; rowH = 0 }
            x += s.width + spacing
            rowH = max(rowH, s.height)
        }
        return CGSize(width: maxW == .infinity ? x : maxW, height: y + rowH)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var x = bounds.minX, y = bounds.minY, rowH: CGFloat = 0
        for v in subviews {
            let s = v.sizeThatFits(.unspecified)
            if x + s.width > bounds.maxX, x > bounds.minX { x = bounds.minX; y += rowH + spacing; rowH = 0 }
            v.place(at: CGPoint(x: x, y: y), proposal: ProposedViewSize(s))
            x += s.width + spacing
            rowH = max(rowH, s.height)
        }
    }
}

/// Full-screen "hide companies" picker for the advanced filter.
struct ExcludedCompaniesView: View {
    @Binding var excluded: Set<String>
    let all: [String]
    @State private var query = ""

    private var shown: [String] {
        query.isEmpty ? all : all.filter { $0.localizedCaseInsensitiveContains(query) }
    }

    var body: some View {
        List {
            if !excluded.isEmpty {
                Section("Hidden") {
                    ForEach(excluded.sorted(), id: \.self) { c in
                        Button {
                            excluded.remove(c)
                        } label: {
                            HStack {
                                Text(c).foregroundStyle(Theme.Palette.ink)
                                Spacer()
                                Image(systemName: "checkmark").foregroundStyle(Theme.Palette.accent)
                            }
                        }
                    }
                }
            }
            Section("Companies on the board") {
                ForEach(shown.filter { !excluded.contains($0) }, id: \.self) { c in
                    Button { excluded.insert(c) } label: {
                        Text(c).foregroundStyle(Theme.Palette.ink)
                    }
                }
            }
        }
        .searchable(text: $query, prompt: "Company")
        .navigationTitle("Hidden companies")
        .navigationBarTitleDisplayMode(.inline)
    }
}
