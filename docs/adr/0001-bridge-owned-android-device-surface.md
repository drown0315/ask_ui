# Bridge-Owned Android Device Surface

Ask UI will route Android device screen and input control through the local bridge session instead of letting the web app manage scrcpy or ADB directly. The bridge already owns local Flutter session integration, and scrcpy adds local process, device serial, port, stream, and input lifecycle concerns that belong beside that session boundary; the web app should consume bridge-provided surface state and send user input through bridge APIs.

The page startup contract includes `deviceId` so the bridge can target the same Android device with ADB/scrcpy. In the first version, the bridge performs a Target Device availability check by confirming that the requested `deviceId` appears in `flutter devices --machine` output before creating a session. This check proves that Flutter currently sees the requested device; it does not strictly prove that the session's `vmServiceUri` came from that same device.

If `flutter devices --machine` runs but does not list the requested Android device, the bridge should reject session creation with `target_device_not_found`. If the check itself fails, such as Flutter missing from PATH, malformed machine output, or the command exiting unsuccessfully, the bridge should reject with `target_device_check_failed` and log the underlying error plus stack trace for diagnosis.

The first version should run `flutter devices --machine` for each session creation request instead of caching device visibility. Device attachment state changes quickly, and session creation is not expected to be high frequency.

The availability check should only accept Android Flutter devices. Desktop and web targets such as `macos` or `chrome` may appear in Flutter's device list, but they are not Target Devices for Ask UI's Android/scrcpy-backed Live App Surface.

A session request that repeats an existing `vmServiceUri` and project root with a different `deviceId` should fail with an explicit configuration error instead of creating a second session or silently reusing the first one. A workbench session is bound to exactly one Target Device for its lifetime.

Session lookup should continue to treat the `vmServiceUri` and project root as the Flutter app session identity. The `deviceId` is a required binding on that session and must be checked for consistency rather than added to the lookup key, because adding it to the key would allow one Flutter app session to be opened against multiple devices.

Stricter VM Service/device binding verification can be added later if a reliable method is found. Until then, the bridge records the required `deviceId` as the caller's binding declaration, checks that the device is visible to Flutter, and enforces consistency for repeated requests to the same Flutter app session.

Correcting a bad or missing `deviceId` should happen by reloading Ask UI with a corrected page URL. The Target Device is part of the startup contract, not a runtime switch inside an established workbench session.

The browser-embedded surface should use the official scrcpy server binary rather than the desktop scrcpy CLI window. A reference implementation in `ws-scrcpy` shows the viable architecture shape, but its vendored server differs from the official scrcpy 4.0 server, so Ask UI should calibrate the official server startup arguments, stream framing, and control protocol before locking the web/bridge contract.
