# SmartClose Permissions

SmartClose requires two macOS permissions:

- **Accessibility** to inspect the clicked close button, find the owning window, and count the app's remaining windows.
- **Input Monitoring** to receive the global close-button click before macOS handles it.

## How the flow works
1. Launch SmartClose.
2. In onboarding, click **Grant Access** for each missing permission.
3. If macOS does not show a prompt, SmartClose will switch that row to **Open Settings** so you can finish the grant manually.
4. SmartClose refreshes permission state automatically as soon as you return to the app.
5. If macOS grants access but SmartClose still cannot rebuild its event tap, the UI will show **Relaunch SmartClose** as a recovery step.

## Manual paths in System Settings
- **Privacy & Security > Accessibility**
- **Privacy & Security > Input Monitoring**

## Troubleshooting stale permission state
Signing changes, old Debug builds, macOS upgrades, or restored app copies can leave stale TCC entries behind. If SmartClose appears in the list but still reports missing access:

1. Quit SmartClose.
2. Run these commands in Terminal:

```bash
tccutil reset Accessibility com.smartclose.app
tccutil reset ListenEvent com.smartclose.app
```

3. Launch SmartClose again and re-grant both permissions.

## Notes
- SmartClose is designed for a signed app bundle identity. Running older unsigned or linker-signed Debug builds can cause TCC mismatches.
- If an app behaves unexpectedly after permissions are working, add it to the ignore list instead of forcing more permissions.
