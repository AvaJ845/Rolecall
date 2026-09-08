import SwiftUI

/// Manage the reader's saved searches: apply one, toggle its alert (Plus), or delete it.
/// Reached from the filter menu on the board and from Settings.
struct SavedSearchesView: View {
    var onApply: ((SavedSearch) -> Void)? = nil

    @EnvironmentObject private var searches: SavedSearches
    @EnvironmentObject private var store: BoardStore
    @EnvironmentObject private var tracked: TrackedRoles
    @EnvironmentObject private var settings: AppSettings
    @Environment(\.isPlus) private var isPlus
    @Environment(\.dismiss) private var dismiss
    @State private var showPaywall = false

    var body: some View {
        Group {
            if searches.searches.isEmpty {
                EmptyStateView(
                    title: "No saved searches",
                    message: "From the board, set a filter and choose “Save this search”.",
                    icon: "bookmark"
                )
            } else {
                List {
                    Section {
                        ForEach(searches.searches) { search in
                            row(search)
                        }
                        .onDelete { searches.remove(atOffsets: $0) }
                    } footer: {
                        if !isPlus {
                            Text("The free plan keeps one saved search. Rolecall Plus keeps as many as you like and can alert you when a new role matches.")
                        }
                    }
                }
            }
        }
        .navigationTitle("Saved searches")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                Button("Done") { dismiss() }.fontWeight(.semibold)
            }
        }
        .sheet(isPresented: $showPaywall) { PaywallView(feature: .alerts) }
    }

    private func row(_ search: SavedSearch) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Button {
                onApply?(search)
                dismiss()
            } label: {
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(search.name)
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(Theme.Palette.ink)
                        Text("\(search.matchCount(in: store.board)) live now · \(search.filter.summary.lowercased())")
                            .font(.footnote)
                            .foregroundStyle(Theme.Palette.inkSecondary)
                            .lineLimit(1)
                    }
                    Spacer()
                    if onApply != nil {
                        Image(systemName: "arrow.forward")
                            .font(.footnote.weight(.semibold))
                            .foregroundStyle(Theme.Palette.inkTertiary)
                    }
                }
            }
            .buttonStyle(.plain)

            Toggle(isOn: alertBinding(for: search)) {
                HStack(spacing: 6) {
                    Text("Alert me for new matches").font(.footnote)
                    if !isPlus { PlusBadge() }
                }
            }
            .tint(Theme.Palette.accent)
        }
        .padding(.vertical, 4)
    }

    private func alertBinding(for search: SavedSearch) -> Binding<Bool> {
        Binding(
            get: { search.notify && isPlus },
            set: { on in
                guard isPlus else { showPaywall = true; return }
                Task {
                    if on, await Digest.ensureAuthorised() == false { return }
                    var s = search
                    s.notify = on
                    searches.update(s)
                    await Digest.reschedule(board: store.board, tracked: tracked, settings: settings)
                }
            }
        )
    }
}
