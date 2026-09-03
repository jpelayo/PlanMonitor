import Foundation
import SwiftUI

@MainActor
@Observable
final class EnabledProviders {
    struct Change: Sendable, Equatable {
        let provider: ProviderID
        let isEnabled: Bool
    }

    private static let key = "enabledProviders"
    private static let appGroup = "group.com.infinitecontext.plantracker"

    private(set) var values: Set<ProviderID>
    private let defaults: UserDefaults
    private var continuations: [UUID: AsyncStream<Change>.Continuation] = [:]
    /// Called on the main actor, inside `set`, before the async stream is fed. For work that
    /// must happen in the same event as the click — the menu bar cannot wait for a run-loop
    /// turn that a transient popover may be holding.
    private var synchronousObservers: [UUID: (Change) -> Void] = [:]

    init(defaults: UserDefaults? = nil) {
        self.defaults = defaults
            ?? UserDefaults(suiteName: Self.appGroup)
            ?? .standard

        let stored = self.defaults.stringArray(forKey: Self.key)
        let decoded = Set((stored ?? []).compactMap(ProviderID.init(rawValue:)))
        if stored == nil || decoded.isEmpty {
            values = [.claude]
            persist()
        } else {
            values = decoded
            // Rewrite only when the stored form is not already canonical, so a value
            // written by a newer build that knows more providers is not destroyed.
            if stored != Self.canonicalOrder(decoded) && (stored?.allSatisfy { ProviderID(rawValue: $0) != nil } ?? false) {
                persist()
            }
        }
    }

    func isEnabled(_ provider: ProviderID) -> Bool {
        values.contains(provider)
    }

    func canDisable(_ provider: ProviderID) -> Bool {
        !isEnabled(provider) || values.count > 1
    }

    /// The invariant lives here, not in the UI: the last enabled provider cannot be
    /// disabled. Observers hear about actual changes only.
    func set(_ provider: ProviderID, enabled: Bool) {
        let before = values
        if enabled {
            values.insert(provider)
        } else if canDisable(provider) {
            values.remove(provider)
        }
        if values.isEmpty {
            values = [.claude]
        }
        guard values != before else { return }
        persist()
        let change = Change(provider: provider, isEnabled: isEnabled(provider))
        for observer in synchronousObservers.values {
            observer(change)
        }
        for continuation in continuations.values {
            continuation.yield(change)
        }
    }

    /// Synchronous notification of every real change. Returns a token; drop it to stop.
    @discardableResult
    func observeSynchronously(_ observer: @escaping (Change) -> Void) -> AnyObject {
        let id = UUID()
        synchronousObservers[id] = observer
        return ObserverToken { [weak self] in
            Task { @MainActor [weak self] in
                self?.synchronousObservers.removeValue(forKey: id)
            }
        }
    }

    private final class ObserverToken {
        private let onDeinit: () -> Void
        init(onDeinit: @escaping () -> Void) { self.onDeinit = onDeinit }
        deinit { onDeinit() }
    }

    func binding(for provider: ProviderID) -> Binding<Bool> {
        Binding(
            get: { [weak self] in (self?.isEnabled(provider)) ?? (provider == .claude) },
            set: { [weak self] in self?.set(provider, enabled: $0) }
        )
    }

    /// Every change after subscription, in the order it happened.
    func changes() -> AsyncStream<Change> {
        let id = UUID()
        return AsyncStream { continuation in
            continuations[id] = continuation
            continuation.onTermination = { [weak self] _ in
                Task { @MainActor [weak self] in
                    self?.continuations.removeValue(forKey: id)
                }
            }
        }
    }

    private func persist() {
        defaults.set(Self.canonicalOrder(values), forKey: Self.key)
    }

    private static func canonicalOrder(_ set: Set<ProviderID>) -> [String] {
        ProviderID.allCases.filter(set.contains).map(\.rawValue)
    }
}
