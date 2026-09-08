import Foundation
import Network

/// One process-wide view of whether the current network path is cellular, backed by a
/// single long-lived `NWPathMonitor`. `FreshnessChecker` reads this to honour
/// `AppSettings.checkLinksOnWiFiOnly`.
final class NetworkStatus: @unchecked Sendable {

    static let shared = NetworkStatus()

    private let monitor = NWPathMonitor()
    private let queue = DispatchQueue(label: "com.avaresearch.rolecall.netpath")
    private let lock = NSLock()
    private var cellular = false

    private init() {
        monitor.pathUpdateHandler = { [weak self] path in
            guard let self else { return }
            let onCell = path.status == .satisfied && path.usesInterfaceType(.cellular)
            self.lock.lock()
            self.cellular = onCell
            self.lock.unlock()
        }
        monitor.start(queue: queue)
    }

    /// `true` when the active path runs over cellular. `async` only to match the
    /// injectable closure shape in `FreshnessChecker`.
    func onCellular() async -> Bool {
        lock.lock()
        defer { lock.unlock() }
        return cellular
    }
}
