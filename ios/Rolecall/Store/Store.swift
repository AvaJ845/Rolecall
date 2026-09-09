import Foundation
import StoreKit

/// Everything the app knows about "Rolecall Plus" — a single optional subscription that
/// unlocks the active-search convenience layer. The verified board, searching it, saving
/// a role, and marking it applied are free forever; nothing here ever gates them. Plus
/// only ever adds an alert, a reminder, a filter, a note — never removes the free path.
///
/// Entitlement lives only in StoreKit and on this device. There is no account, no server
/// check, and nothing synced anywhere. `isPlus` is derived from
/// `Transaction.currentEntitlements` and kept live by a `Transaction.updates` listener.
@MainActor
final class Store: ObservableObject {

    /// The two product identifiers, one subscription group ("Rolecall Plus").
    enum ProductID {
        static let monthly = "rolecall.plus.monthly"
        static let yearly  = "rolecall.plus.yearly"
        static let all: Set<String> = [monthly, yearly]
    }

    enum PurchaseOutcome {
        /// The subscription is now active.
        case success
        /// Ask-to-Buy / SCA — Apple will finish the purchase later; entitlement will
        /// arrive through the updates listener.
        case pending
        /// The customer dismissed the system sheet. Not an error.
        case cancelled
    }

    /// True iff a verified, unexpired Plus transaction is in `currentEntitlements`.
    /// Every Plus feature reads this (via `\.isPlus`); it is never written optimistically.
    @Published private(set) var isPlus: Bool = false

    /// Loaded product metadata, newest fetch wins. Empty until `products()` succeeds.
    @Published private(set) var plusProducts: [Product] = []

    /// Set while the App Store is being contacted so the paywall can show a spinner
    /// instead of an empty state.
    @Published private(set) var isLoadingProducts = false

    private var updatesTask: Task<Void, Never>?

    init() {
        #if DEBUG
        if ProcessInfo.processInfo.arguments.contains("-uitest-plus") {
            // Screenshot / UI-test builds only: pretend Plus is active so the gated
            // screens can be captured without touching StoreKit. Never compiled into a
            // shipping build.
            isPlus = true
            return
        }
        #endif

        // Start listening before the first entitlement read so a transaction that lands
        // mid-launch is never missed.
        updatesTask = Task { [weak self] in
            for await update in Transaction.updates {
                await self?.handle(verificationResult: update)
            }
        }
        Task { await refreshEntitlements() }
    }

    deinit {
        updatesTask?.cancel()
    }

    // MARK: Products

    /// Fetch the localized `Product` values for the paywall. Returns `[]` on any failure
    /// (offline, App Store unreachable) — the caller shows a retry, never a crash.
    func products() async -> [Product] {
        isLoadingProducts = true
        defer { isLoadingProducts = false }
        do {
            let fetched = try await Product.products(for: ProductID.all)
            // Monthly first, then yearly — matches the paywall's toggle order.
            let ordered = fetched.sorted { $0.price < $1.price }
            plusProducts = ordered
            return ordered
        } catch {
            return plusProducts   // keep whatever we had; may be empty
        }
    }

    // MARK: Purchase

    /// Buy a subscription. Returns `true` only when Plus is actually active on return.
    /// `.pending` returns `false` (entitlement, if granted, arrives via the listener).
    @discardableResult
    func purchase(_ product: Product) async throws -> Bool {
        let result = try await product.purchase()
        switch result {
        case let .success(verification):
            let transaction = try checkVerified(verification)
            await transaction.finish()
            await refreshEntitlements()
            return isPlus
        case .pending:
            return false
        case .userCancelled:
            return false
        @unknown default:
            return false
        }
    }

    /// Same as `purchase(_:)` but reports the three outcomes the paywall distinguishes
    /// in copy (success dismisses, pending shows a "we'll finish this" note).
    func buy(_ product: Product) async throws -> PurchaseOutcome {
        let result = try await product.purchase()
        switch result {
        case let .success(verification):
            let transaction = try checkVerified(verification)
            await transaction.finish()
            await refreshEntitlements()
            return .success
        case .pending:
            return .pending
        case .userCancelled:
            return .cancelled
        @unknown default:
            return .cancelled
        }
    }

    // MARK: Restore

    /// Explicit "Restore purchases". `AppStore.sync()` re-pulls the receipt; the updates
    /// listener plus `refreshEntitlements()` then reconcile `isPlus`. Never throws to the
    /// caller — a failed sync just leaves entitlement where it was.
    func restore() async {
        do {
            try await AppStore.sync()
        } catch {
            // User cancelled the sign-in sheet, or the network failed. Nothing to grant.
        }
        await refreshEntitlements()
    }

    // MARK: Entitlement plumbing

    /// Recompute `isPlus` from the current, verified entitlements. This is the only place
    /// `isPlus` is set (outside the DEBUG override).
    func refreshEntitlements() async {
        #if DEBUG
        if ProcessInfo.processInfo.arguments.contains("-uitest-plus") { return }
        #endif

        var entitled = false
        for await result in Transaction.currentEntitlements {
            guard case let .verified(transaction) = result else { continue }
            guard ProductID.all.contains(transaction.productID) else { continue }
            if let revoked = transaction.revocationDate, revoked <= Date() { continue }
            if let expiry = transaction.expirationDate, expiry <= Date() { continue }
            entitled = true
        }
        if entitled != isPlus { isPlus = entitled }
        // Cache it for the background-refresh task, which must not init StoreKit.
        SharedContainer.lastKnownIsPlus = entitled
    }

    private func handle(verificationResult: VerificationResult<Transaction>) async {
        guard let transaction = try? checkVerified(verificationResult) else { return }
        await transaction.finish()
        await refreshEntitlements()
    }

    /// StoreKit 2 signs every transaction; an unverified result must never grant access.
    private func checkVerified<T>(_ result: VerificationResult<T>) throws -> T {
        switch result {
        case .unverified(_, let error):
            throw error
        case .verified(let safe):
            return safe
        }
    }
}
