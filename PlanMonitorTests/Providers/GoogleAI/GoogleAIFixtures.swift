import Foundation
@testable import PlanMonitor

/// agy 1.5.14's `/usage --output-format json`, as read on 2026-11-23, trimmed to the fields that
/// matter (prose shortened; no account data is in the report).
enum GoogleAIFixtures {
    static let report = Data(#"""
    {"conversation_id":"","status":"SUCCESS","response":"…","duration_seconds":0,"num_turns":0,
     "usage":{"input_tokens":0,"output_tokens":0,"thinking_tokens":0,"cache_read_tokens":0,"total_tokens":0},
     "command":{"name":"usage","data":{"description":"Within each group, models share a weekly limit and a 5-hour limit.",
      "groups":[
       {"name":"Gemini Models","description":"Models within this group: Gemini 4 Neon, Gemini 4 Hydrogen",
        "buckets":[
         {"id":"gemini-weekly","name":"Weekly Limit Remaining","description":"…","window":"weekly",
          "remaining_fraction":0.7022169232368469,"reset_time":"2026-11-29T14:03:00Z"},
         {"id":"gemini-5h","name":"Five Hour Limit Remaining","description":"…","window":"5h",
          "remaining_fraction":0.5478848218917847,"reset_time":"2026-11-23T18:30:18Z"}]},
       {"name":"Claude and GPT models","description":"…",
        "buckets":[
         {"id":"3p-weekly","name":"Weekly Limit Remaining","window":"weekly","remaining_fraction":1,"reset_time":"2026-11-30T18:26:44Z"},
         {"id":"3p-5h","name":"Five Hour Limit Remaining","window":"5h","remaining_fraction":1,"reset_time":"2026-11-23T23:26:44Z"}]},
       {"name":"Gemini 4 Argon","description":"…",
        "buckets":[
         {"id":"gemini-argon-wtu-weekly","name":"Gemini 4 Argon Weekly Limit","window":"weekly","remaining_fraction":1,"reset_time":"2026-11-30T18:26:44Z"}]}]}}}
    """#.utf8)
}

/// Returns whatever it is told to, counting runs; never touches the machine.
nonisolated final class FakeGoogleAIRunner: GoogleAIScriptRunning, @unchecked Sendable {
    private let lock = NSLock()
    private var _state: GoogleAIScriptState
    private var _result: Result<Data, GoogleAIRunError>
    private var _runs = 0

    init(state: GoogleAIScriptState = .installed, result: Result<Data, GoogleAIRunError> = .success(GoogleAIFixtures.report)) {
        _state = state
        _result = result
    }

    var runs: Int { lock.withLock { _runs } }

    func set(state: GoogleAIScriptState? = nil, result: Result<Data, GoogleAIRunError>? = nil) {
        lock.withLock {
            if let state { _state = state }
            if let result { _result = result }
        }
    }

    func scriptState() -> GoogleAIScriptState { lock.withLock { _state } }

    func run(timeout: TimeInterval) async throws(GoogleAIRunError) -> Data {
        let result = lock.withLock { () -> Result<Data, GoogleAIRunError> in
            _runs += 1
            return _result
        }
        return try result.get()
    }
}
