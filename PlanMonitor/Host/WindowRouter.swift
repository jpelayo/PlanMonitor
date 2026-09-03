import AppKit
import SwiftUI

/// The auxiliary windows (sign-in, connect) and Settings. With the menu bar owned by AppKit,
/// these are plain `NSWindow`s hosting the provider's SwiftUI view; Settings stays the SwiftUI
/// `Settings` scene and is opened through the app's standard action.
@MainActor
final class WindowRouter: NSObject, NSWindowDelegate {
    enum AppWindow: String, CaseIterable {
        case loginClaude = "login-claude"
        case loginCodex = "login-codex"
        case loginGrok = "login-grok"
        case connectOpenRouter = "connect-openrouter"

        var title: String {
            switch self {
            case .loginClaude: String(localized: "Sign in to Claude")
            case .loginCodex: String(localized: "Sign in to Codex")
            case .loginGrok: String(localized: "Sign in to Grok")
            case .connectOpenRouter: String(localized: "Connect OpenRouter")
            }
        }
    }

    static let shared = WindowRouter()

    private var builders: [AppWindow: () -> AnyView] = [:]
    private var windows: [AppWindow: NSWindow] = [:]

    private override init() {
        super.init()
    }

    /// Registered once by the composition root.
    func register(_ id: AppWindow, content: @escaping () -> AnyView) {
        builders[id] = content
    }

    func open(_ id: AppWindow) {
        if let window = windows[id] {
            NSApp.activate(ignoringOtherApps: true)
            window.makeKeyAndOrderFront(nil)
            return
        }
        guard let builder = builders[id] else { return }

        let hosting = NSHostingController(rootView: builder())
        hosting.sizingOptions = [.preferredContentSize]
        let window = NSWindow(contentViewController: hosting)
        window.title = id.title
        window.styleMask = [.titled, .closable, .miniaturizable]
        window.isReleasedWhenClosed = false
        window.setContentSize(hosting.view.fittingSize)
        window.setAccessibilityIdentifier("window.\(id.rawValue)")
        window.delegate = self
        window.center()
        windows[id] = window

        NSApp.activate(ignoringOtherApps: true)
        window.makeKeyAndOrderFront(nil)
    }

    func close(_ id: AppWindow) {
        windows[id]?.close()
    }

    var isOpen: (AppWindow) -> Bool {
        { [weak self] id in self?.windows[id] != nil }
    }

    /// The SwiftUI `Settings` scene, via AppKit's standard responder action. Activation is
    /// asynchronous, so the action is sent on the next run-loop turn once the app is active
    /// and a key window exists for the responder chain; the pre-Sonoma selector is tried too.
    func openSettings() {
        NSApp.activate(ignoringOtherApps: true)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
            let handled = NSApp.sendAction(Selector(("showSettingsWindow:")), to: nil, from: nil)
            if !handled {
                _ = NSApp.sendAction(Selector(("showPreferencesWindow:")), to: nil, from: nil)
            }
            NSApp.activate(ignoringOtherApps: true)
        }
    }

    // MARK: - NSWindowDelegate

    func windowWillClose(_ notification: Notification) {
        guard let window = notification.object as? NSWindow,
              let id = windows.first(where: { $0.value === window })?.key else { return }
        // Release the hosted view so its WebView and state go away with the window.
        window.contentViewController = nil
        windows[id] = nil
    }
}
