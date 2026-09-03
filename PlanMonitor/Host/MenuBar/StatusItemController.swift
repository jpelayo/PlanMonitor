import AppKit
import Observation
import SwiftUI

/// One `NSStatusItem` per enabled provider, in stable left-to-right order, each with an
/// `NSPopover` hosting that provider's SwiftUI dropdown. AppKit renders the label: the symbol
/// as a template image (or palette-coloured when severity asks for it) and the digits as an
/// attributed title, so they stay real text — adaptive, highlightable, accessible — and can
/// carry a colour, a face, or a size without being rasterised.
@MainActor
final class StatusItemController: NSObject, NSPopoverDelegate {
    struct Provider {
        let id: ProviderID
        let label: () -> MenuBarLabel
        let content: () -> AnyView
    }

    private struct Entry {
        let item: NSStatusItem
        let popover: NSPopover
        var lastLabel: MenuBarLabel?
    }

    private let providers: [ProviderID: Provider]
    private let enabledProviders: EnabledProviders
    private var entries: [ProviderID: Entry] = [:]
    private var enablementToken: AnyObject?

    init(providers: [Provider], enabledProviders: EnabledProviders) {
        self.providers = Dictionary(uniqueKeysWithValues: providers.map { ($0.id, $0) })
        self.enabledProviders = enabledProviders
        super.init()
    }

    /// Creates the items for the currently enabled providers and follows changes from then on.
    func start() {
        syncEnabledItems()
        // Synchronous: the item must appear in the same event as the checkbox click, and a
        // transient popover can hold the run loop long enough that a scheduled task would
        // only run after it closes.
        enablementToken = enabledProviders.observeSynchronously { [weak self] _ in
            self?.syncEnabledItems()
        }
    }

    // MARK: - Enablement

    private func syncEnabledItems() {
        // Removals first so a newly enabled item never lands to the right of a stale one.
        for provider in ProviderID.allCases where !enabledProviders.isEnabled(provider) {
            removeItem(for: provider)
        }
        // New status items are inserted at the left edge of the status area, so create in
        // reverse order to end up with Claude, Codex, Grok, OpenRouter left to right.
        for provider in ProviderID.allCases.reversed() where enabledProviders.isEnabled(provider) {
            addItemIfNeeded(for: provider)
        }
    }

    private func addItemIfNeeded(for provider: ProviderID) {
        guard entries[provider] == nil, let definition = providers[provider] else { return }

        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        item.autosaveName = "PlanTracker.\(provider.rawValue)"
        item.behavior = []
        // macOS persists visibility per autosave name; an item that was removed or dragged
        // out earlier would otherwise come back hidden. Enabling means showing.
        item.isVisible = true

        let popover = NSPopover()
        popover.behavior = .transient
        popover.animates = true
        popover.delegate = self

        if let button = item.button {
            button.target = self
            button.action = #selector(togglePopover(_:))
            button.sendAction(on: [.leftMouseUp])
            button.imagePosition = .imageLeading
            button.imageHugsTitle = true
            button.setAccessibilityIdentifier("menubar.\(provider.rawValue)")
        }

        entries[provider] = Entry(item: item, popover: popover, lastLabel: nil)
        render(provider)
        observeLabel(provider, definition: definition)
    }

    private func removeItem(for provider: ProviderID) {
        guard let entry = entries.removeValue(forKey: provider) else { return }
        entry.popover.performClose(nil)
        NSStatusBar.system.removeStatusItem(entry.item)
    }

    // MARK: - Label

    private func observeLabel(_ provider: ProviderID, definition: Provider) {
        withObservationTracking {
            // Reading the label inside the tracking block registers every property it
            // depends on; any change re-renders and re-arms.
            _ = definition.label()
        } onChange: {
            Task { @MainActor [weak self] in
                guard let self, self.entries[provider] != nil else { return }
                self.render(provider)
                self.observeLabel(provider, definition: definition)
            }
        }
    }

    private func render(_ provider: ProviderID) {
        guard var entry = entries[provider],
              let definition = providers[provider],
              let button = entry.item.button else { return }
        let label = definition.label()
        guard label != entry.lastLabel else { return }
        entry.lastLabel = label
        entries[provider] = entry

        let symbol = Self.symbolImage(for: label)

        // Symbol and digits in one attributed string, so AppKit lays both out on one
        // baseline: the attachment is centred on the cap height, i.e. on the visual centre
        // of the digits, and follows them whatever the font size is. The same path is used
        // with no digits, so the glyph sits at the same height signed out and signed in.
        button.image = nil
        button.imagePosition = .noImage
        button.attributedTitle = Self.attributedTitle(symbol: symbol, text: label.text ?? "", label: label)

        button.setAccessibilityLabel(label.accessibilityLabel)
        button.setAccessibilityValue(label.accessibilityValue ?? label.text)

        // No padding of our own: the item is exactly as wide as its content. Whatever gap
        // remains is the system's status-bar spacing, which no app can reduce.
        entry.item.length = NSStatusItem.variableLength
    }

    private static func attributedTitle(symbol: NSImage?, text: String, label: MenuBarLabel) -> NSAttributedString {
        let title = NSMutableAttributedString()

        if let symbol {
            let attachment = NSTextAttachment()
            attachment.image = symbol
            // Centre the glyph on the digits' cap height. A template image drawn as an
            // attachment takes the title's colour, so it stays adaptive and inverts on
            // highlight exactly like the digits.
            let capCentre = label.font.capHeight / 2
            attachment.bounds = CGRect(
                x: 0,
                y: capCentre - symbol.size.height / 2,
                width: symbol.size.width,
                height: symbol.size.height
            )
            title.append(NSAttributedString(attachment: attachment))
            if !text.isEmpty {
                title.append(NSAttributedString(string: " ", attributes: [.font: label.font]))
            }
        }
        guard !text.isEmpty else { return title }

        var attributes: [NSAttributedString.Key: Any] = [.font: label.font]
        if let tint = label.textTint {
            attributes[.foregroundColor] = tint
        }
        title.append(NSAttributedString(string: text, attributes: attributes))
        return title
    }

    private static func symbolImage(for label: MenuBarLabel) -> NSImage? {
        var configuration = NSImage.SymbolConfiguration(pointSize: MenuBarLabel.symbolPointSize, weight: .regular)
        if let tint = label.symbolTint {
            configuration = configuration.applying(NSImage.SymbolConfiguration(paletteColors: [tint]))
        }
        let source: NSImage?
        if let variableValue = label.variableValue {
            source = NSImage(systemSymbolName: label.resolvedSymbolName, variableValue: variableValue, accessibilityDescription: nil)
        } else {
            source = NSImage(systemSymbolName: label.resolvedSymbolName, accessibilityDescription: nil)
        }
        guard let image = (source ?? NSImage(systemSymbolName: label.fallbackSymbol, accessibilityDescription: nil))?
            .withSymbolConfiguration(configuration) else { return nil }
        // Template = the bar's adaptive grey and proper highlight inversion. Colour only
        // when severity asks for it.
        image.isTemplate = label.symbolTint == nil
        return image
    }

    // MARK: - Popover

    @objc private func togglePopover(_ sender: NSStatusBarButton) {
        guard let provider = entries.first(where: { $0.value.item.button === sender })?.key else { return }
        toggle(provider)
    }

    func toggle(_ provider: ProviderID) {
        guard let entry = entries[provider], let button = entry.item.button else { return }
        if entry.popover.isShown {
            entry.popover.performClose(nil)
            return
        }
        // Only one dropdown at a time, like MenuBarExtra.
        for other in entries.values where other.popover.isShown {
            other.popover.performClose(nil)
        }
        guard let definition = providers[provider] else { return }
        let hosting = NSHostingController(
            rootView: definition.content().background(MenuMaterialBackground())
        )
        hosting.sizingOptions = [.preferredContentSize]
        entry.popover.contentViewController = hosting
        entry.popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
        button.highlight(true)
        // Accessory apps do not activate when a status item is clicked, and AppKit renders
        // accent-coloured controls desaturated in a non-key window. Activating gives the
        // dropdown the same live appearance a menu-bar window had.
        NSApp.activate(ignoringOtherApps: true)
        entry.popover.contentViewController?.view.window?.makeKey()
    }

    func closeAll() {
        for entry in entries.values where entry.popover.isShown {
            entry.popover.performClose(nil)
        }
    }

    func popoverDidClose(_ notification: Notification) {
        guard let popover = notification.object as? NSPopover,
              let entry = entries.values.first(where: { $0.popover === popover }) else { return }
        entry.item.button?.highlight(false)
        // Drop the hosted view so its state (and any WebKit residue) is released.
        popover.contentViewController = nil
    }
}

/// The dropdown sits on the menu material — what macOS menus themselves use — instead of the
/// lighter popover material, so the wallpaper stops bleeding through the content.
private struct MenuMaterialBackground: NSViewRepresentable {
    func makeNSView(context: Context) -> NSVisualEffectView {
        let view = NSVisualEffectView()
        view.material = .menu
        view.blendingMode = .behindWindow
        view.state = .active
        return view
    }

    func updateNSView(_ nsView: NSVisualEffectView, context: Context) {}
}
