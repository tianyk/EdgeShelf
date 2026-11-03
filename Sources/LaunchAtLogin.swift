import Foundation
import ServiceManagement

/// Launch-at-login is owned by the system, not by `UserDefaults`: every read
/// goes through `SMAppService` so the switch stays truthful when Login Items
/// are changed in System Settings. macOS 13 is the deployment target, so no
/// LaunchAgent fallback is needed.
enum LaunchAtLogin {
    enum ChangeResult {
        case success
        /// Registered, but macOS waits for the user to allow it in
        /// System Settings → General → Login Items.
        case requiresApproval
        case failure(String)
    }

    static var isEnabled: Bool {
        SMAppService.mainApp.status == .enabled
    }

    static func setEnabled(_ enabled: Bool) -> ChangeResult {
        let service = SMAppService.mainApp

        if !enabled {
            // A `requiresApproval` item is still registered, so it has to be
            // unregistered as well or it would stay in the Login Items list.
            guard service.status != .notRegistered else { return .success }
            do {
                try service.unregister()
                return .success
            } catch {
                return .failure(error.localizedDescription)
            }
        }

        switch service.status {
        case .enabled:
            return .success
        case .requiresApproval:
            return .requiresApproval
        default:
            break
        }

        do {
            try service.register()
        } catch {
            return .failure(error.localizedDescription)
        }

        switch service.status {
        case .enabled:
            return .success
        case .requiresApproval:
            return .requiresApproval
        default:
            return .failure(L10n.launchAtLoginInactive)
        }
    }

    static func openLoginItemsSettings() {
        SMAppService.openSystemSettingsLoginItems()
    }
}
