import SwiftUI

struct RoleDetailView: View {

    let role: Role
    @Environment(\.openURL) private var openURL
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var freshness: FreshnessChecker.Status? = nil
    @State private var checking = false
    @State private var now = Date()

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                titleBlock
                freshnessBlock
                factsBlock
                Spacer(minLength: 8)
            }
            .padding(Theme.Metric.gutter)
        }
        .rolecallBackground()
        .safeAreaInset(edge: .bottom) { applyBar }
        .navigationTitle(role.company)
        .navigationBarTitleDisplayMode(.inline)
        .task { await runCheck() }
        .onReceive(Timer.publish(every: 60, on: .main, in: .common).autoconnect()) { now = $0 }
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
            default: break
            }
        }
        .animation(reduceMotion ? nil : .easeInOut(duration: 0.25), value: freshness)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(statusHeadline). \(statusDetail)")
        .accessibilityHint(freshness == .couldNotCheck ? "Double tap to check again." : "")
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
                factRow("Engine last verified", verified.formatted(date: .abbreviated, time: .shortened))
            }
        }
        .background(Theme.Palette.surface)
        .clipShape(RoundedRectangle(cornerRadius: Theme.Metric.cardRadius, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: Theme.Metric.cardRadius, style: .continuous)
                .stroke(Theme.Palette.hairline, lineWidth: 1)
        )
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
            .padding(Theme.Metric.gutter)
            .accessibilityHint("Opens \(role.company)'s own application page in the browser.")
        }
        .background(Theme.Palette.paper)
    }

    // MARK: actions

    private func open() { openURL(role.url) }

    private func runCheck() async {
        checking = true
        let result = await FreshnessChecker().check(role.url)
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
        return host.replacingOccurrences(of: "www.", with: "")
    }

    private var statusIcon: String {
        switch freshness {
        case .liveJustChecked: return "checkmark.seal.fill"
        case .mayHaveClosed: return "exclamationmark.triangle.fill"
        case .couldNotCheck, .none: return "arrow.triangle.2.circlepath"
        }
    }

    private var statusColor: Color {
        switch freshness {
        case .liveJustChecked: return Theme.Palette.verified
        case .mayHaveClosed: return Theme.Palette.caution
        case .couldNotCheck, .none: return Theme.Palette.inkTertiary
        }
    }

    private var statusHeadline: String {
        switch freshness {
        case .liveJustChecked: return "Verified live just now"
        case .mayHaveClosed: return "This posting may have closed"
        case .couldNotCheck: return "Couldn't reach the posting"
        case .none: return checking ? "Checking the company site…" : "Checking…"
        }
    }

    private var statusDetail: String {
        switch freshness {
        case .liveJustChecked:
            return "Rolecall just opened \(role.company)'s page and the role is still there. "
                + Freshness.line(for: role.freshnessDate, verified: true, relativeTo: now)
        case .mayHaveClosed:
            return "The page 404'd or bounced to a careers index. Tap to check on the company site."
        case .couldNotCheck:
            return "You may be offline. The engine last saw this role "
                + Freshness.compactAgo(since: role.freshnessDate, relativeTo: now)
                + ". Tap to check again."
        case .none:
            return "Opening \(role.company)'s page to confirm the role is still accepting applications."
        }
    }
}
