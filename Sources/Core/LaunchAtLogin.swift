import ServiceManagement
import OSLog

/// Whether macOS starts Blurt when you log in.
///
/// `SMAppService` rather than a login-item plist or a helper app: the app
/// registers itself, the user can revoke it from System Settings → General →
/// Login Items, and both sides stay in step. The older approaches leave an
/// entry behind that nothing owns.
enum LaunchAtLogin {
    private static let log = Logger(subsystem: "com.blurt.app", category: "launch")

    /// Read from the system, never from a stored preference.
    ///
    /// The user can turn this off in System Settings without telling the app, so
    /// a remembered answer would be a lie as soon as they did.
    static var isEnabled: Bool {
        SMAppService.mainApp.status == .enabled
    }

    /// True when macOS has the registration but the user has refused it.
    static var isDeniedByUser: Bool {
        SMAppService.mainApp.status == .requiresApproval
    }

    static func set(_ enabled: Bool) {
        do {
            if enabled {
                try SMAppService.mainApp.register()
            } else {
                try SMAppService.mainApp.unregister()
            }
        } catch {
            log.error("Could not \(enabled ? "enable" : "disable") launch at login: \(error.localizedDescription)")
        }
    }
}
