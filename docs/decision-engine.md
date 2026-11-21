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

## Quit when last document closes
Some apps keep a standard window open with no document in it, so window counts cannot decide.
Adobe Illustrator's empty Application Frame stays an `AXStandardWindow` after the last document
closes (#29), and InDesign's windows can classify as ambiguous (#30). Apps with the per-app policy
**Quit when last document closes** skip window counting:
- Red close button: the click always goes through. If the closed window is a standard window,
  SmartClose asks the app for its document count (`core/cnte`, `kocl = docu`, the event sent by
  `count documents`) on a background queue, starting after 0.3 s and retrying every 0.3 s for up
  to 3 s. Closing an auxiliary window (panel, dialog) never starts a check.
- `Cmd+W` (when Cmd+W handling is enabled for the app): the same check starts after the keystroke.
- A count of zero requests a normal quit. A positive count, a timeout, denied Automation
  permission, or an app that does not support documents passes through. A newer close in the
  same app replaces a running check, and pausing or disabling SmartClose stops it.
- If the app's hit-test does not land on its close button, SmartClose checks whether the click is
  inside the Accessibility frame of the window's own `AXCloseButton`. This happens only for apps
  using this policy.

## Diagnostics details
For the red close button, Diagnostics lists the window classification reasons (for example
`Unknown subrole: …` or `Auxiliary window present alongside last standard window`) when windows
were ignored or the classification was ambiguous. Document checks list every document count
sample and the elapsed time.
