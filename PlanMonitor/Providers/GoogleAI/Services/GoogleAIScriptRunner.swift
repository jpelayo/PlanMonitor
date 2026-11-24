import Foundation

/// Runs the helper script and returns what it printed. A protocol so tests and the isolated test
/// host never run anything on the machine.
nonisolated protocol GoogleAIScriptRunning: Sendable {
    func scriptState() -> GoogleAIScriptState
    func run(timeout: TimeInterval) async throws(GoogleAIRunError) -> Data
}

/// Under the test host and UI tests: nothing is installed, nothing is ever run.
nonisolated struct NullGoogleAIScriptRunner: GoogleAIScriptRunning {
    func scriptState() -> GoogleAIScriptState { .notInstalled }
    func run(timeout: TimeInterval) async throws(GoogleAIRunError) -> Data { throw .scriptMissing }
}

/// The real runner: `NSUserUnixTask` on the script in the app's Application Scripts folder — the
/// only way a sandboxed app may run something outside the sandbox, and only what the user put there.
nonisolated struct UserUnixTaskGoogleAIRunner: GoogleAIScriptRunning {
    /// Output beyond this is dropped; a usage report is about 2 KB.
    static let outputCap = 1 << 20

    static var scriptsDirectory: URL? {
        try? FileManager.default.url(for: .applicationScriptsDirectory, in: .userDomainMask, appropriateFor: nil, create: true)
    }

    static var scriptURL: URL? {
        scriptsDirectory?.appendingPathComponent(GoogleAIScript.fileName)
    }

    func scriptState() -> GoogleAIScriptState {
        guard let url = Self.scriptURL,
              let data = try? Data(contentsOf: url, options: .mappedIfSafe) else { return .notInstalled }
        return GoogleAIScript.state(forInstalledText: String(decoding: data.prefix(4096), as: UTF8.self))
    }

    func run(timeout: TimeInterval) async throws(GoogleAIRunError) -> Data {
        guard let url = Self.scriptURL, FileManager.default.fileExists(atPath: url.path) else {
            throw .scriptMissing
        }
        let task: NSUserUnixTask
        do {
            task = try NSUserUnixTask(url: url)
        } catch {
            throw .launchFailed
        }

        let output = Pipe()
        let errors = Pipe()
        let stdoutBuffer = CappedBuffer(cap: Self.outputCap)
        let stderrBuffer = CappedBuffer(cap: 16 * 1024)
        output.fileHandleForReading.readabilityHandler = { stdoutBuffer.append($0.availableData) }
        errors.fileHandleForReading.readabilityHandler = { stderrBuffer.append($0.availableData) }
        task.standardOutput = output.fileHandleForWriting
        task.standardError = errors.fileHandleForWriting

        let gate = OnceGate()
        let result: Result<Data, GoogleAIRunError> = await withCheckedContinuation { continuation in
            task.execute(withArguments: nil) { error in
                // The child has exited: drain what is still in the pipes, then decide.
                for (pipe, buffer) in [(output, stdoutBuffer), (errors, stderrBuffer)] {
                    pipe.fileHandleForReading.readabilityHandler = nil
                    try? pipe.fileHandleForWriting.close()
                    buffer.append(pipe.fileHandleForReading.readDataToEndOfFile())
                }
                guard gate.claim() else { return }
                continuation.resume(returning: Self.classify(
                    error: error,
                    stdout: stdoutBuffer.data,
                    stderr: stderrBuffer.data
                ))
            }
            // NSUserUnixTask cannot be cancelled: on timeout the result is abandoned.
            DispatchQueue.global().asyncAfter(deadline: .now() + timeout) {
                guard gate.claim() else { return }
                continuation.resume(returning: .failure(.timedOut))
            }
        }
        return try result.get()
    }

    /// A report on stdout wins whatever the exit status; then the not-found marker; then the kind
    /// of failure. stderr is only matched against the marker, never kept.
    static func classify(error: (any Error)?, stdout: Data, stderr: Data) -> Result<Data, GoogleAIRunError> {
        if error == nil { return .success(stdout) }
        if (try? GoogleAIUsageReport.parse(stdout)) != nil { return .success(stdout) }
        if String(decoding: stderr, as: UTF8.self).contains(GoogleAIScript.agyNotFoundMarker) {
            return .failure(.agyNotFound)
        }
        let nsError = error! as NSError
        if nsError.domain == NSPOSIXErrorDomain || nsError.domain == "NSUserScriptTaskErrorDomain" {
            return .failure(.agyFailed(exit: Int32(truncatingIfNeeded: nsError.code)))
        }
        return .failure(.launchFailed)
    }
}

/// Collects pipe output from the readability handler's queue, up to a cap.
private nonisolated final class CappedBuffer: @unchecked Sendable {
    private let lock = NSLock()
    private var storage = Data()
    private let cap: Int

    init(cap: Int) { self.cap = cap }

    func append(_ chunk: Data) {
        guard !chunk.isEmpty else { return }
        lock.lock(); defer { lock.unlock() }
        let room = cap - storage.count
        guard room > 0 else { return }
        storage.append(chunk.prefix(room))
    }

    var data: Data {
        lock.lock(); defer { lock.unlock() }
        return storage
    }
}

/// Lets exactly one of the completion and the timeout resume the continuation.
private nonisolated final class OnceGate: @unchecked Sendable {
    private let lock = NSLock()
    private var claimed = false

    func claim() -> Bool {
        lock.lock(); defer { lock.unlock() }
        if claimed { return false }
        claimed = true
        return true
    }
}
