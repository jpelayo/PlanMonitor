# PlanMonitor

A native macOS menu bar app that tracks your AI usage limits and spending in real time — for **Claude**, **Codex (ChatGPT)**, **Grok** and **OpenRouter** — from one lightweight process.

![macOS](https://img.shields.io/badge/macOS-15.0+-blue)
![Swift](https://img.shields.io/badge/Swift-6.2+-orange)
![License](https://img.shields.io/badge/license-Apache%202.0-green)

## What it does

Each provider you enable gets its own menu bar item with its own dropdown, sign-in, polling and cache. Enable one, two, or all four — at least one is always on so Settings stays reachable.

| Provider | Signs in with | Shows |
|---|---|---|
| **Claude** | claude.ai (embedded browser) | 5-hour and 7-day limits, per-model weekly windows, credit balances, extra-usage spend, Claude service status |
| **Codex** | chatgpt.com (embedded browser) | 5-hour and weekly limits, every additional limit the API exposes, prepaid credits and overage |
| **Grok** | accounts.x.ai + one-time usage approval | Weekly SuperGrok pool with per-product contributions, monthly allowance, extra usage credits |
| **OpenRouter** | a pasted **management** key (read-only, cannot spend) | Remaining credit, spend over the last 15 min / hour / day / month, projected month, per-key and guardrail budgets, recently used models |

Shared across all four:

- **Session time** — an optional accumulator that infers how long you have been actively using each provider today, from movement in its usage counters. Per-provider on/off, detection interval and daily reset hour.
- **Extra expenditure line** — Claude, Codex and Grok headers show whether pay-as-you-go spend is enabled and how much of the cap is used.
- **Color-coded gauges** — green under 65 % used, orange from 65 %, red from 90 %. The menu bar digits are real text, so they stay readable on light and dark bars; each provider can set their width, size, and spacing.
- **Configurable refresh** — one global interval (3–60 minutes); the countdown in every dropdown is the real next poll.
- **Launch at login** with quiet recovery if macOS closes the app.
- **English and Spanish.**

## Requirements

- macOS 15.0 (Sequoia) or later
- An account with at least one of the supported services

## Installation

### Option 1: App Store / release build

Download the latest build from the [Releases](../../releases) page, open the DMG and drag PlanMonitor to Applications. On first launch, right-click the app and choose **Open** if the build is not notarized, then grant Keychain access when prompted.

### Option 2: Build from source

This repository ships **source only**. The Xcode project, the entitlements files and the helper scripts are deliberately excluded by `.gitignore`, because they embed a signing team ID. You create the scaffolding once in Xcode and it stays yours.

```bash
git clone https://github.com/jpelayo/PlanMonitor.git
cd PlanMonitor
```

Then create a new **macOS App** project in the repository root and wire up two targets.

**App target**

- Add the `PlanMonitor/` folder — `App`, `Host`, `Providers`, `Resources`, `Assets.xcassets`. Remove the template `ContentView.swift` and `<Name>App.swift`; the entry point is `PlanMonitor/PlanTrackerApp.swift`.
- **Signing & Capabilities:** your own Development Team, plus **App Sandbox** (Outgoing Connections → Client, and User Selected File → Read Only), **App Groups**, and **Keychain Sharing** with access group `$(AppIdentifierPrefix)$(CFBundleIdentifier)`.
- **Build settings:** deployment target macOS 15.0, `SWIFT_DEFAULT_ACTOR_ISOLATION = MainActor`, `SWIFT_APPROACHABLE_CONCURRENCY = YES`, `INFOPLIST_KEY_LSUIElement = YES` (menu-bar-only, no Dock icon), display name `PlanMonitor`.

**Login helper target**

- A second macOS App target built from `PlanTrackerLoginHelper/`, with `INFOPLIST_KEY_LSBackgroundOnly = YES`, App Sandbox, and the same App Group as the main app.
- In the main app, add a **Copy Files** build phase — destination *Wrapper*, subpath `Contents/Library/LoginItems` — containing the helper app, so launch-at-login works.

**Identifiers.** For a local build the bundle IDs, app group and Keychain service can be anything, but the entitlements and these constants must agree:

| Constant | Where |
|---|---|
| App group | `Host/EnabledProviders.swift`, `Host/Services/LoginItemSupport.swift`, `PlanTrackerLoginHelper/LoginItemSharedState.swift` |
| Keychain service | `Host/Services/KeychainSecureStore.swift` |
| Helper + main bundle ID | `Host/Services/LoginItemSupport.swift`, `PlanTrackerLoginHelper/LoginItemSharedState.swift` |

Select the app scheme and run (⌘R).

## Usage

1. Launch PlanMonitor — the Claude item appears in your menu bar.
2. Open **Settings…** and tick the providers you want. Each new item appears immediately.
3. Sign in to each provider from its own dropdown (OpenRouter asks for a management key from *Settings → Management Keys* on openrouter.ai).
4. Turn on **Track session time** per provider if you want the daily usage-time line.

To see the app with sample data and no accounts, launch it with the `-demo` argument.

## Privacy & security

- Sessions and keys are stored only in the macOS Keychain, one item per provider, in a versioned format. Signing out of one provider removes only that provider's items.
- Nothing is sent anywhere except to the provider you signed in to. There is no telemetry.
- Each login runs in its own embedded browser locked to that provider's domains; the OpenRouter management key can read usage but cannot make model calls.
- A locked Keychain is treated as temporary: the app keeps showing its last snapshot and retries, it never signs you out.

## Disclaimer

PlanMonitor is an independent tool for use with Claude, Codex, Grok, and OpenRouter. It is not affiliated with the vendors nor endorsed by them.

## Contributing

Pull requests are welcome.

1. Fork the repository
2. Create your feature branch (`git checkout -b feature/amazing-feature`)
3. Commit your changes
4. Open a Pull Request against `main`

Keep `PlanMonitor/Resources/en.lproj/Localizable.strings` and `es.lproj/Localizable.strings` in sync: every key present in both, no duplicates, matching format specifiers. Any string built purely from interpolation should use `Text(verbatim:)` so it never enters the catalogs.

## License

Apache License 2.0 — see [LICENSE](LICENSE).

## Acknowledgments

- Built with [SwiftUI](https://developer.apple.com/xcode/swiftui/)
- Inspired by the need to keep an eye on AI usage limits without leaving your workflow
