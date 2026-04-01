import Foundation
import ServiceManagement

@MainActor
final class LaunchAtLoginManager: ObservableObject {
    static let shared = LaunchAtLoginManager()

    @Published private(set) var isEnabled = false
    @Published private(set) var statusMessage: String?

    private init() {
        refresh()
    }

    func refresh() {
        let service = SMAppService.mainApp

        switch service.status {
        case .enabled:
            isEnabled = true
            statusMessage = nil
        case .requiresApproval:
            isEnabled = false
            statusMessage = "Enable tape in System Settings > General > Login Items."
        case .notFound:
            isEnabled = false
            statusMessage = "Launch at login is unavailable for this build."
        case .notRegistered:
            isEnabled = false
            statusMessage = nil
        @unknown default:
            isEnabled = false
            statusMessage = "Unable to determine launch-at-login status."
        }
    }

    func setEnabled(_ enabled: Bool) {
        let service = SMAppService.mainApp

        do {
            if enabled {
                try service.register()
            } else {
                try service.unregister()
            }
            refresh()
        } catch {
            refresh()
            statusMessage = error.localizedDescription
        }
    }
}
