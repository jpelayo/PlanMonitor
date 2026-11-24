import AppKit
import Foundation

/// Puts the helper script where `NSUserUnixTask` may run it. The app cannot write to its own
/// Application Scripts folder; the user grants that by saving through a Save dialog that opens
/// there (the `files.user-selected.read-write` entitlement). Saving anywhere else is refused.
@MainActor
enum GoogleAIScriptInstaller {
    enum Outcome: Equatable {
        case installed
        case cancelled
        case wrongFolder
        case failed(String)
    }

    static func install() -> Outcome {
        guard let directory = UserUnixTaskGoogleAIRunner.scriptsDirectory else {
            return .failed(String(localized: "The scripts folder could not be found."))
        }
        NSApp.activate(ignoringOtherApps: true)
        let panel = NSSavePanel()
        panel.directoryURL = directory
        panel.nameFieldStringValue = GoogleAIScript.fileName
        panel.canCreateDirectories = false
        panel.isExtensionHidden = false
        panel.title = String(localized: "Install script")
        panel.message = String(localized: "Save the helper script in this folder. It only runs agy -p /usage to read your Antigravity limits.")
        panel.prompt = String(localized: "Install")
        guard panel.runModal() == .OK, let url = panel.url else { return .cancelled }

        guard url.deletingLastPathComponent().standardizedFileURL.path == directory.standardizedFileURL.path,
              url.lastPathComponent == GoogleAIScript.fileName else {
            return .wrongFolder
        }
        do {
            try Data(GoogleAIScript.contents.utf8).write(to: url, options: .atomic)
            try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: url.path)
        } catch {
            return .failed(error.localizedDescription)
        }
        return .installed
    }

    /// Opens the folder in Finder, the script selected when it is there.
    static func showFolder() {
        guard let directory = UserUnixTaskGoogleAIRunner.scriptsDirectory else { return }
        if let script = UserUnixTaskGoogleAIRunner.scriptURL, FileManager.default.fileExists(atPath: script.path) {
            NSWorkspace.shared.activateFileViewerSelecting([script])
        } else {
            NSWorkspace.shared.open(directory)
        }
    }
}
