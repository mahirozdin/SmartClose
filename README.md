# SmartClose - Ultimate MacOS App Closing Solution.

<!-- Drop a short screen recording named example.gif in the repo root; it will render here automatically. -->
![SmartClose in action](example.gif)

[![All Contributors](https://img.shields.io/badge/all_contributors-2-orange.svg?style=flat-square)](#contributors)

I created SmartClose because, recently, There are many new macos users arround and My self also switching between Windows and macOs too often, and I find it really annoying that when I click the red close button on the last window of an app, the app doesn't quit. So I made SmartClose to fix this issue.

** Basic idea: If you click the red close button on the last normal window of an app, SmartClose politely quits the app. If there are multiple windows, it just closes the one you clicked. If anything is ambiguous, it does nothing. **

SmartClose is a macOS menu bar utility that makes the red close button behave more like Windows. When you close the last normal window of an app, SmartClose politely quits the app. If there are multiple windows, it only closes the one you clicked.

SmartClose is conservative by design. If anything is ambiguous, inaccessible, or potentially unsafe, it passes the close through instead of forcing behavior.

## Why it exists

On macOS, clicking the red close button usually closes a window but keeps the app running. That is native behavior, but it feels inconsistent if you switch between Windows and macOS frequently or expect single-window apps to quit when their last window closes.

## What SmartClose changes

- If the app has more than one normal window, SmartClose leaves the close behavior alone.
- If the app has exactly one normal window, SmartClose requests a normal quit.
- If anything is ambiguous or inaccessible, SmartClose does nothing.

## Safety model

- SmartClose only acts when it can reliably inspect windows through Accessibility APIs.
- If required permissions are missing, SmartClose stays disabled.
- It does not use pixel color detection or coordinate heuristics.
- It never force-quits apps.

## Requirements

- macOS 13.0 or later
- Accessibility permission
- Input Monitoring permission

## Install

### Download a release

1. Download the latest `SmartClose-<version>.dmg` from [GitHub Releases](https://github.com/mahirozdin/SmartClose/releases).
2. Open the disk image and drag `SmartClose.app` into `Applications`.
3. Launch SmartClose from `Applications`.
4. Complete onboarding and grant the requested permissions.

Each release also includes a notarized ZIP of the same app bundle and a SHA-256 checksum file.

### Build from source

1. Open [SmartClose.xcodeproj](./SmartClose.xcodeproj) in Xcode.
2. Select the `SmartClose` scheme.
3. Build and run.

## Configuration

- Ignore list and allow list with `*` wildcard support
- Per-app policies: default, always normal close, always quit on last window, disabled
- Hidden and minimized window handling toggles
- Optional Cmd+W handling (experimental, off by default) — see below
- Pause mode
- Launch at login

### Cmd+W handling (experimental)

By default SmartClose only reacts to the red close button. You can optionally
enable the same smart-close behavior for the `Cmd+W` shortcut from **Settings →
Behavior → Handle Cmd+W (experimental)**.

It is intentionally conservative and **off by default**, because `Cmd+W` also
closes tabs, documents, and editor panes in many apps. When enabled, SmartClose
never intercepts the keystroke: it lets the app handle `Cmd+W` normally first,
then re-checks the window count over a short bounded retry window and requests a
normal quit only if that actually closed the app's last normal window. It honors
the ignore/allow lists and per-app rules, and never acts on SmartClose itself.

## Permissions

SmartClose uses macOS Accessibility APIs to detect the close action and inspect windows, plus Input Monitoring to receive the global close-button click.

Detailed permission notes live in [docs/permissions.md](./docs/permissions.md).

## Releasing

Release and notarization steps live in [docs/release.md](./docs/release.md).

The repository includes:

- [scripts/release_local.sh](./scripts/release_local.sh) for local signed and notarized builds
- [scripts/create_dmg.sh](./scripts/create_dmg.sh) for DMG packaging
- [release.yml](./.github/workflows/release.yml) for GitHub Actions releases

## Known limitations

- Accessibility and Input Monitoring are both required.
- Some apps expose windows in non-standard ways.
- Electron or custom windowing toolkits may behave differently.
- Behavior can vary across third-party macOS apps with unusual window lifecycles.
- The Mac App Store is not a good fit for this permission model.

## Documentation

- [FAQ](./docs/faq.md)
- [Contributing](./CONTRIBUTING.md)
- [Changelog](./CHANGELOG.md)

## Contributors

Thanks goes to these wonderful people ([emoji key](https://allcontributors.org/docs/en/emoji-key)):

<!-- ALL-CONTRIBUTORS-LIST:START - Do not remove or modify this section -->
<!-- prettier-ignore-start -->
<!-- markdownlint-disable -->
<table>
  <tbody>
    <tr>
      <td align="center" valign="top" width="14.28%"><a href="https://github.com/mahirozdin"><img src="https://avatars.githubusercontent.com/u/9491185?v=4?s=100" width="100px;" alt="Mahir Taha Özdin"/><br /><sub><b>Mahir Taha Özdin</b></sub></a><br /><a href="https://github.com/mahirozdin/SmartClose/commits?author=mahirozdin" title="Code">💻</a> <a href="https://github.com/mahirozdin/SmartClose/commits?author=mahirozdin" title="Documentation">📖</a> <a href="#maintenance-mahirozdin" title="Maintenance">🚧</a> <a href="#design-mahirozdin" title="Design">🎨</a></td>
      <td align="center" valign="top" width="14.28%"><a href="https://github.com/sohate"><img src="https://avatars.githubusercontent.com/u/81889148?v=4?s=100" width="100px;" alt="sohate"/><br /><sub><b>sohate</b></sub></a><br /><a href="#ideas-sohate" title="Ideas, Planning, & Feedback">🤔</a></td>
    </tr>
  </tbody>
</table>

<!-- markdownlint-restore -->
<!-- prettier-ignore-end -->

<!-- ALL-CONTRIBUTORS-LIST:END -->

This project follows the [all-contributors](https://github.com/all-contributors/all-contributors) specification. Contributions of any kind — code, ideas, docs, bug reports — are welcome!

## Privacy

All logic runs locally on your Mac. SmartClose does not send telemetry by default.
