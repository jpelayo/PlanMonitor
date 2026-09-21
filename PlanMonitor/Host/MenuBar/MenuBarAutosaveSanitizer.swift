import Foundation

/// Clears the `NSStatusItem …` bookkeeping that could keep a status item off the menu bar.
///
/// AppKit persists each item's position and visibility in the app's own defaults under its
/// autosave name, and it does so for *anyone's* drag — a menu-bar manager's synthetic ⌘-drag
/// looks exactly like the user's hand. Thaw's notch-overflow code dragged all four items past
/// the left edge and had no restore path, which left positions no display could show. Run this
/// before any item exists: AppKit reads the saved position the moment `autosaveName` is set.
///
/// It touches only what is provably bad. A sane position is the user's own arrangement and
/// must survive every launch.
nonisolated enum MenuBarAutosaveSanitizer {
    /// Returns the keys it removed, so the caller can leave a breadcrumb.
    static func sanitise(
        _ defaults: UserDefaults,
        autosaveNames: [String],
        widestScreen: CGFloat
    ) -> [String] {
        var removed: [String] = []
        func remove(_ key: String) {
            defaults.removeObject(forKey: key)
            // `dictionaryRepresentation()` merges the whole search list; a key that still
            // resolves after removal lived in another domain and was never ours to count.
            if defaults.object(forKey: key) == nil {
                removed.append(key)
            }
        }

        for name in autosaveNames {
            // A position is a distance from the right edge of the status area; nothing beyond
            // the widest connected display, or negative, can be on screen.
            let position = "NSStatusItem Preferred Position \(name)"
            if let value = defaults.object(forKey: position) as? Double,
               value < 0 || value > Double(widestScreen) {
                remove(position)
            }
            // Visibility is forced on when the item is created; a stored `false` only makes
            // the un-named instant before that hidden.
            for key in ["NSStatusItem Visible \(name)", "NSStatusItem VisibleCC \(name)"]
            where defaults.object(forKey: key) as? Bool == false {
                remove(key)
            }
        }

        // `Item-<n>` is the auto-name AppKit assigns between creating an item and the app
        // naming it. Anything persisted under it was written in that instant, never by us.
        for key in defaults.dictionaryRepresentation().keys
        where key.hasPrefix("NSStatusItem ") && Self.isAutoName(key) {
            remove(key)
        }

        return removed.sorted()
    }

    private static func isAutoName(_ key: String) -> Bool {
        guard let range = key.range(of: " Item-") else { return false }
        let suffix = key[range.upperBound...]
        return !suffix.isEmpty && suffix.allSatisfy(\.isNumber)
    }
}
