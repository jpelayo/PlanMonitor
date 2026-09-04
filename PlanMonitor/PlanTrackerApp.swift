//
//  PlanTrackerApp.swift
//  PlanTracker
//
//  Copyright © 2025 Intelligent Computing OU. All rights reserved.
//

import AppKit
import os
import SwiftUI

/// The SwiftUI app owns only the Settings scene. The four menu-bar items are AppKit
/// `NSStatusItem`s (see `StatusItemController`) so their digits are real, adaptive text; the
/// sign-in and connect windows are `NSWindow`s hosted through `WindowRouter`.
@main
struct PlanTrackerApp: App {
    @NSApplicationDelegateAdaptor(PlanTrackerAppDelegate.self) private var appDelegate
    @State private var viewModel: ClaudeUsageViewModel
    @State private var codexViewModel: CodexUsageViewModel
    @State private var grokViewModel: GrokUsageViewModel
    @State private var openRouterViewModel: OpenRouterBudgetViewModel
    @State private var enabledProviders: EnabledProviders
    @State private var preferences: GlobalPreferences

    init() {
        let launch = AppLaunchContext.current

        // A second instance must exit before it touches any shared state.
        if !launch.isTestHost {
            Self.terminateIfSecondaryInstance()
        }

        // One composition root. Under the test host or UI tests nothing here may reach the
        // user's Keychain, preferences, or login item.
        let secureStore: any SecureStore = launch.isIsolated ? InMemorySecureStore() : KeychainSecureStore()
        let defaults: UserDefaults = launch.isIsolated
            ? UserDefaults(suiteName: "com.infinitecontext.plantracker.isolated.\(ProcessInfo.processInfo.processIdentifier)") ?? .standard
            : .standard
        let groupDefaults: UserDefaults? = launch.isIsolated ? defaults : nil

        if !launch.isIsolated {
            let launchState = AppRuntimeState.beginLaunchIfNeeded()
            if launchState.wasUnexpectedTermination {
                AppRuntimeState.recordBreadcrumb("unexpected-termination-detected")
            }
            CacheJanitor.prepareForLaunch()
        }

        let globalPreferences = GlobalPreferences(defaults: defaults, readLoginItem: !launch.isIsolated)
        let claude = ClaudeUsageViewModel(secureStore: secureStore, defaults: defaults)
        let codex = CodexUsageViewModel(secureStore: secureStore, defaults: defaults)
        let grok = GrokUsageViewModel(secureStore: secureStore, defaults: defaults)
        let openRouter = OpenRouterBudgetViewModel(secureStore: secureStore, defaults: defaults)
        let enabled = EnabledProviders(defaults: groupDefaults)
        let coordinator = ProviderRuntimeCoordinator(
            claude: claude,
            codex: codex,
            grok: grok,
            openRouter: openRouter
        )
        let reviewer = ReviewerMode(
            providers: enabled,
            runtimes: [.claude: claude, .codex: codex, .grok: grok, .openrouter: openRouter]
        )

        globalPreferences.onChange = { change in
            switch change {
            case .pollingInterval(let minutes):
                claude.pollingIntervalMinutes = minutes
                codex.pollingIntervalMinutes = minutes
                grok.pollingIntervalMinutes = minutes
                openRouter.pollingIntervalMinutes = minutes
            case .percentageMode(let showRemaining):
                claude.showRemainingPercent = showRemaining
                codex.showRemainingPercent = showRemaining
                grok.showRemainingPercent = showRemaining
            case .language:
                break
            }
        }
        globalPreferences.publishCurrentValues()

        _viewModel = State(initialValue: claude)
        _codexViewModel = State(initialValue: codex)
        _grokViewModel = State(initialValue: grok)
        _openRouterViewModel = State(initialValue: openRouter)
        _enabledProviders = State(initialValue: enabled)
        _preferences = State(initialValue: globalPreferences)

        // Auxiliary windows, hosted by AppKit on demand.
        let router = WindowRouter.shared
        router.register(.loginClaude) {
            AnyView(ClaudeLoginView { sessionKey in
                Task { await claude.handleLoginSuccess(sessionKey: sessionKey) }
            })
        }
        router.register(.loginCodex) {
            AnyView(CodexLoginView { cookies in
                await codex.handleLoginSuccess(sessionCookies: cookies)
            })
        }
        router.register(.loginGrok) {
            AnyView(GrokLoginView(viewModel: grok))
        }
        router.register(.connectOpenRouter) {
            AnyView(OpenRouterConnectKeyView(viewModel: openRouter))
        }

        // Menu-bar items: one per enabled provider, label from the provider, dropdown is the
        // provider's SwiftUI view in a popover.
        let statusItems = StatusItemController(
            providers: [
                .init(
                    id: .claude,
                    label: {
                        ClaudeMenuBarLabel.make(
                            usageData: claude.usageData,
                            authState: claude.authState,
                            showRemainingPercent: globalPreferences.showRemainingPercent,
                            usageDisplay: claude.menuBarText.usageDisplay,
                            font: claude.menuBarText.font
                        )
                    },
                    content: {
                        AnyView(ClaudeMenuBarView(
                            viewModel: claude,
                            providers: enabled,
                            preferences: globalPreferences,
                            reviewerMode: reviewer
                        ))
                    }
                ),
                .init(
                    id: .codex,
                    label: {
                        CodexMenuBarLabel.make(
                            usageData: codex.usageData,
                            authState: codex.authState,
                            showRemainingPercent: globalPreferences.showRemainingPercent,
                            usageDisplay: codex.menuBarText.usageDisplay,
                            font: codex.menuBarText.font
                        )
                    },
                    content: {
                        AnyView(CodexMenuBarView(viewModel: codex, providers: enabled, preferences: globalPreferences))
                    }
                ),
                .init(
                    id: .grok,
                    label: {
                        GrokMenuBarLabel.make(
                            usageData: grok.usageData,
                            authState: grok.authState,
                            showRemainingPercent: globalPreferences.showRemainingPercent,
                            usageDisplay: grok.menuBarText.usageDisplay,
                            font: grok.menuBarText.font
                        )
                    },
                    content: {
                        AnyView(GrokMenuBarView(viewModel: grok, providers: enabled, preferences: globalPreferences))
                    }
                ),
                .init(
                    id: .openrouter,
                    label: {
                        OpenRouterMenuBarLabel.make(
                            snapshot: openRouter.snapshot,
                            connectionState: openRouter.connectionState,
                            display: openRouter.menuBarDisplay,
                            font: openRouter.menuBarText.font
                        )
                    },
                    content: {
                        AnyView(OpenRouterMenuBarView(viewModel: openRouter, providers: enabled, preferences: globalPreferences))
                    }
                )
            ],
            enabledProviders: enabled
        )

        // The delegate owns lifecycle: it shows the status items and starts the coordinator
        // once the app has finished launching, and stops everything on termination.
        AppServices.shared = AppServices(
            coordinator: coordinator,
            providers: enabled,
            reviewerMode: reviewer,
            statusItems: statusItems,
            preferences: globalPreferences,
            launch: launch
        )

        if !launch.isIsolated {
            AppRuntimeState.recordBreadcrumb("app-init")
        }
    }

    private static func terminateIfSecondaryInstance() {
        guard let bundleIdentifier = Bundle.main.bundleIdentifier else { return }
        let runningApps = NSRunningApplication.runningApplications(withBundleIdentifier: bundleIdentifier)
        if runningApps.count > 1 {
            // Terminate after a brief delay to ensure NSApp is ready
            DispatchQueue.main.async {
                NSApp.terminate(nil)
            }
        }
    }

    var body: some Scene {
        Settings {
            SettingsView(
                viewModel: viewModel,
                codexViewModel: codexViewModel,
                grokViewModel: grokViewModel,
                openRouterViewModel: openRouterViewModel,
                providers: enabledProviders,
                preferences: preferences
            )
        }
    }
}

enum AppMemoryPressureLevel: String, Sendable {
    case warning
    case critical
}

extension Notification.Name {
    static let planTrackerMemoryPressure = Notification.Name("PlanTrackerMemoryPressure")
}

struct LaunchRecoveryState: Sendable {
    let wasUnexpectedTermination: Bool
    let previousLaunchDate: Date?
    let previousHeartbeatDate: Date?
}

/// Launch bookkeeping and bounded lifecycle breadcrumbs. Host-level only: providers add
/// their own id to the messages they record and never log data values.
enum AppRuntimeState {
    private static let logger = Logger(
        subsystem: Bundle.main.bundleIdentifier ?? "com.infinitecontext.plantracker",
        category: "Lifecycle"
    )
    private static let defaults = UserDefaults.standard
    private static let didLaunchCleanlyKey = "host.runtime.didLaunchCleanly"
    private static let lastLaunchDateKey = "host.runtime.lastLaunchDate"
    private static let lastLaunchTimestampKey = "host.runtime.lastLaunchTimestamp"
    private static let lastHeartbeatDateKey = "host.runtime.lastHeartbeatDate"
    private static let lastHeartbeatTimestampKey = "host.runtime.lastHeartbeatTimestamp"
    private static let lastBreadcrumbsKey = "host.runtime.lastBreadcrumbs"
    private static let maxBreadcrumbs = 40
    private static var cachedLaunchState: LaunchRecoveryState?
    /// Breadcrumbs are quiet while isolated (tests, UI tests) so they never touch real defaults.
    static var isSilenced = AppLaunchContext.current.isIsolated

    static func beginLaunchIfNeeded() -> LaunchRecoveryState {
        if let cachedLaunchState {
            return cachedLaunchState
        }

        let previousLaunchDate = defaults.object(forKey: lastLaunchDateKey) as? Date
        let previousHeartbeatDate = defaults.object(forKey: lastHeartbeatDateKey) as? Date
        let hadPriorLaunch = previousLaunchDate != nil
        let didLaunchCleanly = defaults.object(forKey: didLaunchCleanlyKey) as? Bool ?? true

        let state = LaunchRecoveryState(
            wasUnexpectedTermination: hadPriorLaunch && !didLaunchCleanly,
            previousLaunchDate: previousLaunchDate,
            previousHeartbeatDate: previousHeartbeatDate
        )

        let now = Date()
        defaults.set(false, forKey: didLaunchCleanlyKey)
        defaults.set(now, forKey: lastLaunchDateKey)
        defaults.set(now.timeIntervalSince1970, forKey: lastLaunchTimestampKey)
        defaults.set(now, forKey: lastHeartbeatDateKey)
        defaults.set(now.timeIntervalSince1970, forKey: lastHeartbeatTimestampKey)
        LoginItemSharedState.markMainAppLaunch(at: now)
        cachedLaunchState = state

        recordBreadcrumb("launch-begin")
        return state
    }

    static func recordHeartbeat(reason: String) {
        guard !isSilenced else { return }
        let now = Date()
        defaults.set(now, forKey: lastHeartbeatDateKey)
        defaults.set(now.timeIntervalSince1970, forKey: lastHeartbeatTimestampKey)
        LoginItemSharedState.markHeartbeat(at: now)
        recordBreadcrumb("heartbeat-\(reason)")
    }

    static func recordBreadcrumb(_ message: String) {
        guard !isSilenced else { return }
        let formatter = ISO8601DateFormatter()
        let entry = "\(formatter.string(from: Date())) \(message)"
        logger.notice("\(entry, privacy: .public)")

        var breadcrumbs = defaults.stringArray(forKey: lastBreadcrumbsKey) ?? []
        breadcrumbs.append(entry)
        if breadcrumbs.count > maxBreadcrumbs {
            breadcrumbs.removeFirst(breadcrumbs.count - maxBreadcrumbs)
        }
        defaults.set(breadcrumbs, forKey: lastBreadcrumbsKey)
        let now = Date()
        defaults.set(now, forKey: lastHeartbeatDateKey)
        defaults.set(now.timeIntervalSince1970, forKey: lastHeartbeatTimestampKey)
        LoginItemSharedState.markHeartbeat(at: now)
    }

    /// Called exactly once per process, from the delegate, after runtimes have stopped.
    static func markCleanTermination() {
        guard !isSilenced, isPrimaryInstance else { return }
        defaults.set(true, forKey: didLaunchCleanlyKey)
        let now = Date()
        defaults.set(now, forKey: lastHeartbeatDateKey)
        defaults.set(now.timeIntervalSince1970, forKey: lastHeartbeatTimestampKey)
        LoginItemSharedState.markCleanTermination(at: now)
        recordBreadcrumb("termination-clean")
        defaults.synchronize()
    }

    /// Records intent before Quit so the login helper does not relaunch the app.
    static func prepareForUserInitiatedTermination(reason: String) {
        guard !isSilenced, isPrimaryInstance else { return }
        let now = Date()
        LoginItemSharedState.markUserInitiatedTermination(at: now)
        recordBreadcrumb("termination-user-\(reason)")
        defaults.synchronize()
    }

    private static var isPrimaryInstance: Bool {
        guard let bundleIdentifier = Bundle.main.bundleIdentifier else { return true }
        return NSRunningApplication.runningApplications(withBundleIdentifier: bundleIdentifier).count <= 1
    }
}

/// Everything the app delegate needs from the composition root. Set once in `App.init`,
/// before the delegate's launch callback runs.
@MainActor
final class AppServices {
    static var shared: AppServices?

    let coordinator: ProviderRuntimeCoordinator
    let providers: EnabledProviders
    let reviewerMode: ReviewerMode
    let statusItems: StatusItemController
    let preferences: GlobalPreferences
    let launch: AppLaunchContext

    init(
        coordinator: ProviderRuntimeCoordinator,
        providers: EnabledProviders,
        reviewerMode: ReviewerMode,
        statusItems: StatusItemController,
        preferences: GlobalPreferences,
        launch: AppLaunchContext
    ) {
        self.coordinator = coordinator
        self.providers = providers
        self.reviewerMode = reviewerMode
        self.statusItems = statusItems
        self.preferences = preferences
        self.launch = launch
    }
}

final class PlanTrackerAppDelegate: NSObject, NSApplicationDelegate {
    private var memoryPressureSource: DispatchSourceMemoryPressure?
    private var isTerminating = false

    func applicationDidFinishLaunching(_ notification: Notification) {
        AppRuntimeState.recordBreadcrumb("did-finish-launching")
        installMemoryPressureSource()

        guard let services = AppServices.shared else { return }
        // The unit-test host only needs to exist; it must not start providers or show items.
        guard !services.launch.isTestHost else { return }

        services.statusItems.start()

        if services.launch.isDemo {
            services.reviewerMode.activate()
            return
        }
        services.coordinator.start(observing: services.providers)
    }

    func applicationDidBecomeActive(_ notification: Notification) {
        AppRuntimeState.recordBreadcrumb("did-become-active")
        // The user may have just flipped the switch in System Settings → Login Items.
        AppServices.shared?.preferences.refreshLoginItemState()
    }

    func applicationDidResignActive(_ notification: Notification) {
        AppRuntimeState.recordBreadcrumb("did-resign-active")
    }

    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        guard !isTerminating else { return .terminateNow }
        isTerminating = true
        guard let services = AppServices.shared else { return .terminateNow }
        services.statusItems.closeAll()
        Task { @MainActor in
            await services.coordinator.stopAll()
            NSApp.reply(toApplicationShouldTerminate: true)
        }
        return .terminateLater
    }

    func applicationWillTerminate(_ notification: Notification) {
        AppRuntimeState.markCleanTermination()
    }

    private func installMemoryPressureSource() {
        let source = DispatchSource.makeMemoryPressureSource(
            eventMask: [.warning, .critical],
            queue: .main
        )
        source.setEventHandler { [weak self] in
            self?.handleMemoryPressureEvent(source.data)
        }
        source.resume()
        memoryPressureSource = source
        AppRuntimeState.recordBreadcrumb("memory-pressure-monitor-installed")
    }

    private func handleMemoryPressureEvent(_ event: DispatchSource.MemoryPressureEvent) {
        let level: AppMemoryPressureLevel
        if event.contains(.critical) {
            level = .critical
        } else if event.contains(.warning) {
            level = .warning
        } else {
            return
        }

        AppRuntimeState.recordBreadcrumb("memory-pressure-\(level.rawValue)")
        NotificationCenter.default.post(name: .planTrackerMemoryPressure, object: level)
    }
}
