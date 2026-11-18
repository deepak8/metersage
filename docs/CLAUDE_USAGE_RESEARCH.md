# Independent Claude subscription usage refresh

Researched and implemented 17 November 2026. The app now uses the official CLI usage-panel approach below; it does not extract credentials or introduce an independent subscription login.

## Finding

The existing bridge is an event-driven snapshot source. Rereading its file cannot establish current account usage when only Claude Desktop or the website is active. Claude's quota allowance is shared across those surfaces, but a monitor still needs a fresh account measurement. [Shared limits](https://support.claude.com/en/articles/11647753-how-do-usage-and-length-limits-work)

The best first prototype for this app is to run the user's unmodified, officially authenticated Claude Code CLI and request its built-in `/usage` panel. The user would not need to send a model prompt. This is a different adapter from the status-line bridge; it still requires Claude Code to be installed and signed in to the intended account.

## Options investigated

### 1. Official CLI command, automated terminal capture — recommended prototype

Anthropic documents `/usage` as showing subscription usage bars for Pro/Max/Ultra users. It also documents last-known fallback bars when the usage request fails, so a panel containing numbers is not necessarily a fresh response. [Official usage documentation](https://code.claude.com/docs/en/costs)

CodexBar's implementation starts Claude Code in a pseudo-terminal, opens `/usage`, waits for quota rendering, and parses the displayed panel. It also contains a direct CLI fallback. This is source-level feasibility evidence, not a supported JSON API. Our own terminal adapter was subsequently tested live with Claude Code 2.1.326. [CLI probe source](https://github.com/steipete/CodexBar/blob/main/Sources/CodexBarCore/Providers/Claude/ClaudeStatusProbe.swift), [Direct CLI fallback source](https://github.com/steipete/CodexBar/blob/main/Sources/CodexBarCore/Providers/Claude/ClaudeUsageFetcher.swift)

Our proposed adapter:

1. On connection, show the CLI's authenticated account so the user can confirm the intended subscription.
2. Use a dedicated probe directory and an owned terminal session; do not attach to the user's working terminal or desktop session.
3. Request only the built-in usage command. Keep tools, user hooks, Remote Control startup, and unrelated MCP servers inactive for this probe using process-local options supported by the installed CLI. Leave saved settings and authentication unchanged.
4. Parse the current terminal frame, including session, weekly, optional model-specific limits, and resets. Do not concatenate old redraws and mistake erased text or usage-attribution percentages for quota.
5. Detect loading, sign-in-required, rate-limit, and “last-known usage” notices. Preserve capture age on cached results; never turn a cached CLI panel into a fresh observation.
6. Use bounded output, cancellation, process cleanup, one in-flight check, and provider backoff. Begin with manual Refresh, then enable five-minute polling after successful local validation. Never automatically launch browser sign-in from a background poll.
7. Keep the existing bridge for local context/session-cost metrics. Store quota and context observation times separately rather than marking all fields current when only quota was refreshed.

The screen parser is an integration-maintenance cost: test the installed CLI version and keep fixtures for terminal redraws, partial output, rate limiting, and changed wording. Our live native probe returned 21% session usage and 16% weekly usage independently of the older bridge report (18% and 15%). This verifies independent polling, not a complete cross-device attribution or token breakdown.

### 2. Direct subscription OAuth endpoint

CodexBar calls `https://api.anthropic.com/api/oauth/usage` with an access token and handles session/weekly windows and reset times. Its documentation describes scope requirements and token expiry/refresh behavior. This can obtain quotas independently of chat activity, but it is an internal subscription endpoint rather than the documented Console analytics API. [OAuth implementation](https://github.com/steipete/CodexBar/blob/main/Sources/CodexBarCore/Providers/Claude/ClaudeOAuth/ClaudeOAuthUsageFetcher.swift), [Provider notes](https://github.com/steipete/CodexBar/blob/main/docs/claude.md)

Do not make token extraction our default. Anthropic's authentication guidance restricts third-party Claude.ai login and collection/intermediation of subscription credentials or session tokens, while distinguishing end-user sign-in through the unmodified Claude Code binary. Existing monitor implementations do not establish permission for a new product. [Authentication guidance](https://code.claude.com/docs/en/legal-and-compliance)

### 3. Desktop or browser session and web usage endpoint

CodexBar can use a signed-in session to request `https://claude.ai/api/organizations/{orgId}/usage`. Its optional macOS desktop source imports Claude.app's encrypted cookies using its Safe Storage entry. This aligns with a desktop-selected account but introduces credential access, account-matching, expiry, and challenge handling. [Web implementation](https://github.com/steipete/CodexBar/blob/main/Sources/CodexBarCore/Providers/Claude/ClaudeWeb/ClaudeWebAPIFetcher.swift)

This is a technical alternative, not evidence of a public integration contract. It also needs the authentication restrictions above resolved for a distributable product. No desktop cookies, Safe Storage secrets, or OAuth tokens were read in this research.

### 4. Official Admin/analytics APIs

The published Usage/Cost and Rate Limits APIs address Console organizations and eligible enterprise analytics. They do not provide a drop-in personal Pro subscription allowance integration. The rate-limit API describes configured Messages API limits, not a personal Claude account's remaining five-hour subscription window. [Usage API](https://platform.claude.com/docs/en/manage-claude/usage-cost-api), [Rate Limits API](https://platform.claude.com/docs/en/manage-claude/rate-limits-api)

## What does not solve independent refresh

Claude Code's `statusLine.refreshInterval` can rerun a script while a terminal session is idle. That is useful for display updates, but rerunning our bridge does not establish that Claude Code fetched new account limits. It is not a substitute for a verified quota request. [Status-line behavior](https://code.claude.com/docs/en/statusline)

Local transcript/token scanning can improve usage history, including supported desktop Code session logs, but token counts alone cannot reconstruct the remaining subscription allowance.

## Implemented validation

The native probe and refresh coordinator are implemented. Twenty-six tests pass, including terminal cursor redraws, model-specific windows, attribution-percentage exclusion, cached response ages, quota/metrics timestamp separation, isolated CLI flags, timeout/cancellation, and existing provider regressions. A live native probe retrieved account quotas without a model message. The app retains the optional bridge only for context/session metrics. A separate comparison with the browser’s Settings → Usage screen remains a useful cross-surface acceptance check; it was not performed during this implementation.
