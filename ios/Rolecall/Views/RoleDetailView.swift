import SwiftUI

struct RoleDetailView: View {

    let role: Role
    @EnvironmentObject private var tracked: TrackedRoles
    @EnvironmentObject private var settings: AppSettings
    @Environment(\.openURL) private var openURL
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var freshness: FreshnessChecker.Status? = nil
    @State private var checking = false
    @State private var now = Date()

    private var status: RoleStatus? { tracked.status(for: role) }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                titleBlock
                freshnessBlock
                factsBlock
                sourceNote
                Spacer(minLength: 8)
            }
            .padding(Theme.Metric.gutter)
        }
        .rolecallBackground()
        .safeAreaInset(edge: .bottom) { applyBar }
        .navigationTitle(role.company)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar { detailToolbar }
        .task { await runCheck() }
        .onReceive(Timer.publish(every: 300, on: .main, in: .common).autoconnect()) { now = $0 }
    }

    @ToolbarContentBuilder
    private var detailToolbar: some ToolbarContent {
        ToolbarItem(placement: .topBarTrailing) {
            ShareLink(item: role.url,
                      subject: Text("\(role.title) — \(role.company)"),
                      message: Text("\(role.title) at \(role.company)")) {
                Image(systemName: "square.and.arrow.up")
            }
            .accessibilityLabel("Share role")
        }
        ToolbarItem(placement: .topBarTrailing) {
            Button {
                Haptics.selection()
                tracked.toggleSaved(role)
            } label: {
                Image(systemName: status?.isSaved == true ? "heart.fill" : "heart")
                    .foregroundStyle(status?.isSaved == true ? Theme.Palette.accent : Theme.Palette.ink)
            }
            .accessibilityLabel(status?.isSaved == true ? "Saved. Tap to remove." : "Save role")
        }
    }

    // MARK: blocks

    private var titleBlock: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(role.family.label)
                .font(.caption.weight(.semibold))
                .foregroundStyle(Theme.Palette.inkTertiary)
                .textCase(.uppercase)
                .tracking(0.8)
            Text(role.title)
                .font(.rolecallDisplay(.title))
                .foregroundStyle(Theme.Palette.ink)
                .fixedSize(horizontal: false, vertical: true)
            Text(role.company)
                .font(.title3)
                .foregroundStyle(Theme.Palette.inkSecondary)
        }
        .accessibilityElement(children: .combine)
    }

    private var freshnessBlock: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: statusIcon)
                .foregroundStyle(statusColor)
                .font(.body.weight(.semibold))
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 3) {
                Text(statusHeadline)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(Theme.Palette.ink)
                Text(statusDetail)
                    .font(.footnote)
                    .foregroundStyle(Theme.Palette.inkSecondary)
                    .fixedSize(horizontal: false, vertical: true)
                if freshness == .skippedOnCellular {
                    Button("Check now") { Task { await runCheck(force: true) } }
                        .font(.footnote.weight(.semibold))
                        .buttonStyle(.borderless)
                        .padding(.top, 4)
                }
            }
            Spacer(minLength: 0)
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.Palette.surface)
        .clipShape(RoundedRectangle(cornerRadius: Theme.Metric.cardRadius, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: Theme.Metric.cardRadius, style: .continuous)
                .stroke(Theme.Palette.hairline, lineWidth: 1)
        )
        .contentShape(Rectangle())
        .onTapGesture {
            switch freshness {
            case .mayHaveClosed: open()
            case .couldNotCheck: Task { await runCheck() }
            case .skippedOnCellular: Task { await runCheck(force: true) }
            default: break
            }
        }
        .animation(reduceMotion ? nil : .easeInOut(duration: 0.25), value: freshness)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(statusHeadline). \(statusDetail)")
        .accessibilityHint(freshness == .couldNotCheck || freshness == .skippedOnCellular
                           ? "Double tap to check now." : "")
    }

    private var factsBlock: some View {
        VStack(spacing: 0) {
            factRow("Location", role.locationLine)
            Divider().overlay(Theme.Palette.hairline)
            factRow("Arrangement", role.isRemote ? "Remote" : "On-site / hybrid")
            Divider().overlay(Theme.Palette.hairline)
            factRow("First listed", role.firstSeen.formatted(date: .abbreviated, time: .omitted))
            if let verified = role.lastVerified {
                Divider().overlay(Theme.Palette.hairline)
                factRow("Last checked", verified.formatted(date: .abbreviated, time: .shortened))
            }
        }
        .background(Theme.Palette.surface)
        .clipShape(RoundedRectangle(cornerRadius: Theme.Metric.cardRadius, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: Theme.Metric.cardRadius, style: .continuous)
                .stroke(Theme.Palette.hairline, lineWidth: 1)
        )
    }

    /// A quiet reminder of where this listing comes from and why it can be trusted —
    /// the same promise the board makes, restated on the page you act from.
    private var sourceNote: some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: "building.2")
                .font(.caption2)
                .foregroundStyle(Theme.Palette.inkTertiary)
                .accessibilityHidden(true)
            Text("Straight from \(role.company)'s own careers feed. When \(role.company) closes this role, it leaves Rolecall — usually within a few hours.")
                .font(.footnote)
                .foregroundStyle(Theme.Palette.inkSecondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.horizontal, 4)
        .accessibilityElement(children: .combine)
    }

    private func factRow(_ label: String, _ value: String) -> some View {
        HStack(alignment: .firstTextBaseline) {
            Text(label)
                .font(.subheadline)
                .foregroundStyle(Theme.Palette.inkSecondary)
            Spacer(minLength: 12)
            Text(value)
                .font(.subheadline)
                .foregroundStyle(Theme.Palette.ink)
                .multilineTextAlignment(.trailing)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 13)
        .accessibilityElement(children: .combine)
    }

    private var applyBar: some View {
        VStack(spacing: 0) {
            Divider().overlay(Theme.Palette.hairline)
            VStack(spacing: 10) {
                Button(action: open) {
                    HStack(spacing: 8) {
                        Text("Apply on \(applyHost)")
                            .font(.headline)
                        Image(systemName: "arrow.up.forward")
                            .font(.subheadline.weight(.semibold))
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 16)
                }
                .background(Theme.Palette.accent)
                .foregroundStyle(.white)
                .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                .accessibilityHint("Opens \(role.company)'s own application page in the browser.")

                appliedControl
            }
            .padding(Theme.Metric.gutter)
        }
        .background(Theme.Palette.paper)
        .animation(reduceMotion ? nil : .easeInOut(duration: 0.2), value: status)
    }

    @ViewBuilder
    private var appliedControl: some View {
        if let app = status?.application {
            Menu {
                Picker("Stage", selection: stageBinding) {
                    ForEach(ApplicationStage.allCases) { Text($0.label).tag($0) }
                }
                Button(role: .destructive) { tracked.unmarkApplied(role) } label: {
                    Label("Unmark as applied", systemImage: "arrow.uturn.backward")
                }
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: "checkmark.circle.fill").foregroundStyle(Theme.Palette.verified)
                    Text("\(app.stage.label) · applied \(Freshness.compactAgo(since: app.appliedOn, relativeTo: now))")
                        .foregroundStyle(Theme.Palette.inkSecondary)
                    Image(systemName: "chevron.up.chevron.down").font(.caption2).foregroundStyle(Theme.Palette.inkTertiary)
                }
                .font(.footnote.weight(.medium))
            }
            .accessibilityLabel("Application stage: \(app.stage.label). Tap to update.")
        } else {
            Button {
                Haptics.selection()
                tracked.markApplied(role)
            } label: {
                Text("I applied — track this")
                    .font(.footnote.weight(.medium))
                    .foregroundStyle(Theme.Palette.accent)
            }
        }
    }

    private var stageBinding: Binding<ApplicationStage> {
        Binding(
            get: { status?.application?.stage ?? .applied },
            set: { newStage in
                Haptics.selection()
                tracked.updateApplication(for: role) { $0.stage = newStage }
            }
        )
    }

    // MARK: actions

    private func open() { openURL(role.url) }

    private func runCheck(force: Bool = false) async {
        #if DEBUG
        if let forced = UITestSupport.forcedFreshness {
            now = Date(); freshness = forced; return
        }
        #endif
        checking = true
        let result = await FreshnessChecker().check(
            role.url,
            wifiOnly: settings.checkLinksOnWiFiOnly,
            forceNow: force)
        checking = false
        now = Date()
        freshness = result
        if result == .mayHaveClosed { Haptics.warning() }
    }

    // MARK: status presentation

    private var applyHost: String {
        // Prefer the employer's own domain when the ATS URL exposes it; otherwise a
        // neutral label. Never invent a domain.
        let host = role.url.host ?? ""
        let known = ["greenhouse.io", "ashbyhq.com", "lever.co", "workable.com",
                     "myworkdayjobs.com", "jobs.lever.co", "boards.greenhouse.io"]
        if known.contains(where: host.hasSuffix) {
            return role.company
        }
        let clean = host.replacingOccurrences(of: "www.", with: "")
        return clean.contains(".") ? clean : "the company site"
    }

    private var statusIcon: String {
        switch freshness {
        case .liveJustChecked: return "checkmark.seal.fill"
        case .mayHaveClosed: return "exclamationmark.triangle.fill"
        case .skippedOnCellular: return "antenna.radiowaves.left.and.right.slash"
        case .couldNotCheck, .none: return "arrow.triangle.2.circlepath"
        }
    }

    private var statusColor: Color {
        switch freshness {
        case .liveJustChecked: return Theme.Palette.verified
        case .mayHaveClosed: return Theme.Palette.caution
        case .skippedOnCellular, .couldNotCheck, .none: return Theme.Palette.inkTertiary
        }
    }

    private var statusHeadline: String {
        switch freshness {
        case .liveJustChecked: return "Verified live just now"
        case .mayHaveClosed: return "This posting may have closed"
        case .couldNotCheck: return "Couldn't reach the posting"
        case .skippedOnCellular: return "Not checked — you're on cellular"
        case .none: return checking ? "Checking the company site…" : "Checking…"
        }
    }

    private var statusDetail: String {
        switch freshness {
        case .liveJustChecked:
            return "Rolecall just opened \(role.company)'s page and the role is still there — "
                + "no dead link, no ghost posting."
        case .mayHaveClosed:
            return "The page 404'd or bounced to a careers index. Tap to check on the company site."
        case .couldNotCheck:
            return "You may be offline. Rolecall last confirmed this role "
                + Freshness.compactAgo(since: role.freshnessDate, relativeTo: now)
                + ". Tap to check again."
        case .skippedOnCellular:
            return "Rolecall didn't fetch \(role.company)'s page to save your cellular data. "
                + "Rolecall last confirmed this role "
                + Freshness.compactAgo(since: role.freshnessDate, relativeTo: now)
                + ". Check now, or allow cellular checks in Settings › Privacy."
        case .none:
            return "Opening \(role.company)'s page to confirm the role is still accepting applications."
        }
    }
}
