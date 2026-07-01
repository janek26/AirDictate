import ServiceManagement
import Foundation

final class LoginItemManager: ObservableObject {
    @Published private(set) var isEnabled: Bool = false
    @Published private(set) var status: SMAppService.Status = .notRegistered
    @Published var lastError: String?

    private let log: DebugLog

    init(log: DebugLog) {
        self.log = log
        refresh()
    }

    func refresh() {
        status = SMAppService.mainApp.status
        isEnabled = status == .enabled
        if status == .notFound {
            log.error("SMAppService not available — login item requires app bundle (not SPM)")
        }
    }

    func setEnabled(_ enabled: Bool) {
        do {
            if enabled {
                try SMAppService.mainApp.register()
                log.info("Login item registered")
            } else {
                try SMAppService.mainApp.unregister()
                log.info("Login item unregistered")
            }
            lastError = nil
        } catch {
            lastError = error.localizedDescription
            log.error("Login item failed: \(error.localizedDescription)")
        }
        refresh()
    }

    var statusDescription: String {
        switch status {
        case .enabled:          return "Enabled — launches at login"
        case .notRegistered:    return "Not registered"
        case .requiresApproval: return "Requires approval in Login Items settings"
        case .notFound:         return "SMAppService not available (needs .app bundle)"
        @unknown default:       return "Unknown"
        }
    }
}
