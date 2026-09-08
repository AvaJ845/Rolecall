import SwiftUI

/// Every role the reader has applied to, and where each one stands. Reached from
/// Settings. Active applications first; closed ones (rejected / withdrew) sink and dim.
struct AppliedReportView: View {
    @EnvironmentObject private var store: BoardStore
    @EnvironmentObject private var tracked: TrackedRoles

    private var entries: [(role: Role, application: Application)] {
        tracked.allApplications(in: store.board).sorted { a, b in
            if a.application.stage.isClosed != b.application.stage.isClosed {
                return !a.application.stage.isClosed
            }
            return a.application.updatedOn > b.application.updatedOn
        }
    }

    var body: some View {
        Group {
            if entries.isEmpty {
                EmptyStateView(
                    title: "No applications yet",
                    message: "When you apply to a role, mark it applied to track it here."
                )
            } else {
                List {
                    Section {
                        ForEach(entries, id: \.role.id) { entry in
                            row(entry.role, entry.application)
                        }
                    } footer: {
                        Text("\(entries.count) tracked · tap a stage to update it")
                    }
                }
            }
        }
        .navigationTitle("Applications")
        .navigationBarTitleDisplayMode(.inline)
    }

    private func row(_ role: Role, _ app: Application) -> some View {
        HStack(alignment: .top, spacing: 12) {
            CompanyMonogram(company: role.company, size: 38)
            VStack(alignment: .leading, spacing: 3) {
                Text(role.title)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(app.stage.isClosed ? .secondary : .primary)
                Text(role.company)
                    .font(.footnote)
                    .foregroundStyle(.secondary)

                Menu {
                    Picker("Stage", selection: stageBinding(for: role)) {
                        ForEach(ApplicationStage.allCases) { Text($0.label).tag($0) }
                    }
                } label: {
                    HStack(spacing: 4) {
                        Text(app.stage.label)
                        Image(systemName: "chevron.up.chevron.down").font(.caption2)
                    }
                    .font(.footnote.weight(.medium))
                    .foregroundStyle(app.stage.isClosed ? Color.secondary : Theme.Palette.accent)
                }
                .padding(.top, 2)

                Text("Applied \(app.appliedOn.formatted(date: .abbreviated, time: .omitted))")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
            Spacer(minLength: 0)
        }
        .padding(.vertical, 4)
        .swipeActions {
            Button(role: .destructive) {
                tracked.unmarkApplied(role)
            } label: {
                Label("Remove", systemImage: "trash")
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(role.title) at \(role.company). \(app.stage.label). Applied \(app.appliedOn.formatted(date: .abbreviated, time: .omitted)).")
    }

    private func stageBinding(for role: Role) -> Binding<ApplicationStage> {
        Binding(
            get: { tracked.application(for: role)?.stage ?? .applied },
            set: { newStage in
                Haptics.selection()
                tracked.updateApplication(for: role) { $0.stage = newStage }
            }
        )
    }
}
