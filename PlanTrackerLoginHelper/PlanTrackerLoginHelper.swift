import AppKit

final class LoginItemHelperDelegate: NSObject, NSApplicationDelegate {
    private var monitorTimer: Timer?

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        LoginItemSharedState.beginHelperSession()
        startMonitoring()
        evaluateRelaunchNeed()
    }

    func applicationWillTerminate(_ notification: Notification) {
        monitorTimer?.invalidate()
    }

    private func startMonitoring() {
        monitorTimer = Timer.scheduledTimer(withTimeInterval: 5, repeats: true) { [weak self] _ in
            self?.evaluateRelaunchNeed()
        }
        if let monitorTimer {
            RunLoop.main.add(monitorTimer, forMode: .common)
        }
    }

    private func evaluateRelaunchNeed() {
        guard LoginItemSharedState.isHelperEnabled() else {
            NSApp.terminate(nil)
            return
        }

        guard !isMainAppRunning else { return }
        guard LoginItemSharedState.shouldRelaunchMainApp() else { return }
        relaunchMainApp()
    }

    private var isMainAppRunning: Bool {
        !NSRunningApplication.runningApplications(withBundleIdentifier: LoginItemConfiguration.mainAppBundleIdentifier).isEmpty
    }

    private func relaunchMainApp() {
        guard let mainAppURL = Bundle.main.bundleURL.mainAppBundleURL else { return }
        LoginItemSharedState.recordRelaunchAttempt()

        let configuration = NSWorkspace.OpenConfiguration()
        configuration.activates = false
        configuration.createsNewApplicationInstance = false
        NSWorkspace.shared.openApplication(at: mainAppURL, configuration: configuration) { _, _ in }
    }
}

private extension URL {
    var mainAppBundleURL: URL? {
        deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
    }
}

@main
struct PlanTrackerLoginHelperMain {
    static func main() {
        let app = NSApplication.shared
        let delegate = LoginItemHelperDelegate()
        app.delegate = delegate
        app.run()
    }
}
