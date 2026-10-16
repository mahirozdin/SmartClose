# FAQ

## Does SmartClose force quit apps?
No. SmartClose always requests a normal quit. If the app has unsaved changes, macOS will prompt as usual.

## Why does SmartClose need Accessibility permission?
It uses Accessibility APIs to inspect windows and detect the close button reliably.

## Can I exclude apps?
Yes. Use the ignore list or per-app rules in Settings.

## Can SmartClose run without a menu bar icon or startup window?
Yes. Complete setup, enable **Launch at login**, and turn off **Show menu bar icon** in Settings. Subsequent login launches do not open a window. Monitoring continues in the background when SmartClose is enabled and both required permissions are granted.

Launch SmartClose from Applications, Spotlight, or Finder whenever you want to open Settings, including when it is already running. You can restore the menu bar icon there. Incomplete setup still opens the onboarding window, and necessary permission prompts and update dialogs are unaffected.

## Does it work with all apps?
Not always. Some apps expose windows in non-standard ways. SmartClose defaults to fail-safe behavior in ambiguous cases.
