# SmartClose

SmartClose is a macOS menu bar utility that makes the red close button behave more like Windows: when you close the last normal window of an app, SmartClose politely quits the app. If the app has multiple windows, SmartClose only closes the one you clicked.

## Why macOS behaves differently
On macOS, clicking the red close button usually closes a window but keeps the app running. This is native, but it can feel inconsistent if you expect apps to quit when the last window closes.

## What SmartClose changes
- If the app has **more than one normal window**, SmartClose lets the close behave normally.
- If the app has **exactly one normal window**, SmartClose requests a normal quit (no force quit).
- If anything is ambiguous or inaccessible, SmartClose does **nothing**.

## Safety philosophy
SmartClose is conservative by default. It only acts when it can reliably inspect windows via Accessibility APIs. If permissions are missing or the app cannot be inspected, SmartClose simply passes the close through.
The app starts disabled until both Accessibility and Input Monitoring are granted.

## Release status
- Public distribution target: GitHub Releases.
- Primary install artifact: notarized `.dmg`.
- Secondary install artifact: notarized `.zip`.
- Minimum supported macOS version: 13.0.

## Configuration
- Ignore list and allow list (bundle ID patterns supported with `*`).
- Per-app policies: default, always normal close, always quit on last window, disabled.
- Toggles for minimized and hidden windows.

## Install
### Option 1: GitHub Releases
1. Download the latest `SmartClose.dmg` from GitHub Releases.
2. Open the disk image and drag `SmartClose.app` into `Applications`.
3. Launch SmartClose from `Applications`.
4. Grant Accessibility and Input Monitoring during onboarding.

If you prefer a direct app bundle, the release also includes a ZIP with the same notarized app.

### Option 2: Build from source
1. Open `SmartClose.xcodeproj` in Xcode.
2. Select the **SmartClose** scheme.
3. Build and run.

## Permissions
SmartClose uses macOS Accessibility APIs to detect the close button and count windows, plus Input Monitoring to receive the global close-button click. It does not use pixel color detection or coordinate heuristics.

See `docs/permissions.md` for full details.

## Releasing
Local and CI release instructions live in `docs/release.md`.

The repository includes:
- `scripts/release_local.sh` for signed, notarized local builds.
- `scripts/create_dmg.sh` for DMG packaging.
- `.github/workflows/release.yml` for tagged GitHub releases.

## Known limitations
- Accessibility and Input Monitoring permissions are required.
- Some apps expose windows in non-standard ways.
- Electron or custom windowing toolkits may behave differently.
- The utility cannot guarantee identical behavior across all macOS apps.
- The Mac App Store is not an ideal distribution channel for apps requiring Accessibility access.

## FAQ
See `docs/faq.md`.

## Contributing
See `CONTRIBUTING.md`.

## Privacy
All logic runs locally. SmartClose does **not** send telemetry by default.
