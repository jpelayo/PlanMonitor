import Foundation
import SwiftUI

/// Google AI: the Antigravity limits — Gemini models, Claude and GPT models, Gemini 4 Argon, each
/// group's 5-hour and weekly windows — as `agy -p /usage --output-format json` reports them.
///
/// There is no sign-in and nothing in the Keychain: agy keeps its own. The app cannot start agy
/// (sandbox), so a helper script the user installs runs it (`GoogleAIScript`, `NSUserUnixTask`).
/// States: no script or no agy → the setup state, no gauges; agy failing or answering oddly → the
/// last figures kept, stale, with a neutral line. The Gemini app's own limits are a later source.
@MainActor
@Observable
final class GoogleAIViewModel {
    private(set) var scriptState: GoogleAIScriptState = .notInstalled
    private(set) var usage: GoogleAIUsage = .empty
    private(set) var lastUpdated: Date?
    private(set) var lastError: GoogleAIRunError?
    private(set) var isLoading = false
    private(set) var isDemoMode = false
    private(set) var nextRefreshAt: Date?
    /// The setup window's "Test now" / install result line.
    private(set) var setupMessage: String?

    var pollingIntervalMinutes: Int = 5 {
        didSet {
            let seconds = TimeInterval(pollingIntervalMinutes * 60)
            Task { await pollingService.setInterval(seconds) }
        }
    }

    /// The figures are shown: a report has been read and nothing says setup is missing.
    var showsUsage: Bool {
        if isDemoMode { return true }
        if let lastError, lastError.needsSetup { return false }
        return !usage.isEmpty
    }

    /// The dropdown offers setup instead of gauges.
    var needsSetup: Bool {
        if isDemoMode { return false }
        if scriptState == .notInstalled { return true }
        if let lastError, lastError.needsSetup { return true }
        return false
    }

    /// The line shown under the gauges: transient failures only (the setup states have their own UI).
    var errorMessage: String? {
        guard let lastError, !lastError.needsSetup else { return nil }
        return lastError.message
    }

    /// Three missed cycles in a row.
    var isStale: Bool {
        guard let lastUpdated, !isDemoMode else { return false }
        return Date().timeIntervalSince(lastUpdated) > TimeInterval(pollingIntervalMinutes * 60 * 3)
    }

    let sessionPreferences: SessionTrackingPreferences
    let sessionTracker: SessionTracker
    let menuBarText: MenuBarTextPreferences

    private let runner: any GoogleAIScriptRunning
    private let pollingService: GoogleAIPollingService
    private let snapshotStore: GoogleAISnapshotStore
    private var isPolling = false
    private var callbacksInstalled = false

    init(
        defaults: UserDefaults = .standard,
        runner: any GoogleAIScriptRunning,
        collectDelay: TimeInterval = GoogleAIPollingService.collectDelay
    ) {
        self.runner = runner
        self.pollingService = GoogleAIPollingService(runner: runner, collectDelay: collectDelay)
        self.snapshotStore = GoogleAISnapshotStore(defaults: defaults)
        self.sessionPreferences = SessionTrackingPreferences(namespace: "googleai", defaults: defaults)
        self.sessionTracker = SessionTracker(namespace: "googleai", defaults: defaults)
        self.menuBarText = MenuBarTextPreferences(namespace: "googleai", defaults: defaults)
    }

    // MARK: - Lifecycle

    func resume() async {
        guard !isDemoMode else { return }
        scriptState = runner.scriptState()
        if usage.isEmpty { restorePersistedSnapshot() }
        await startPolling()
    }

    func suspend() async {
        isPolling = false
        await pollingService.stop()
        nextRefreshAt = nil
    }

    func refreshUsage() async {
        guard !isDemoMode, !isLoading else { return }
        AppRuntimeState.recordBreadcrumb("provider-googleai-manual-refresh")
        isLoading = true
        scriptState = runner.scriptState()
        await installCallbacksIfNeeded()
        await pollingService.refreshNow()
        isLoading = false
    }

    private func startPolling() async {
        AppRuntimeState.recordBreadcrumb("provider-googleai-poll-start")
        isPolling = true
        await installCallbacksIfNeeded()
        await pollingService.setInterval(TimeInterval(pollingIntervalMinutes * 60))
        await pollingService.start()
    }

    // MARK: - Setup

    /// The Save dialog, then an immediate run so the user sees whether it works.
    func installScript() async {
        switch GoogleAIScriptInstaller.install() {
        case .installed:
            AppRuntimeState.recordBreadcrumb("provider-googleai-script-installed")
            scriptState = runner.scriptState()
            await testNow()
        case .cancelled:
            break
        case .wrongFolder:
            setupMessage = String(localized: "Save the script in the folder the dialog opens, with its own name.")
        case .failed(let reason):
            setupMessage = reason
        }
    }

    /// Runs the script once, as the setup window's "Test now".
    func testNow() async {
        guard !isDemoMode else { return }
        setupMessage = String(localized: "Running agy…")
        await refreshUsage()
        if let lastError {
            setupMessage = lastError.message
        } else {
            setupMessage = String(localized: "Working: \(usage.buckets.count) limits read.")
        }
    }

    func refreshScriptState() {
        scriptState = runner.scriptState()
    }

    var dailySessionFormatted: String? {
        guard sessionPreferences.isEnabled else { return nil }
        return SessionTimeFormatter.line(totalSeconds: sessionTracker.totalSeconds)
    }

    // MARK: - Wiring

    /// Awaited before the first poll, so no report can arrive before anyone listens.
    private func installCallbacksIfNeeded() async {
        guard !callbacksInstalled else { return }
        callbacksInstalled = true
        await pollingService.setCallbacks(
            onUpdate: { [weak self] usage, fetchedAt in
                Task { @MainActor [weak self] in
                    self?.apply(usage, fetchedAt: fetchedAt)
                }
            },
            onError: { [weak self] error in
                Task { @MainActor [weak self] in
                    self?.apply(error)
                }
            },
            onSchedule: { [weak self] date in
                Task { @MainActor [weak self] in
                    self?.nextRefreshAt = date
                }
            }
        )
    }

    private func apply(_ newUsage: GoogleAIUsage, fetchedAt: Date) {
        guard !isDemoMode else { return }
        usage = newUsage
        lastUpdated = fetchedAt
        lastError = nil
        scriptState = runner.scriptState()
        if sessionPreferences.isEnabled {
            sessionTracker.processTick(
                signals: Self.activitySignals(for: newUsage),
                minInterval: sessionPreferences.checkInterval,
                resetHour: sessionPreferences.resetHour
            )
        }
        snapshotStore.save(usage: usage, lastUpdated: fetchedAt)
    }

    /// The used share of each 5-hour window — counters that only grow within the window, so a
    /// reset reads as a drop rather than as activity. Never a remaining figure.
    static func activitySignals(for usage: GoogleAIUsage) -> [ActivitySignal] {
        usage.buckets
            .filter { $0.kind == .fiveHour }
            .compactMap { ActivitySignal.percent($0.id, $0.used * 100) }
    }

    private func apply(_ error: GoogleAIRunError) {
        guard !isDemoMode else { return }
        lastError = error
        if error == .scriptMissing { scriptState = .notInstalled }
        AppRuntimeState.recordBreadcrumb("provider-googleai-run-failed")
    }

    // MARK: - Snapshot persistence

    private func restorePersistedSnapshot() {
        guard let persisted = snapshotStore.load() else { return }
        usage = persisted.usage
        lastUpdated = persisted.lastUpdated
        AppRuntimeState.recordBreadcrumb("provider-googleai-snapshot-restored")
    }
}

// MARK: - Reviewer mode

extension GoogleAIViewModel: DemoCapable {
    func enterDemo() {
        guard !isDemoMode else { return }
        isDemoMode = true
        isPolling = false
        Task { [pollingService] in await pollingService.stop() }
        nextRefreshAt = nil
        let now = Date()
        usage = GoogleAIDemoSnapshot.usage(now: now)
        lastUpdated = now
        lastError = nil
        scriptState = .installed
        sessionTracker.setMockAccumulated(97 * 60) // 1h 37m
    }
}
