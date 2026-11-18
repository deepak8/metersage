---
name: MeterSage
description: Quiet Utility Minimalism for a native macOS allowance monitor
colors:
  canvas-light: "#F3F5F8"
  canvas-dark: "#151A21"
  surface-light: "#FFFFFF"
  surface-dark: "#1E2530"
  raised-light: "#E8EDF3"
  raised-dark: "#2A3442"
  ink-light: "#202D3C"
  ink-dark: "#E8EEF6"
  secondary-light: "#596879"
  secondary-dark: "#A9B7C9"
  accent-light: "#426D98"
  accent-dark: "#99BBDD"
  buttonFill-light: "#426D98"
  buttonFill-dark: "#426D98"
  meter-light: "#587FA7"
  meter-dark: "#89AACE"
  track-light: "#E4EAF1"
  track-dark: "#354253"
  line-light: "#DCE3EC"
  line-dark: "#354152"
  warning-light: "#945608"
  warning-dark: "#E9BB70"
  failure-light: "#AA3A40"
  failure-dark: "#F0A1A5"
typography:
  title:
    fontFamily: "SF Pro, system-ui, sans-serif"
    fontSize: "20px"
    fontWeight: 600
  sheet-title:
    fontFamily: "SF Pro, system-ui, sans-serif"
    fontSize: "18px"
    fontWeight: 600
  provider:
    fontFamily: "SF Pro, system-ui, sans-serif"
    fontSize: "16px"
    fontWeight: 600
  section:
    fontFamily: "SF Pro, system-ui, sans-serif"
    fontSize: "14px"
    fontWeight: 600
  body:
    fontFamily: "SF Pro, system-ui, sans-serif"
    fontSize: "13px"
    fontWeight: 400
  data-label:
    fontFamily: "SF Pro, system-ui, sans-serif"
    fontSize: "13px"
    fontWeight: 500
  data-value:
    fontFamily: "SF Pro, system-ui, sans-serif"
    fontSize: "13px"
    fontWeight: 600
  supporting:
    fontFamily: "SF Pro, system-ui, sans-serif"
    fontSize: "12px"
    fontWeight: 400
  code:
    fontFamily: "SF Mono, monospace"
    fontSize: "11px"
    fontWeight: 400
rounded:
  surface: "12px"
spacing:
  step-4: "4px"
  step-8: "8px"
  step-12: "12px"
  step-16: "16px"
  step-20: "20px"
  step-24: "24px"
components:
  card-light:
    backgroundColor: "{colors.surface-light}"
    textColor: "{colors.ink-light}"
    rounded: "{rounded.surface}"
    padding: "{spacing.step-16}"
  card-dark:
    backgroundColor: "{colors.surface-dark}"
    textColor: "{colors.ink-dark}"
    rounded: "{rounded.surface}"
    padding: "{spacing.step-16}"
  button-primary:
    backgroundColor: "{colors.buttonFill-light}"
    textColor: "white"
  dashboard:
    width: "440px"
  sheet:
    width: "430px"
  allowance-meter:
    height: "6px"
---

# Design System: MeterSage

## Overview

**Creative North Star: "Quiet Utility Minimalism"**

Quiet Utility Minimalism gives a persistent macOS utility the calm precision of native Settings. Cool solid surfaces, charcoal and soft navy text, muted blue allowance meters, and restrained system typography make comparisons easy without turning usage into a hero statistic.

Native controls and familiar sheet behavior preserve the existing workflows. Both appearances use explicit semantic colors; official provider icons identify services and remain unchanged. The approved workflow is code-first native preview with preset configuration, rather than generated replacements for the interface or assets.

**Key Characteristics:**
- Solid cool neutrals in light and dark appearances.
- Native controls, compact aligned information, and quiet feedback.
- Blue allowance, amber warnings, and red provider failures.

## Colors

### Primary
Muted blue `accent` serves native actions; `meter` marks healthy allowance. `buttonFill` keeps white primary-button labels legible in either appearance. These are semantic roles, not provider brand colors.

### Neutral
`canvas` is the cool application background; `surface` is the solid card or sheet surface; `raised` separates quieter inset regions. `ink` carries primary text, `secondary` supports timestamps and context, `track` anchors meters, and `line` defines subtle boundaries. Each light/dark pair in the frontmatter maps directly to `UtilityTheme.swift`.

Amber `warning` identifies low allowance or stale attention states; red `failure` identifies provider errors. Always accompany status color with text or a symbol. Provider identity colors may still distinguish history series; they do not redefine allowance semantics.

**The Semantic Color Rule.** Healthy allowance is blue, attention is amber, and provider failure is red; a color never replaces the status label.

## Typography

SwiftUI system fonts resolve to the macOS system face. Frontmatter CSS family names are portable descriptions of those native fonts, and pixel units represent source point measurements at 1×. The implementation remains authoritative for native sizing.

The dashboard title uses `title`; sheet headings use `sheet-title`; provider names use `provider`; compact chart headings use `section`. Native `.body` is the baseline for quota labels and values, with medium labels and semibold monospaced digits. `.callout` supports account details and resets. Explicit supporting labels use `supporting`. The Claude bridge configuration uses the smaller monospaced `code` role. Native semantic styles retain platform line metrics; no artificial line-height or tracking scale is imposed.

## Layout

Use the 4-point grid and compact, deliberate grouping. Card interiors use the shared padding token. The persistent dashboard has a fixed width from `dashboard`; its height is capped by the available screen and its body scrolls. Refresh and Settings remain accessible in the header. The manual-refresh status area reserves 28pt even when empty.

Secondary sheets use the fixed `sheet` width. Connection sheets keep their action footer outside the scrolling body, so long instructions do not hide Sign in or Check connection. Settings use native grouped controls; history preserves native list behavior. These are macOS windows, with screen-height constraints rather than invented web breakpoints.

## Elevation & Depth

Use solid tonal layering without card shadows. Surface contrast and a subtle half-point outline at 55% line-color opacity provide definition. Keep native control elevation and system focus treatment; do not add decorative materials or shadows.

## Shapes

Soft rectangular surfaces use the shared surface radius. Allowance tracks and fills are capsules. Buttons, toggles, pickers, and fields retain native macOS geometry rather than inheriting the card radius.

## Components

### Buttons and fields
Native bordered, prominent, plain, and link buttons retain system interaction and keyboard behavior. Prominent connection actions use the shared button fill with white text. Native fields and settings controls retain system focus, disabled, and selection states. Do not fabricate a custom hover or focus language.

### Provider cards
Use the shared solid surface, outline, radius, and padding. Align the unchanged official provider mark with account identity and quiet freshness. Right-align primary values. Keep details disclosed on demand; do not nest decorative cards inside cards.

### Allowance rows
Always present 5-hour before weekly. Keep labels and monospaced values aligned, then the capsule meter and reset context. Missing values say Unavailable; stale values say last reported and use a quieter fill. Low allowance has an amber label and symbol. Preserve source group names and disclosure content.

### Refresh feedback
Keep Refresh in place while loading and show a small adjacent activity indicator. Manual feedback uses the reserved status line and a brief ease-out opacity transition (0.16 seconds); Reduce Motion disables that animation. Automatic polling remains quiet. Unresolved errors stay inline and actionable.

### Preview and asset authority
`UtilityTheme.swift` and the native SwiftUI views are the implementation source. Use the app's snapshot command and code-first preset configuration to inspect appearances and surfaces. Sidecar HTML is a portable visual approximation for documentation only. Existing provider icon resources are unchanged official assets, not generated artwork.

## Do's and Don'ts

### Do:
- Do use shared adaptive colors and the 4-point spacing grid.
- Do keep the 5-hour then weekly rows in a stable order, including unavailable states.
- Do pair warning and failure colors with text or symbols.
- Do preserve native controls, keyboard behavior, and unchanged official provider icons.
- Do validate changes through native light and dark snapshots and the existing workflows.

### Don't:
- Don't add heavy glass, gradients, neon, excessive shadows, or decorative graphics.
- Don't infer token quotas or billing from allowance percentages.
- Don't use green as the healthy allowance series or saturate cards with provider branding.
- Don't replace native workflows with new navigation or authentication flows.
- Don't treat illustrative HTML sidecar previews as native implementation specifications.

## Menu bar: stacked limits

Approved option B replaces the single-line allowance title. Each 72pt native button draws a 16pt provider icon and two rows within the 22pt menu bar: weekly above 5-hour. Labels use 8.5pt system type, values 9.5pt medium monospaced digits. These sizes are specific to the constrained native status strip; dashboard/supporting copy remains at the documented larger sizes. Each low value warns independently; missing values are dashes and cached Claude readings retain an asterisk. A small logo badge indicates connection or stale-data attention. Hover and accessibility labels describe both windows; native button actions are unchanged.
