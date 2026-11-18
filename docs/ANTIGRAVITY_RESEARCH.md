# Antigravity usage integration research

Researched 17 November 2026. Follow-up: the primary CLI adapter is implemented, and a live read-only report from official CLI 1.5.10 succeeded on this machine. It returned Gemini weekly/5-hour, Claude/GPT weekly/5-hour, and an additional Gemini 4 Argon weekly window. The CLI used its existing official sign-in. The status-line and desktop-only routes below remain optional future alternatives.

## Recommended source: the official CLI usage report

Run the official, signed-in `agy` CLI as a subprocess:

```sh
agy -p /usage --output-format json
```

Google's CLI v1.1.11 release notes introduced structured print-mode reports for `/usage`, `/quota`, and `/credits`. They execute without a model turn, quota consumption, or a saved conversation. Require a compatible version and verify the returned command/status/schema before accepting values. Keep slash-command expansion enabled; do not let a usage request fall through to model inference. [Official changelog](https://antigravity.google/docs/changelog)

The official headless guide distinguishes CLI-handled slash commands from streamed model turns. Use a separate print invocation, not a long-running conversation input stream. [Headless guide](https://antigravity.google/docs/cli/headless/)

This is our proposed primary source because the existing Refresh button can request a new report. Add a subprocess deadline, bounded output, cancellation/cleanup, and single-flight refreshes. Run from an empty temporary working directory so workspace-specific configuration cannot affect a monitoring request. Expired authentication should lead to an explicit reconnect state rather than repeatedly launching sign-in during background polling. Validate these behaviors against the installed CLI before shipping.

## What to display

Google's quota panel describes model groups with weekly and five-hour limits. Preserve the groups and bucket identifiers the account actually returns, including any extra model-specific buckets; do not hardcode every model as an independent allowance. [Official quota panel](https://antigravity.google/docs/cli/commands/usage?authuser=3)

Proposed dashboard rows, shown only when measured data exists:

| Group | Windows |
| --- | --- |
| Gemini | Five-hour and weekly |
| Claude / GPT | Five-hour and weekly |
| Other returned named group | Its reported windows |

Keep these allowances under Antigravity, separate from the direct Claude and Codex cards. Do not add the same shared quota once per model. Use the lowest remaining fresh active bucket for Antigravity's existing menu bar percentage, and identify that bucket in its tooltip.

The current model catalog lists Gemini, Claude, and GPT-OSS models. Calling all OpenAI entries “Codex” would be imprecise. Account access varies by Google plan, so discover available models rather than promising third-party model access from a plan name alone. [Model catalog](https://antigravity.google/docs/models), [Plans](https://antigravity.google/docs/plans/)

## Documented fallback: status-line bridge

The CLI supports a script in `statusLine` under `~/.gemini/antigravity-cli/settings.json`, receiving JSON on stdin. Its documented payload includes a `quota` map keyed by bucket ID, fractions or amounts remaining, reset timestamps, model details, optional plan/account fields, context metrics, and optional estimated cost. `stack_with_default` allows retaining the built-in status line. [Official status-line reference](https://antigravity.google/docs/cli/statusline/)

We could add `UsageMonitor --antigravity-statusline`, sanitize incoming fields, and save a local snapshot using the existing Claude bridge pattern. Updates would depend on CLI activity; refreshing our app would reread the snapshot rather than force a backend fetch.

Keep absent fractions unavailable. An amount remaining does not establish a percentage without a known total. Preserve explicit zero. Context tokens are not daily consumption, and a cost estimate is not a billed subscription charge.

## Desktop-only alternative

CodexBar implements probes for Antigravity's local internal services, preferring `RetrieveUserQuotaSummary`, with legacy `GetUserStatus` fallbacks. Its documentation records significant differences between the standalone app, CLI, and IDE, plus newer CLI CSRF restrictions. This demonstrates another technical route, but it is not evidence of a stable public monitoring API. [Implementation documentation](https://github.com/steipete/CodexBar/blob/main/docs/antigravity.md)

For our distributable app, prefer documented CLI reports. Consider an optional desktop-only adapter later if users need monitoring without the standalone CLI. Validate it independently against the installed version and account; never treat model availability as a measured full quota.

## Original local findings and implementation follow-up

- Installed: `/Applications/Antigravity IDE.app`, version 2.7.0; its bundled extension includes quota-service schema names. This confirms bundled interfaces, not a successful live quota response.
- No standalone `agy` command was found on the current PATH or in the checked common executable locations.
- No credentials were read, no authenticated endpoints were probed, and no login or CLI settings were changed during this research.
- Next: install/discover the official CLI, complete its own sign-in, and capture one sanitized real `/usage` JSON report. Confirm identity/scope and compare every returned group with the official quota panel.
- Implement a parser using that verified schema, with fixtures for shared groups, partial windows, disabled buckets, zero allowance, expiry, schema errors, and missing values. Add the adapter to the existing connection and refresh flow.
- Token history and spending remain separate work: establish their actual source and scope before showing daily totals or billed costs.

Implementation follow-up: installed the official CLI with Google's installer into `~/.local/bin/agy`; the installer also added that directory to shell profiles. Added a strict report parser, version gating, bounded/cancellable subprocess execution, passive browser-launch guards, per-provider refresh handling, group/reset display, and a connection flow. Sixteen tests pass, including invalid/partial/disabled reports and subprocess limits. The earlier missing-CLI and not-yet-live-tested notes above describe the research stage rather than the current installation.
