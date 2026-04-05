# FAQ

## Does SmartClose force quit apps?
No. SmartClose always requests a normal quit. If the app has unsaved changes, macOS will prompt as usual.

## Why does SmartClose need Accessibility permission?
It uses Accessibility APIs to inspect windows and detect the close button reliably.

## Can I exclude apps?
Yes. Use the ignore list or per-app rules in Settings.

## Does it work with all apps?
Not always. Some apps expose windows in non-standard ways. SmartClose defaults to fail-safe behavior in ambiguous cases.
