import SwiftUI
import StoreKit

struct SettingsView: View {
    @EnvironmentObject private var settings: AppSettings
    @EnvironmentObject private var tracked: TrackedRoles
    @EnvironmentObject private var store: BoardStore
    @EnvironmentObject private var plus: Store
    @EnvironmentObject private var searches: SavedSearches
    @Environment(\.isPlus) private var isPlus
    @Environment(\.dismiss) private var dismiss
    @State private var confirmingWipe = false
    @State private var iconOption: AppIconOption = .current
    @State private var showPaywall = false

    @State private var notificationsDenied = false

    private func handleDigestToggle(_ turnedOn: Bool) {
        Task {
            if turnedOn, await Digest.ensureAuthorised() == false {
                // permission refused — revert the switches and tell them why
                settings.morningRead = false
                settings.weeklyRecap = false
                notificationsDenied = true
            }
            await Digest.reschedule(board: store.board, tracked: tracked, settings: settings)
        }
    }

    /// A list row that opens a web page — with the trailing glyph iOS uses to say
    /// "this leaves the app".
    private func externalLink(_ title: String, _ urlString: String) -> some View {
        Link(destination: URL(string: urlString)!) {
            HStack {
                Text(title)
                Spacer()
                Image(systemName: "arrow.up.right")
                    .font(.footnote)
                    .foregroundStyle(.tertiary)
            }
        }
        .accessibilityLabel("\(title). Opens in the browser.")
    }

    private var version: String {
        let v = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0"
        let b = Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "1"
        return "\(v) (\(b))"
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    if isPlus {
                        HStack {
                            Label("Rolecall Plus", systemImage: "sparkles")
                            Spacer()
                            Text("Active").foregroundStyle(.secondary)
                        }
                        Button("Manage subscription") {
                            guard let scene = UIApplication.shared.connectedScenes
                                .compactMap({ $0 as? UIWindowScene })
                                .first(where: { $0.activationState == .foregroundActive })
                                ?? UIApplication.shared.connectedScenes
                                    .compactMap({ $0 as? UIWindowScene }).first
                            else { return }
                            Task { try? await AppStore.showManageSubscriptions(in: scene) }
                        }
                    } else {
                        Button {
                            showPaywall = true
                        } label: {
                            HStack(spacing: 10) {
                                Image(systemName: "sparkles").foregroundStyle(Theme.Palette.accent)
                                VStack(alignment: .leading, spacing: 2) {
                                    Text("Rolecall Plus").foregroundStyle(Theme.Palette.ink)
                                    Text("Alerts, reminders, advanced filters, notes")
                                        .font(.footnote).foregroundStyle(.secondary)
                                }
                                Spacer()
                                Image(systemName: "chevron.forward")
                                    .font(.footnote.weight(.semibold)).foregroundStyle(.tertiary)
                            }
                        }
                    }
                }

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

                Section {
                    Toggle("Morning read", isOn: $settings.morningRead)
                    Toggle("Weekly recap", isOn: $settings.weeklyRecap)
                } header: {
                    Text("Digests")
                } footer: {
                    Text("A quiet local notification — the count of new roles, computed on your device. Nothing fires when there's nothing new.")
                }
                .onChange(of: settings.morningRead) { _, on in handleDigestToggle(on) }
                .onChange(of: settings.weeklyRecap) { _, on in handleDigestToggle(on) }

                Section("Job search") {
                    NavigationLink {
                        SavedSearchesView()
                    } label: {
                        LabeledContent("Saved searches", value: "\(searches.searches.count)")
                    }
                    NavigationLink {
                        AppliedReportView()
                    } label: {
                        LabeledContent("Applications", value: "\(tracked.appliedCount)")
                    }
                    Toggle(isOn: $settings.autoClearOldRoles) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Tidy up automatically")
                            Text("Remove applications with no activity for 90 days")
                                .font(.footnote).foregroundStyle(.secondary)
                        }
                    }
                }

                Section {
                    Text("Rolecall keeps everything on this device. No account, no analytics, no trackers. Nothing you do here is sent anywhere.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                    Toggle(isOn: $settings.checkLinksOnWiFiOnly) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Check links on Wi-Fi only")
                            Text("Opening a role fetches the posting to confirm it's still open. On cellular Rolecall skips that unless you tap “Check now”.")
                                .font(.footnote).foregroundStyle(.secondary)
                        }
                    }
                    externalLink("Privacy Policy", "https://rolecalljobs.com/privacy/")
                    externalLink("Terms of Use", "https://rolecalljobs.com/terms/")
                } header: {
                    Text("Privacy")
                }

                Section {
                    Button(role: .destructive) { confirmingWipe = true } label: {
                        Text("Clear all data")
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
            .sheet(isPresented: $showPaywall) { PaywallView() }
            .alert("Notifications are off", isPresented: $notificationsDenied) {
                Button("Open Settings") {
                    if let url = URL(string: UIApplication.openSettingsURLString) {
                        UIApplication.shared.open(url)
                    }
                }
                Button("Not now", role: .cancel) { }
            } message: {
                Text("Turn on notifications for Rolecall in the Settings app to get digests.")
            }
            .alert("Clear all data?", isPresented: $confirmingWipe) {
                Button("Clear everything", role: .destructive) {
                    tracked.wipeAll()
                    searches.wipeAll()
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
