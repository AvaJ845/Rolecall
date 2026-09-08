import SwiftUI

/// One posting in the list. Company and title carry the hierarchy; the freshness line is
/// the trust signal and is never truncated away.
struct RoleRow: View {
    let role: Role
    var now: Date = Date()
    var status: RoleStatus? = nil
    var isNew: Bool = false

    @ScaledMetric(relativeTo: .body) private var vPadding: CGFloat = 16

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                if isNew {
                    Text("NEW")
                        .font(.caption2.weight(.bold))
                        .foregroundStyle(Theme.Palette.accent)
                        .tracking(0.5)
                }
                Text(role.company)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(Theme.Palette.inkSecondary)
                Spacer(minLength: 8)
                statusAccessory
                Text(role.family.shortLabel)
                    .font(.caption2.weight(.medium))
                    .foregroundStyle(Theme.Palette.inkTertiary)
            }

            Text(role.title)
                .font(.rolecallTitle(.title3))
                .foregroundStyle(Theme.Palette.ink)
                .fixedSize(horizontal: false, vertical: true)

            Text(role.locationLine)
                .font(.subheadline)
                .foregroundStyle(Theme.Palette.inkSecondary)

            HStack(spacing: 6) {
                Circle()
                    .fill(Theme.Palette.verified)
                    .frame(width: 6, height: 6)
                Text(freshnessText)
                    .font(.footnote)
                    .foregroundStyle(Theme.Palette.inkSecondary)
            }
            .padding(.top, 2)
        }
        .padding(.vertical, vPadding)
        .padding(.horizontal, Theme.Metric.gutter)
        .frame(maxWidth: .infinity, alignment: .leading)
        .contentShape(Rectangle())
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityLabel)
        .accessibilityHint("Opens the role and checks it is still live.")
    }

    @ViewBuilder
    private var statusAccessory: some View {
        switch status {
        case .saved:
            Image(systemName: "heart.fill")
                .font(.caption2)
                .foregroundStyle(Theme.Palette.accent)
                .accessibilityHidden(true)
        case .applied:
            Text("APPLIED")
                .font(.caption2.weight(.bold))
                .foregroundStyle(Theme.Palette.verified)
                .tracking(0.5)
        default:
            EmptyView()
        }
    }

    private var freshnessText: String {
        if let app = status?.application {
            let stage = app.stage == .applied ? "applied" : app.stage.label.lowercased()
            return "\(stage) · \(Freshness.compactAgo(since: app.updatedOn, relativeTo: now))"
        }
        return Freshness.line(for: role.freshnessDate,
                              verified: role.lastVerified != nil,
                              relativeTo: now)
    }

    private var accessibilityLabel: String {
        var line = isNew ? "New. " : ""
        line += "\(role.title), \(role.company). \(role.locationLine). "
        switch status {
        case .saved: line += "Saved. "
        case let .applied(app):
            line += "\(app.stage.label), updated \(Freshness.compactAgo(since: app.updatedOn, relativeTo: now)). "
        default: break
        }
        line += Freshness.spokenLine(for: role.freshnessDate,
                                     verified: role.lastVerified != nil,
                                     relativeTo: now)
        return line
    }
}
