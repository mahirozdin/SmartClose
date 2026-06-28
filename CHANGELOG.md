# Changelog

## 0.3.3
- Fix: Cmd+W handling could pass through on macOS 26 when the just-closed last window was still reported briefly by the accessibility/window APIs (#8). SmartClose now retries the post-Cmd+W verification for a short bounded window and records the before/after samples in diagnostics.

## 0.3.2
- Fix: closing an app's auxiliary window quit the whole app (#6). Clicking the red close button on a non-standard window — e.g. CotEditor's Find & Replace panel, a dialog, or a floating inspector — was treated as closing the last window and quit the app, even with the main window still open. SmartClose now only quits when the window you close is itself a standard window.

## 0.3.1
- Fix: optional Cmd+W handling never quit any app (#3). When an app's last window closed, the window count came back 0 but flagged "ambiguous", which suppressed the quit. SmartClose now counts windows just before Cmd+W and, when there was exactly one normal window that is then gone, requests the quit reliably.

## 0.3.0
- Add automatic updates via [Sparkle](https://sparkle-project.org). SmartClose now checks for new releases and can download/install them in the background; a "Check for Updates…" menu item and an "Automatically check for updates" setting are included. (Existing 0.2.0 users update to 0.3.0 manually once; updates are automatic from 0.3.0 onward.)

## 0.2.0
- Add optional, experimental Cmd+W handling (off by default). SmartClose lets the app handle Cmd+W normally first, then requests a normal quit only if that closed the app's last normal window. Honors ignore/allow lists and per-app rules. (#1)
- Fix: closing SmartClose's own window no longer quits the app — SmartClose now hard-excludes itself.
- Add an app icon.
- Add a Contributors section to the README (all-contributors).

## 0.1.0
- Initial SmartClose release.
