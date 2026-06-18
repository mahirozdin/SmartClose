# Changelog

## 0.2.0
- Add optional, experimental Cmd+W handling (off by default). SmartClose lets the app handle Cmd+W normally first, then requests a normal quit only if that closed the app's last normal window. Honors ignore/allow lists and per-app rules. (#1)
- Fix: closing SmartClose's own window no longer quits the app — SmartClose now hard-excludes itself.
- Add an app icon.
- Add a Contributors section to the README (all-contributors).

## 0.1.0
- Initial SmartClose release.
