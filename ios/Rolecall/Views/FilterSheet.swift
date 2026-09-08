import SwiftUI

/// Role-family multi-select and a remote-only toggle. A sheet, not a screen — it is a
/// refinement of the one list, and dismisses straight back to it.
struct FilterSheet: View {
    @Binding var filter: RoleFilter
    let counts: [RoleFamily: Int]
    let remoteCount: Int
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: Theme.Metric.sectionGap) {
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
                        Toggle(isOn: $filter.remoteOnly) {
                            VStack(alignment: .leading, spacing: 2) {
                                Text("Remote only").foregroundStyle(Theme.Palette.ink)
                                Text("\(remoteCount) remote roles")
                                    .font(.footnote)
                                    .foregroundStyle(Theme.Palette.inkSecondary)
                            }
                        }
                        .tint(Theme.Palette.accent)
                        .padding(16)
                        .cardSurface()
                    }
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
