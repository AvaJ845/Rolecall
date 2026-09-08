import SwiftUI

/// Every role the reader has applied to, and where each one stands. Reached from
/// Settings. Active applications first; closed ones (rejected / withdrew) sink and dim.
struct AppliedReportView: View {
    @EnvironmentObject private var store: BoardStore
    @EnvironmentObject private var tracked: TrackedRoles
    @Environment(\.isPlus) private var isPlus
    @State private var showPaywall = false

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
                    message: "When you apply to a role, mark it applied to track it here.",
                    icon: "tray"
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
        .toolbar {
            if !entries.isEmpty {
                ToolbarItem(placement: .topBarTrailing) {
                    ShareLink(items: ApplicationExport.files(entries)) {
                        Image(systemName: "square.and.arrow.up")
                    }
                    .accessibilityLabel("Export applications")
                }
            }
        }
        .sheet(isPresented: $showPaywall) { PaywallView(feature: .reminders) }
    }

    private func row(_ role: Role, _ app: Application) -> some View {
        VStack(alignment: .leading, spacing: 8) {
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

            if !app.stage.isClosed {
                reminderControl(role, app)
            }
            if isPlus {
                TextField("Add a note…", text: noteBinding(for: role), axis: .vertical)
                    .font(.footnote)
                    .lineLimit(1...4)
                    .textFieldStyle(.plain)
            } else if !app.note.isEmpty {
                Text(app.note)
                    .font(.footnote).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(.vertical, 4)
        .swipeActions {
            Button(role: .destructive) {
                Task { await Reminders.sync(role: role, application: nil) }
                tracked.unmarkApplied(role)
            } label: {
                Label("Remove", systemImage: "trash")
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(role.title) at \(role.company). \(app.stage.label). Applied \(app.appliedOn.formatted(date: .abbreviated, time: .omitted)).")
    }

    @ViewBuilder
    private func reminderControl(_ role: Role, _ app: Application) -> some View {
        if isPlus {
            HStack(spacing: 6) {
                Image(systemName: "clock.arrow.circlepath").font(.caption2)
                if let due = app.followUpAt {
                    Text("Follow up \(due.formatted(.relative(presentation: .named)))")
                        .font(.caption2)
                    Button("Clear") {
                        tracked.setFollowUp(nil, for: role)
                        Task { await Reminders.sync(role: role, application: tracked.application(for: role)) }
                    }
                    .font(.caption2.weight(.semibold))
                } else {
                    DatePicker("Remind me", selection: reminderBinding(for: role),
                               in: Date()..., displayedComponents: [.date, .hourAndMinute])
                        .labelsHidden()
                        .font(.caption2)
                }
            }
            .foregroundStyle(Theme.Palette.accent)
        } else {
            Button {
                showPaywall = true
            } label: {
                Label("Set a follow-up reminder", systemImage: "clock.arrow.circlepath")
                    .font(.caption2)
                    .foregroundStyle(Theme.Palette.inkTertiary)
            }
            .buttonStyle(.plain)
        }
    }

    private func reminderBinding(for role: Role) -> Binding<Date> {
        Binding(
            get: { tracked.application(for: role)?.followUpAt ?? Date().addingTimeInterval(3 * 86_400) },
            set: { date in
                Haptics.selection()
                tracked.setFollowUp(date, for: role)
                Task { await Reminders.sync(role: role, application: tracked.application(for: role)) }
            }
        )
    }

    private func noteBinding(for role: Role) -> Binding<String> {
        Binding(
            get: { tracked.application(for: role)?.note ?? "" },
            set: { text in tracked.setNote(text, for: role) }
        )
    }

    private func stageBinding(for role: Role) -> Binding<ApplicationStage> {
        Binding(
            get: { tracked.application(for: role)?.stage ?? .applied },
            set: { newStage in
                Haptics.selection()
                tracked.updateApplication(for: role) { $0.stage = newStage }
                Task { await Reminders.sync(role: role, application: tracked.application(for: role)) }
            }
        )
    }
}
