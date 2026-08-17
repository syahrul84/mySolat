import Foundation
import ServiceManagement

/// Start-at-login toggle backed by `SMAppService` (macOS 13+).
///
/// `SMAppService.mainApp` requires no helper target and no privileged install — the
/// registration is stored per-user by launchd and survives app updates.
enum LaunchAtLogin {
    static var isEnabled: Bool {
        SMAppService.mainApp.status == .enabled
    }

    /// Registers or unregisters the app. Returns the resulting state, which may
    /// differ from `enabled` if the user has denied the login item in System
    /// Settings (status `.requiresApproval`).
    @discardableResult
    static func set(_ enabled: Bool) -> Bool {
        do {
            if enabled {
                if SMAppService.mainApp.status != .enabled {
                    try SMAppService.mainApp.register()
                }
            } else {
                if SMAppService.mainApp.status == .enabled {
                    try SMAppService.mainApp.unregister()
                }
            }
        } catch {
            // Most commonly `.requiresApproval` — the toggle simply won't stick
            // until the user approves it under Login Items.
            return isEnabled
        }
        return isEnabled
    }

    /// True when macOS is waiting for the user to approve the login item.
    static var requiresApproval: Bool {
        SMAppService.mainApp.status == .requiresApproval
    }
}
