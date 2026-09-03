@MainActor
protocol ProviderRuntime: AnyObject {
    var providerID: ProviderID { get }
    func enable() async
    func disable() async
    func refresh() async
    func handleMemoryPressure(_ level: AppMemoryPressureLevel) async
}

extension ProviderRuntime {
    /// Providers without transient caches have nothing to do under pressure.
    func handleMemoryPressure(_ level: AppMemoryPressureLevel) async {}
}

extension ClaudeUsageViewModel: ProviderRuntime {
    var providerID: ProviderID { .claude }
    func enable() async { await resume() }
    func disable() async { await suspend() }
    func refresh() async { await refreshUsage() }
}

extension CodexUsageViewModel: ProviderRuntime {
    var providerID: ProviderID { .codex }
    func enable() async { await resume() }
    func disable() async { await suspend() }
    func refresh() async { await refreshUsage() }
}

extension GrokUsageViewModel: ProviderRuntime {
    var providerID: ProviderID { .grok }
    func enable() async { await resume() }
    func disable() async { await suspend() }
    func refresh() async { await refreshUsage() }
}

extension OpenRouterBudgetViewModel: ProviderRuntime {
    var providerID: ProviderID { .openrouter }
    func enable() async { await resume() }
    func disable() async { await suspend() }
}
