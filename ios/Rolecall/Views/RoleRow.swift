import SwiftUI

/// One posting in the list. A calm identity tile anchors it; the title carries the
/// hierarchy; the freshness line is the trust signal and is never truncated away.
struct RoleRow: View {
    let role: Role
    var now: Date = Date()
    var status: RoleStatus? = nil
    var isNew: Bool = false
    /// The board shows a "saved" / "applied" marker so you can spot roles you've already
    /// touched. In the Saved and Applied lists every row is that status, so the marker is
    /// redundant noise — those lists pass `false`.
    var showsStatusBadge: Bool = true

    @ScaledMetric(relativeTo: .body) private var vPadding: CGFloat = 15
    @ScaledMetric(relativeTo: .body) private var tile: CGFloat = 40

    var body: some View {
        HStack(alignment: .top, spacing: 13) {
            CompanyMonogram(company: role.company, size: tile)

            VStack(alignment: .leading, spacing: 5) {
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    if isNew {
                        Text("NEW")
                            .font(.caption2.weight(.bold))
                            .tracking(0.5)
                            .foregroundStyle(Theme.Palette.accent)
                            .padding(.horizontal, 5)
                            .padding(.vertical, 1.5)
                            .overlay(
                                Capsule(style: .continuous)
                                    .stroke(Theme.Palette.accent.opacity(0.35), lineWidth: 1)
                            )
                            .accessibilityHidden(true)
                    }
                    Text(role.company)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(Theme.Palette.inkSecondary)
                        .lineLimit(1)
                    Spacer(minLength: 6)
                    if showsStatusBadge { statusAccessory }
                    Text(role.family.shortLabel)
                        .font(.caption2.weight(.medium))
                        .foregroundStyle(Theme.Palette.inkTertiary)
                        .fixedSize()
                }

                Text(role.title)
                    .font(.rolecallTitle(.title3))
                    .foregroundStyle(Theme.Palette.ink)
                    .fixedSize(horizontal: false, vertical: true)

                Text(role.locationLine)
                    .font(.subheadline)
                    .foregroundStyle(Theme.Palette.inkSecondary)

                HStack(spacing: 5) {
                    Image(systemName: freshnessIcon)
                        .font(.caption2)
                        .foregroundStyle(freshnessTint)
                    Text(freshnessText)
                        .font(.footnote)
                        .foregroundStyle(Theme.Palette.inkSecondary)
                }
                .padding(.top, 1)
            }
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

    private var freshnessIcon: String {
        status?.isApplied == true ? "arrow.right.circle" : "checkmark.seal.fill"
    }

    private var freshnessTint: Color {
        status?.isApplied == true ? Theme.Palette.inkTertiary : Theme.Palette.verified
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
