import SwiftUI

/// One posting in the list. Company and title carry the hierarchy; the freshness line is
/// the trust signal and is never truncated away.
struct RoleRow: View {
    let role: Role
    var now: Date = Date()

    @ScaledMetric(relativeTo: .body) private var vPadding: CGFloat = 16

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .firstTextBaseline) {
                Text(role.company)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(Theme.Palette.inkSecondary)
                Spacer(minLength: 8)
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
                Text(Freshness.line(for: role.freshnessDate,
                                    verified: role.lastVerified != nil,
                                    relativeTo: now))
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

    private var accessibilityLabel: String {
        var line = "\(role.title), \(role.company). \(role.locationLine). "
        line += Freshness.spokenLine(for: role.freshnessDate,
                                     verified: role.lastVerified != nil,
                                     relativeTo: now)
        return line
    }
}
