import SwiftUI

struct SettingsView: View {
    @EnvironmentObject private var settings: AppSettings
    @EnvironmentObject private var tracked: TrackedRoles
    @EnvironmentObject private var store: BoardStore
    @Environment(\.dismiss) private var dismiss
    @State private var confirmingWipe = false
    @State private var iconOption: AppIconOption = .current

    private var version: String {
        let v = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0"
        let b = Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "1"
        return "\(v) (\(b))"
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Appearance") {
                    Picker("Theme", selection: $settings.appearance) {
                        ForEach(AppearanceChoice.allCases) { Text($0.label).tag($0) }
                    }
                    .pickerStyle(.segmented)
                }

                if UIApplication.shared.supportsAlternateIcons {
                    Section("App icon") {
                        IconPickerRow(selection: $iconOption) { option in
                            settings.alternateIconName = option.alternateName
                            Task { await AppIconOption.apply(option) }
                        }
                    }
                }

                Section("Applications") {
                    NavigationLink {
                        AppliedReportView()
                    } label: {
                        HStack {
                            Label("Applied roles", systemImage: "checkmark.circle")
                            Spacer()
                            Text("\(tracked.appliedCount)")
                                .foregroundStyle(.secondary)
                                .monospacedDigit()
                        }
                    }
                    Toggle(isOn: $settings.autoClearOldRoles) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Tidy up automatically")
                            Text("Remove applications with no activity for 90 days")
                                .font(.footnote).foregroundStyle(.secondary)
                        }
                    }
                }

                Section("Privacy") {
                    Text("Rolecall keeps everything on this device. No account, no analytics, no trackers. Nothing you do here is sent anywhere.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }

                Section {
                    Button(role: .destructive) { confirmingWipe = true } label: {
                        Text("Clear all my data")
                    }
                } footer: {
                    Text("Removes every saved role, application, and preference. The job board itself is unaffected.")
                }

                Section {
                    LabeledContent("Version", value: version)
                } footer: {
                    Text("Rolecall — product-design jobs, straight from the source.")
                }
            }
            .navigationTitle("Settings")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }.fontWeight(.semibold)
                }
            }
            .alert("Clear all your data?", isPresented: $confirmingWipe) {
                Button("Clear everything", role: .destructive) {
                    tracked.wipeAll()
                    settings.resetAll()
                    iconOption = .classic
                    Task { await AppIconOption.apply(.classic) }
                }
                Button("Cancel", role: .cancel) { }
            } message: {
                Text("This can't be undone.")
            }
        }
    }
}
