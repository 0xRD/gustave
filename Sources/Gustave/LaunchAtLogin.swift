import Combine
import ServiceManagement

/// Starting Gustave at login, through `SMAppService.mainApp`: the system's own login item
/// for this app, with no helper and no entitlement. The state belongs to the system, so it is
/// read from there, never stored in Gustave's settings.
@MainActor
final class LaunchAtLogin: ObservableObject {
    @Published private(set) var isEnabled = false
    /// The user has to allow it in System Settings, Login Items.
    @Published private(set) var needsApproval = false
    @Published private(set) var failed = false

    init() {
        refresh()
    }

    /// Read again whenever the settings window shows: the user can change it in System
    /// Settings at any time.
    func refresh() {
        let status = SMAppService.mainApp.status
        isEnabled = status == .enabled
        needsApproval = status == .requiresApproval
    }

    func set(_ enabled: Bool) {
        do {
            if enabled {
                try SMAppService.mainApp.register()
            } else {
                try SMAppService.mainApp.unregister()
            }
            failed = false
        } catch {
            failed = true
        }
        refresh()
    }

    func openLoginItems() {
        SMAppService.openSystemSettingsLoginItems()
    }
}
