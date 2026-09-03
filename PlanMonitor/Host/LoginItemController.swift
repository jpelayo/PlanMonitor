import ServiceManagement

@MainActor
enum LoginItemController {
    /// One instance for the life of the process, as the donor app and Apple's samples do.
    /// Building a throwaway `SMAppService` around each call made the status read back
    /// inconsistently with the call that had just been made.
    private static let service = SMAppService.loginItem(
        identifier: LoginItemConfiguration.helperBundleIdentifier
    )

    enum State: Equatable {
        /// macOS will start the helper at login.
        case enabled
        /// Registered, but switched off in System Settings → Login Items.
        case requiresApproval
        case disabled

        var isEnabled: Bool { self == .enabled }
    }

    /// What ServiceManagement said the last time a change was requested, if it complained.
    private(set) static var lastErrorDescription: String?

    static var state: State {
        let status = service.status
        if status.isEnabledForUI { return .enabled }
        if status.requiresUserApproval { return .requiresApproval }
        return .disabled
    }

    static var isEnabled: Bool { state.isEnabled }

    /// Asks macOS to register or unregister the helper and returns the state it actually
    /// ended up in — the only source of truth for the toggle.
    ///
    /// This is deliberately not a two-way switch. Once the user turns the item off in
    /// System Settings, `register()` cannot turn it back on: Background Task Management
    /// records the item as registered-but-disallowed, `status` reports `.requiresApproval`,
    /// and only the user can re-allow it. So the app requests, reports, and offers a
    /// shortcut to the pane; it never claims a state macOS did not grant.
    @discardableResult
    static func setEnabled(_ enabled: Bool) async -> State {
        LoginItemSharedState.setHelperEnabled(enabled)
        lastErrorDescription = nil

        do {
            if enabled {
                // Always call register, never skip it when the status already reads
                // enabled: macOS posts its "added items that can run in the background"
                // notice in response to this call, and skipping it makes an enable look
                // like nothing happened at all.
                try service.register()
            } else {
                try await service.unregister()
            }
        } catch {
            lastErrorDescription = error.localizedDescription
        }

        // ServiceManagement does not update `status` synchronously with the call.
        try? await Task.sleep(for: .milliseconds(250))

        let achieved = state
        LoginItemSharedState.setHelperEnabled(achieved.isEnabled)
        return achieved
    }

    /// Re-reads the system state; the user can change it in System Settings at any time.
    static func syncActivityWithCurrentSetting() {
        LoginItemSharedState.setHelperEnabled(isEnabled)
    }

    /// System Settings → General → Login Items.
    static func openSystemSettings() {
        SMAppService.openSystemSettingsLoginItems()
    }
}
