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
