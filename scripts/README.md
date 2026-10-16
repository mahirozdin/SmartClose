Scripts used for local development and release automation live here.

- `create_dmg.sh`: builds a simple drag-to-Applications DMG.
- `release_local.sh`: archives, exports, notarizes, staples, zips, and packages the public release artifacts.
- `test_launch_behavior.swift`: checks login/manual launches and reopens through Launch Services using isolated settings. Run it in an active macOS desktop session after building the app:

  ```sh
  swiftc -parse-as-library scripts/test_launch_behavior.swift -o build/test-launch-behavior
  build/test-launch-behavior "$PWD/build/DerivedData/Build/Products/Debug/SmartClose.app"
  ```

  This sends the native login Apple Event without logging out. It checks window counts and activation policy for six scenarios, then terminates only the instances it launched. It disables monitoring and update checks in those instances. Run it separately from XCUITest: the sandboxed UI test runner cannot pass the environment needed to isolate the app's settings through Launch Services. A real logout/login and an end-to-end update installation remain manual release checks.
