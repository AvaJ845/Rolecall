import SwiftUI
import StoreKit

/// The one and only paywall. Calm, honest, dismissible. Never blocks the board — it is
/// only ever reached by tapping a *convenience* feature (alerts, reminders, sync, …).
struct PaywallView: View {
    var feature: PlusFeature? = nil

    @EnvironmentObject private var store: Store
    @Environment(\.dismiss) private var dismiss
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.openURL) private var openURL

    @State private var products: [Product] = []
    @State private var selected: Product? = nil
    @State private var working = false
    @State private var errorText: String?
    @State private var pendingNote = false

    private let benefits: [(String, String)] = [
        ("bell.badge", "Alerts when a saved search matches a new role"),
        ("bookmark", "Keep as many saved searches as you like"),
        ("line.3.horizontal.decrease", "Filter by seniority, team and pay band"),
        ("clock.arrow.circlepath", "Follow-up reminders on your applications"),
        ("square.and.pencil", "A private note on each application"),
    ]

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    header
                    benefitList
                    planPicker
                    disclosure
                }
                .padding(Theme.Metric.gutter)
                .padding(.bottom, 8)
                .rolecallReadingColumn()
            }
            .rolecallBackground()
            .safeAreaInset(edge: .bottom) { buyBar }
            .navigationTitle("Rolecall Plus")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Not now") { dismiss() }
                }
            }
            .task {
                products = await store.products()
                selected = products.first    // monthly, cheapest first
            }
            .onChange(of: store.isPlus) { _, now in if now { dismiss() } }
            .alert("Couldn't complete that", isPresented: .constant(errorText != nil)) {
                Button("OK") { errorText = nil }
            } message: {
                Text(errorText ?? "")
            }
        }
    }

    // MARK: sections

    private var header: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Run a serious search.")
                .font(.rolecallDisplay(.title))
                .foregroundStyle(Theme.Palette.ink)
                .fixedSize(horizontal: false, vertical: true)
            Text(feature?.blurb
                 ?? "Plus adds the tools for an active job hunt. The board, search, saving a role and applying stay free — always.")
                .font(.callout)
                .foregroundStyle(Theme.Palette.inkSecondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .accessibilityElement(children: .combine)
    }

    private var benefitList: some View {
        VStack(alignment: .leading, spacing: 14) {
            ForEach(benefits, id: \.1) { icon, text in
                HStack(alignment: .top, spacing: 12) {
                    Image(systemName: icon)
                        .font(.body)
                        .foregroundStyle(Theme.Palette.accent)
                        .frame(width: 26)
                        .accessibilityHidden(true)
                    Text(text)
                        .font(.subheadline)
                        .foregroundStyle(Theme.Palette.ink)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.Palette.surface)
        .clipShape(RoundedRectangle(cornerRadius: Theme.Metric.cardRadius, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: Theme.Metric.cardRadius, style: .continuous)
                .stroke(Theme.Palette.hairline, lineWidth: 1)
        )
    }

    @ViewBuilder
    private var planPicker: some View {
        #if DEBUG
        if PaywallDemo.isActive {
            VStack(spacing: 10) {
                ForEach(PaywallDemo.plans) { demoRow($0) }
            }
        } else {
            livePlanPicker
        }
        #else
        livePlanPicker
        #endif
    }

    @ViewBuilder
    private var livePlanPicker: some View {
        if products.isEmpty {
            HStack {
                if store.isLoadingProducts { ProgressView() }
                Text(store.isLoadingProducts ? "Loading plans…" : "Plans are unavailable right now.")
                    .font(.footnote)
                    .foregroundStyle(Theme.Palette.inkSecondary)
                Spacer()
                if !store.isLoadingProducts {
                    Button("Retry") { Task { products = await store.products(); selected = products.first } }
                        .font(.footnote.weight(.semibold))
                }
            }
            .padding(.vertical, 8)
        } else {
            VStack(spacing: 10) {
                ForEach(products, id: \.id) { product in
                    planRow(product)
                }
            }
        }
    }

    private func planRow(_ product: Product) -> some View {
        let isSel = selected?.id == product.id
        return Button {
            selected = product
            Haptics.selection()
        } label: {
            HStack(spacing: 12) {
                Image(systemName: isSel ? "largecircle.fill.circle" : "circle")
                    .foregroundStyle(isSel ? Theme.Palette.accent : Theme.Palette.inkTertiary)
                VStack(alignment: .leading, spacing: 2) {
                    Text(planTitle(product))
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(Theme.Palette.ink)
                    Text(planDetail(product))
                        .font(.footnote)
                        .foregroundStyle(Theme.Palette.inkSecondary)
                }
                Spacer()
                Text(product.displayPrice)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(Theme.Palette.ink)
                    .monospacedDigit()
            }
            .padding(14)
            .background(Theme.Palette.surface)
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .stroke(isSel ? Theme.Palette.accent : Theme.Palette.hairline,
                            lineWidth: isSel ? 2 : 1)
            )
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(isSel ? [.isSelected] : [])
    }

    private var disclosure: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(disclosureText)
                .font(.caption2)
                .foregroundStyle(Theme.Palette.inkTertiary)
                .fixedSize(horizontal: false, vertical: true)
            HStack(spacing: 16) {
                Button("Restore") { Task { await store.restore() } }
                Button("Terms") { openURL(URL(string: "https://rolecalljobs.com/terms/")!) }
                Button("Privacy") { openURL(URL(string: "https://rolecalljobs.com/privacy/")!) }
            }
            .font(.caption2.weight(.medium))
            .foregroundStyle(Theme.Palette.accent)
        }
    }

    private var buyBar: some View {
        VStack(spacing: 6) {
            Divider().overlay(Theme.Palette.hairline)
            Button(action: buy) {
                Group {
                    if working { ProgressView().tint(.white) }
                    else { Text(buyTitle) }
                }
                .font(.headline)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 16)
            }
            .background(Theme.Palette.accent)
            .foregroundStyle(.white)
            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
            .disabled(isBuyDisabled)
            .padding(.horizontal, Theme.Metric.gutter)
            .padding(.top, 8)

            if pendingNote {
                Text("Waiting for approval — Plus will unlock once it's confirmed.")
                    .font(.caption2)
                    .foregroundStyle(Theme.Palette.inkSecondary)
            }
        }
        .padding(.bottom, 6)
        .background(Theme.Palette.paper)
    }

    // MARK: actions / copy

    private var isBuyDisabled: Bool {
        #if DEBUG
        if PaywallDemo.isActive { return false }
        #endif
        return selected == nil || working
    }

    private func buy() {
        #if DEBUG
        if PaywallDemo.isActive { return }   // review screenshot only — no transaction
        #endif
        guard let product = selected else { return }
        working = true
        Task {
            defer { working = false }
            do {
                switch try await store.buy(product) {
                case .success:
                    Haptics.success()
                    dismiss()
                case .pending:
                    pendingNote = true
                case .cancelled:
                    break
                }
            } catch {
                errorText = "The App Store couldn't verify the purchase. No charge was made."
            }
        }
    }

    private var buyTitle: String {
        #if DEBUG
        if PaywallDemo.isActive { return "Start 7 days free" }
        #endif
        guard let p = selected else { return "Choose a plan" }
        return hasTrial(p) ? "Start 7 days free" : "Subscribe \(p.displayPrice)"
    }

    private func hasTrial(_ p: Product) -> Bool {
        p.subscription?.introductoryOffer?.paymentMode == .freeTrial
    }

    private func planTitle(_ p: Product) -> String {
        switch p.subscription?.subscriptionPeriod.unit {
        case .month: return "Monthly"
        case .year:  return "Yearly"
        default:     return p.displayName
        }
    }

    private func planDetail(_ p: Product) -> String {
        let trial = hasTrial(p) ? "7 days free, then " : ""
        switch p.subscription?.subscriptionPeriod.unit {
        case .month: return "\(trial)\(p.displayPrice) / month"
        case .year:
            let perMonth = (p.price / 12)
            let fmt = p.priceFormatStyle
            return "\(trial)\(p.displayPrice) / year  ·  \(perMonth.formatted(fmt))/mo"
        default: return "\(trial)\(p.displayPrice)"
        }
    }

    private var disclosureText: String {
        "Payment is charged to your Apple Account. A free trial, where offered, converts to "
        + "a paid subscription unless cancelled at least 24 hours before it ends. The "
        + "subscription renews automatically at the price shown until cancelled in Settings › "
        + "Apple Account › Subscriptions. Rolecall keeps no account and no server record of "
        + "your subscription."
    }

    #if DEBUG
    private func demoRow(_ plan: PaywallDemo.Plan) -> some View {
        HStack(spacing: 12) {
            Image(systemName: plan.selected ? "largecircle.fill.circle" : "circle")
                .foregroundStyle(plan.selected ? Theme.Palette.accent : Theme.Palette.inkTertiary)
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(plan.title)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(Theme.Palette.ink)
                    if let tag = plan.tag {
                        Text(tag)
                            .font(.caption2.weight(.semibold))
                            .padding(.horizontal, 6).padding(.vertical, 2)
                            .background(Theme.Palette.accent.opacity(0.14))
                            .foregroundStyle(Theme.Palette.accent)
                            .clipShape(Capsule())
                    }
                }
                Text(plan.detail)
                    .font(.footnote)
                    .foregroundStyle(Theme.Palette.inkSecondary)
            }
            Spacer()
            Text(plan.price)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(Theme.Palette.ink)
                .monospacedDigit()
        }
        .padding(14)
        .background(Theme.Palette.surface)
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(plan.selected ? Theme.Palette.accent : Theme.Palette.hairline,
                        lineWidth: plan.selected ? 2 : 1)
        )
    }
    #endif
}

#if DEBUG
/// A fixed, offline stand-in for the two Rolecall Plus products, used only to capture the
/// App Store Connect subscription review screenshot (`-uitest-paywall`). Never reachable
/// in a shipping build — the whole type is `#if DEBUG`. The strings mirror
/// `RolecallProducts.storekit` so the screenshot is accurate.
enum PaywallDemo {
    static var isActive: Bool {
        ProcessInfo.processInfo.arguments.contains("-uitest-paywall")
    }

    struct Plan: Identifiable {
        let id = UUID()
        let title: String
        let detail: String
        let price: String
        let tag: String?
        let selected: Bool
    }

    static let plans: [Plan] = [
        Plan(title: "Monthly",
             detail: "7 days free, then $4.99 / month",
             price: "$4.99", tag: nil, selected: true),
        Plan(title: "Yearly",
             detail: "7 days free, then $29.99 / year  ·  $2.50/mo",
             price: "$29.99", tag: "Best value", selected: false),
    ]
}
#endif
