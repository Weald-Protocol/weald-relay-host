import Foundation
import ServiceManagement

/// Start at login, through the framework rather than a login-items plist.
///
/// It only works from a signed bundle, so a failure here is not worth an alert:
/// the toggle is a convenience and the app is one click away regardless.
enum LoginItem {
    static func set(_ on: Bool) {
        do {
            if on {
                if SMAppService.mainApp.status != .enabled {
                    try SMAppService.mainApp.register()
                }
            } else {
                if SMAppService.mainApp.status == .enabled {
                    try SMAppService.mainApp.unregister()
                }
            }
        } catch {
            NSLog("WealdRelayHost: login item change failed: \(error.localizedDescription)")
        }
    }
}
