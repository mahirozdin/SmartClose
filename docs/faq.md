# FAQ

## Does SmartClose force quit apps?
No. SmartClose always requests a normal quit. If the app has unsaved changes, macOS will prompt as usual.

## Why does SmartClose need Accessibility permission?
It uses Accessibility APIs to inspect windows and detect the close button reliably.

## Can I exclude apps?
Yes. Use the ignore list or per-app rules in Settings.

Rules match the bundle identifier of the app that owns the window. The Diagnostics view shows that identifier for every decision. Some apps run their windows in a separate UI app nested inside a faceless host app. Docker Desktop is one example: `com.electron.dockerdesktop` runs inside `com.docker.docker`. SmartClose applies rules for such a host app to the nested app as well, so either identifier works. If both identifiers have per-app rules, the nested app's own rule wins.

## Can SmartClose run without a menu bar icon or startup window?
Yes. Complete setup, enable **Launch at login**, and turn off **Show menu bar icon** in Settings. Subsequent login launches do not open a window. Monitoring continues in the background when SmartClose is enabled and both required permissions are granted.

Launch SmartClose from Applications, Spotlight, or Finder whenever you want to open Settings, including when it is already running. You can restore the menu bar icon there. Incomplete setup still opens the onboarding window, and necessary permission prompts and update dialogs are unaffected.

## Does it work with all apps?
Not always. Some apps expose windows in non-standard ways. SmartClose defaults to fail-safe behavior in ambiguous cases.

## Adobe Illustrator or InDesign stays open after I close the last document. Why?
Adobe apps keep an empty window (the Application Frame) open after the last document closes, and macOS reports it as a normal window. To SmartClose this looks like an app with one window left, so it does not quit. InDesign's windows can also be reported in a way SmartClose treats as ambiguous.

Add a per-app rule for the app (for example `com.adobe.illustrator` or `com.adobe.InDesign`, or `com.adobe.*`) with the policy **Quit when last document closes**. SmartClose then asks the app how many documents are open after you close a window, and quits it only when none remain. macOS asks once for Automation permission. For `Cmd+W`, also enable **Handle Cmd+W (experimental)**.
