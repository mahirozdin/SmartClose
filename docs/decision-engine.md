# Decision Engine

## What counts as a normal window
A window is considered "normal" when:
- Its role is `AXWindow`.
- Its subrole is `AXStandardWindow`.
- It is not a sheet, popover, system dialog, or floating panel.
- It is not minimized (unless the user chooses to count minimized windows).
- It is not hidden (unless the user chooses to count hidden windows).
- Tabs are not counted unless the platform exposes them as separate windows.

## What is intentionally ignored
SmartClose ignores:
- Sheets and dialogs (`AXSheet`, `AXDialog`, `AXSystemDialog`).
- Popovers (`AXPopover`).
- Floating panels (`AXFloatingWindow`).
- Hidden windows when "Ignore hidden windows" is enabled.
- Minimized windows when "Ignore minimized windows" is enabled.

## Ambiguity handling
If SmartClose cannot determine the role, subrole, or visibility/minimized state of a window, it treats the classification as ambiguous. In ambiguous cases, SmartClose does **not** convert close to quit.

## Why fail-safe matters
Accessibility metadata varies by app. A conservative default prevents incorrect quits in apps that expose unusual window structures.

## App rule resolution
Rules are matched against the bundle identifier of the process that owns the clicked window.
If that app is nested inside another app bundle whose `Info.plist` marks it faceless
(`LSUIElement` or `LSBackgroundOnly`), the host's identifier is also considered. Docker Desktop
is an example: its windows belong to `com.electron.dockerdesktop` inside `com.docker.docker`.
- Hard exclusions, the allow list, and the ignore list match either identifier. An exclusion can
  only make SmartClose fall back to the system's normal close.
- Per-app rules prefer the window owner's own rule (exact, then the longest wildcard) and fall
  back to the host's rule.
- Regular apps that bundle other apps (for example Xcode and Simulator) are not hosts, so their
  rules do not apply to the bundled apps.
The host lookup runs only after a close button is detected. It reads `Info.plist` once per app
and caches the result.
