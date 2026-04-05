# SmartClose Architecture

## Overview
SmartClose is a menu bar utility that intercepts close-button intent, inspects the target app's window state via Accessibility APIs, and decides whether to allow a normal close or request a quit.

## Core Components
- **PermissionManager**: Tracks Accessibility permission state and opens System Settings.
- **EventMonitor**: Low-level CGEventTap for left mouse down/up.
- **AXInspector**: Minimal wrapper over Accessibility APIs for element lookup and window metadata.
- **WindowClassifier**: Filters windows into countable vs ignored and flags ambiguity.
- **DecisionEngine**: Pure, unit-testable decision logic.
- **AppPolicyResolver**: Applies ignore list, allow list, and per-app policy overrides.
- **ActionExecutor**: Sends a graceful quit request.
- **DiagnosticsStore**: Ring buffer of recent decisions for the diagnostics UI.
- **SettingsStore**: Strongly typed, JSON-codable settings persisted to UserDefaults.

## Flow Summary
1. EventMonitor detects left-click on the close button.
2. AXInspector resolves the target window + app PID.
3. WindowClassifier counts normal windows (fail-safe on ambiguity).
4. DecisionEngine returns pass-through vs quit request.
5. ActionExecutor requests a normal quit if needed.
6. DiagnosticsStore records the result.

## Threading
- Event tap runs on its own thread.
- Diagnostics updates are dispatched to the main thread.
- Settings persistence uses UserDefaults and is accessed on the main thread.

## Wildcard Matching
Bundle ID patterns support `*` as a wildcard that matches any sequence of characters.
Matching is case-sensitive and must match the full bundle ID.
