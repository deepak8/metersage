# MeterSage

Your AI allowances, at a glance.

A native macOS menu bar utility for Codex, Claude Code, and Google Antigravity. Built with SwiftUI and Swift Charts. The approved visual direction is Quiet Utility Minimalism: solid cool surfaces, muted blue allowance meters, native controls, and explicit light/dark tokens. See [DESIGN.md](DESIGN.md) for the canonical design system. Provider icons are read from locally installed applications; original letter marks are used when those apps are absent.

## Build and open

Requires macOS 14+ and Xcode with the Swift 6.2 toolchain. No third-party Swift packages are required.

```sh
git clone https://github.com/deepak8/metersage.git
cd metersage
```

Build locally:

```sh
./scripts/build-app.sh
open "artifacts/MeterSage.app"
```

Launching or reopening the app brings up a persistent dashboard window, so it remains accessible even if the menu bar strip is hidden behind a laptop notch. Closing that window leaves the app running in the menu bar; it does not appear in the Dock. The strip shows each provider’s icon followed by two stacked allowance rows (`W 87%` above `5h 98%`), then Refresh. For providers with multiple model groups, each window shows its lowest remaining allowance; the tooltip identifies the limiting group. Click a provider to reopen the same dashboard and scroll to that provider. The app uses a persistent window instead of a transient menu popover so connection checks, refreshes, and external sign-in do not dismiss it. The first launch has no connected accounts. To review the dashboard with sample data, enable **Settings → Demo mode**, or launch a separate instance:

```sh
open -n "artifacts/MeterSage.app" --args --demo
```

Move the app to its final location before configuring the Claude bridge, since the bridge references the executable's absolute path. Open `Package.swift` in Xcode to work on the source.

## Implemented in this first build

- Adaptive light/dark persistent dashboard, provider cards, quota bars, reset countdowns, low-allowance badges, seven-day stacked chart, and history sheet.
- Compact provider overview with fixed 5-hour then weekly rows and a tightest-allowance indicator. Antigravity summarizes each window’s lowest active model-group allowance, names its source group, and exposes all original quota groups through an expandable section. Session metrics and source details expand separately.
- One grouped menu bar strip with Codex, Claude, and Antigravity app icons plus weekly (`W`) and 5-hour (`5h`) remaining percentages in fixed-width stacked columns and a refresh button. Missing or expired quotas show `—`; stale Codex/Antigravity readings also show `—`. Claude’s last known active-window percentage stays visible with `*` and muted text when stale or explicitly cached by the official client; a small amber badge on the provider icon indicates attention is needed. Hover shows the observation age and explains that it is cached. Cached readings do not trigger alerts. Menu bar values react to fresh readings; demo mode has a visible DEMO label.
- A clearly labeled demo mode with illustrative accounts and amounts. Demo actions cannot initiate provider connections or send low-allowance notifications.
- Connect/Reconnect/Disconnect controls in the dashboard, with guided official CLI sign-in opened in Terminal. Disconnect stops this app's monitoring; it does not log the official CLI out.
- Codex adapter for authenticated official App Server account/quota endpoints and optional daily token reporting. Only reads usage after the user explicitly connects. Requires the `codex` CLI in a supported executable search path.
- Claude account allowance adapter. Refresh and automatic polling request the authenticated official Claude Code `/usage` panel through an isolated pseudo-terminal, without sending a model prompt. Usage on Desktop/web is reflected when it shares the same subscription account. Requires a signed-in, initialized Claude Code CLI; locally validated with 2.1.326.
- Optional Claude status-line bridge for current context tokens and session cost. Setup provides JSON to manually merge into settings. The app checks sanitized snapshots every 30 seconds, preserving a separate metrics observation time; these snapshots never overwrite the independently fetched account allowance.
- Antigravity adapter using the official `agy -p /usage --output-format json` report. Keeps separate named Gemini, Claude/GPT, and any additional model quota groups, including reset times. Manual refresh and the configured polling interval fetch new reports. Requires `agy` 1.1.11+ and its official sign-in; no status-line bridge is needed.
- Refresh interval, appearance, configurable warnings, macOS notification permission, launch at login, and deletion of local bridge data.
- Missing/stale readings stay distinct from zero usage. The dashboard reports availability across every enabled provider, including errors before the first reading, with a connection action when attention is needed. Alerts use fresh readings and deduplicate thresholds by quota window across launches.
- Daily history distinguishes unsupported CLI reporting, empty reports, unavailable fields, and failed requests, using a compact availability note instead of a chart placeholder. Claude cost is labeled as a CLI session estimate rather than subscription spending.

## Coverage and unfinished work

- Antigravity's CLI report supplies quota groups, not daily token totals, estimated spending, or verified account identity. These fields remain unavailable rather than treating the report command's zero token consumption as zero account usage. Direct Claude/Codex subscription quotas are separate from Antigravity's Claude/GPT group.
- Codex's adapter has been observed returning live Plus account quota windows. Optional daily metrics may be absent for today or on older CLI versions.
- Claude's bridge reports the latest observed session. Its token counts describe the current context, while its estimated cost describes that session. These values are **not daily usage or billed subscription charges**. This build does not reconstruct complete desktop or account token activity.
- Daily history currently comes from supported provider responses; there is no persistent SQLite history store yet. Claude snapshots are saved locally, but are excluded from daily charts because context counts cannot establish consumption.
- Launch at login and notifications depend on macOS permissions and installation. The local build uses ad-hoc signing. The source is MIT-licensed. Release signing/notarization, clean-install testing, and an update strategy remain outstanding.
- Provider icons load at runtime from official apps installed in `/Applications` or `~/Applications`. MeterSage does not redistribute their icon files. Without those apps, it draws distinct original letter marks. Provider names and trademarks remain with their respective owners; this project is independent and unofficial.

## Local data

Preferences and connected-provider flags use the app's UserDefaults domain. Sanitized Claude snapshots are under `~/Library/Application Support/UsageMonitor/claude/`, with user-only directory/file permissions. Provider credentials stay in the official CLIs. The app does not read prompt text or credential files, and does not add its own backend or telemetry service. Account/quota requests still communicate with the provider through its official CLI.

MeterSage retains the internal bundle identifier `dev.usagemonitor.mac` and the existing local data folder for compatibility with earlier builds. The build script also keeps a local `artifacts/Usage Monitor.app` alias and the former executable name, so existing Claude bridge commands continue working. New installations should use `MeterSage.app` and the bridge command shown in its connection setup.

Deleting bridge snapshots does not remove the manually configured bridge. Remove only the MeterSage command from `statusLine` in `~/.claude/settings.json` to stop future snapshots; preserve any other commands you chained there.

## Validation

```sh
swift test
swift build
```

Thirty-six tests cover terminal redraws, independent Claude quota/session timestamps, cached-panel ages, isolated CLI usage probing, and quota grouping, missing/disabled/expired readings, idle Claude cache visibility, report/version validation, zero allowance, numeric metrics, subprocess timeout/cancellation/output limits, sanitization, Codex protocol fixtures, and native menu bar routing. A real Antigravity CLI 1.5.10 read-only report was validated on this machine, returning five measured windows across Gemini Models, Claude/GPT, and Gemini 4 Argon. Generate native preview images without connecting accounts:

```sh
.build/debug/MeterSage --snapshot "$PWD/artifacts/dashboard-light.png"
.build/debug/MeterSage --snapshot "$PWD/artifacts/dashboard-dark.png" --dark
```

For a Claude account-only diagnostic (requires official Claude Code sign-in):

```sh
.build/debug/MeterSage --probe-claude
```

This prints normalized quotas only. The probe disables tools, hooks, MCP servers, Remote Control startup, and the normal status-line command in its own process. It uses a private temporary workspace, bounds output and runtime, and cleans up its owned process group. CLI startup may register this probe workspace in its own local state. The terminal parser depends on CLI presentation; unexpected layouts produce an error while retaining prior readings. Explicitly cached CLI responses retain their age and suppress alerts; rate limiting or cached results defer further Claude checks for 15 minutes. The bridge is optional and does not need reconfiguration for account allowance updates.

For an Antigravity-only diagnostic (requires the official CLI's sign-in):

```sh
.build/debug/MeterSage --probe-antigravity
```

This prints parsed quota metrics only. It does not enable monitoring in the app. Use **Antigravity → Sign in → Check connection** to connect; an existing CLI sign-in can be used directly without signing in again. Background refreshes suppress browser login launchers and show a reconnect error if authentication cannot complete.

Provider integration notes are in [docs/CLAUDE_USAGE_RESEARCH.md](docs/CLAUDE_USAGE_RESEARCH.md) and [docs/ANTIGRAVITY_RESEARCH.md](docs/ANTIGRAVITY_RESEARCH.md).

## First connection

1. Build and open MeterSage using the commands above.
2. Click **Sign in** on a provider card. Install its official CLI if needed, then complete the official sign-in in Terminal.
3. Click **Check connection**. A CLI already signed in to the intended account can be used directly.
4. Claude’s optional status-line bridge adds session metrics; it is not required for account allowances.

This repository currently provides source builds, not a notarized installer. The local build script uses ad-hoc signing. Keep the app at its final path before configuring the optional Claude bridge.

## License

MeterSage’s original source code is available under the [MIT License](LICENSE). See [THIRD_PARTY_NOTICES.md](THIRD_PARTY_NOTICES.md) for provider names and artwork handling.
