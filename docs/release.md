# Release Guide

SmartClose is designed to ship outside the Mac App Store as a signed, notarized menu bar app distributed through GitHub Releases.

## Prerequisites
- Apple Developer Program membership.
- A `Developer ID Application` certificate installed locally or injected in CI.
- A valid notarization profile created with `xcrun notarytool store-credentials`.
- Xcode 26.2 or later.

## One-time Apple account setup
1. Accept the latest Apple Developer Program License Agreement if Apple shows a `PLA Update available` error during export.
2. In Xcode, open `Settings > Accounts > Manage Certificates`.
3. Create or download a `Developer ID Application` certificate for the SmartClose release team `WWRZ5CG3DW`.
4. Confirm it appears in Keychain:

```bash
security find-identity -v -p codesigning | grep "Developer ID Application"
```

Without that certificate, `xcodebuild -exportArchive` cannot produce a public Developer ID build.

The expected identity is:

```text
Developer ID Application: APPILLON BILGI TEKNOLOJILERI ARGE LIMITED SIRKETI (WWRZ5CG3DW)
```

## Local release
Create the notary profile once:

```bash
xcrun notarytool store-credentials smartclose-notary \
  --apple-id "<apple-id>" \
  --team-id "<team-id>"
```

Then build the full release bundle:

```bash
./scripts/release_local.sh
```

The script performs these steps:
1. Archives the app for `Release`.
2. Exports it with `Developer ID` signing.
3. Verifies the exported signature.
4. Notarizes and staples `SmartClose.app`.
5. Builds `SmartClose-<version>.zip`.
6. Builds `SmartClose-<version>.dmg`.
7. Notarizes and staples the DMG.
8. Writes SHA-256 checksums into `dist/`.

### Environment overrides
- `SMARTCLOSE_TEAM_ID`
- `SMARTCLOSE_NOTARY_PROFILE`
- `PROJECT_PATH`
- `SCHEME`
- `CONFIGURATION`

## GitHub Actions release
The repository includes `.github/workflows/release.yml`.

Required GitHub secrets:
- `APPLE_TEAM_ID`
- `DEVELOPER_ID_APPLICATION_P12_BASE64`
- `DEVELOPER_ID_APPLICATION_P12_PASSWORD`
- `NOTARYTOOL_APPLE_ID`
- `NOTARYTOOL_APP_PASSWORD`

`APPLE_TEAM_ID` must be `WWRZ5CG3DW`. The `.p12` payload must contain the SmartClose `Developer ID Application` identity for that same team, not another Apple team certificate.

To create the certificate secret payload from a local `.p12`:

```bash
base64 -i SmartClose-DeveloperID.p12 | pbcopy
```

The workflow:
1. Imports the Developer ID certificate into a temporary keychain.
2. Stores notarytool credentials for the job.
3. Runs `./scripts/release_local.sh`.
4. Uploads artifacts.
5. Publishes a GitHub Release when the workflow runs from a `v*` tag.

## Artifact layout
Release artifacts are written to `dist/<version>/`:
- `SmartClose-<version>.zip`
- `SmartClose-<version>.dmg`
- `SmartClose-<version>-SHA256.txt`

## Manual QA checklist
- Single-window app closes -> app quits.
- Multi-window app closes -> only target window closes.
- Ignore list app remains unaffected.
- Missing Accessibility permission -> no risky action.
- Hidden/minimized window policy scenarios.
- Unsaved document app behavior.
- Finder excluded.
- Chrome with multiple windows.
- VS Code with multiple windows.
- Terminal excluded by default.
- Settings import/export works.
- Pause mode works.
- Launch at login works.
