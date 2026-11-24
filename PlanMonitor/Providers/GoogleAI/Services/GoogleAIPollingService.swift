import Foundation

/// Owns the refresh loop: each cycle runs the helper script once and reads agy's report.
///
/// `OpenCodePollingService`'s shape: an interruptible sleep, so an interval change applies at once
/// with no run; a published deadline for the footer countdown; backoff with jitter while runs fail
/// transiently. A missing script is checked before anything runs, so an uninstalled provider costs
/// one file check per cycle and picks up an installation by itself.
actor GoogleAIPollingService {
    /// agy takes ~3 s; a cold start can take longer (CodexBar allows 90 s).
    static let runTimeout: TimeInterval = 90

    private let runner: any GoogleAIScriptRunning

    private var pollingTask: Task<Void, Never>?
    private var interval: TimeInterval = 300
    private var inFlight = false
    private var consecutiveFailures = 0
    private var cycleGeneration = 0
    private var onUpdate: (@Sendable (GoogleAIUsage, Date) -> Void)?
    private var onError: (@Sendable (GoogleAIRunError) -> Void)?
    private var onSchedule: (@Sendable (Date?) -> Void)?
    private var nextFireAt: Date? {
        didSet { onSchedule?(nextFireAt) }
    }

    init(runner: any GoogleAIScriptRunning) {
        self.runner = runner
    }

    func setCallbacks(
        onUpdate: @escaping @Sendable (GoogleAIUsage, Date) -> Void,
        onError: @escaping @Sendable (GoogleAIRunError) -> Void,
        onSchedule: (@Sendable (Date?) -> Void)? = nil
    ) {
        self.onUpdate = onUpdate
        self.onError = onError
        self.onSchedule = onSchedule
    }

    func setInterval(_ newValue: TimeInterval) {
        let clamped = max(180, newValue)
        guard clamped != interval else { return }
        interval = clamped
        consecutiveFailures = 0
        cycleGeneration &+= 1        // interrupts the pending sleep, no run
    }

    /// Restarts the pending cycle from now without running.
    func restartCycle() {
        cycleGeneration &+= 1
    }

    func start() {
        stop()
        pollingTask = Task { [weak self] in
            guard let self else { return }
            while !Task.isCancelled {
                await self.poll()
                await self.sleepUntilNextCycle()
            }
        }
    }

    func stop() {
        pollingTask?.cancel()
        pollingTask = nil
        nextFireAt = nil
    }

    /// The manual Refresh: run now, then owe the automatic poll a full delay.
    func refreshNow() async {
        await poll()
        restartCycle()
    }

    // MARK: - Cycle

    private func poll() async {
        guard !inFlight else { return }
        inFlight = true
        defer { inFlight = false }

        let result: Result<GoogleAIUsage, GoogleAIRunError>
        if runner.scriptState() == .notInstalled {
            result = .failure(.scriptMissing)
        } else {
            do {
                let data = try await runner.run(timeout: Self.runTimeout)
                result = .success(try GoogleAIUsageReport.parse(data))
            } catch {
                result = .failure(error)
            }
        }

        switch result {
        case .success(let usage):
            consecutiveFailures = 0
            onUpdate?(usage, Date())
        case .failure(let error):
            if error.isTransient {
                consecutiveFailures += 1
            }
            onError?(error)
        }
    }

    // MARK: - Interruptible sleep

    private func sleepUntilNextCycle() async {
        var generation = cycleGeneration
        var deadline = nextDeadline()
        nextFireAt = deadline
        defer { nextFireAt = nil }
        while !Task.isCancelled {
            if cycleGeneration != generation {
                generation = cycleGeneration
                deadline = nextDeadline()
                nextFireAt = deadline
            }
            let remaining = deadline.timeIntervalSinceNow
            if remaining <= 0 { return }
            let slice = min(remaining, 1.0)
            try? await Task.sleep(nanoseconds: UInt64(slice * 1_000_000_000))
        }
    }

    private func nextDeadline(from now: Date = Date()) -> Date {
        now.addingTimeInterval(backoffDelay ?? interval)
    }

    private var backoffDelay: TimeInterval? {
        guard consecutiveFailures > 0 else { return nil }
        let exponent = min(consecutiveFailures, 6)
        let base = min(interval * pow(2, Double(exponent)), 3600)
        return base * Double.random(in: 0.85...1.15)
    }
}
