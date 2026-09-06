# Guidance for coding agents

## Project boundaries

- This is a native SwiftUI iOS app using CoreBluetooth.
- Minimum deployment target is iOS 17.
- `TreadmillManager` and its published state are `@MainActor` isolated.
- Keep UI composition in SwiftUI views and BLE/protocol behavior in
  `TreadmillManager` and `TreadmillProtocol`.
- Do not add a `CHANGELOG.md`.

## Xcode project and signing

- `TreadmillRemote.xcodeproj/project.pbxproj` is committed and is the
  authoritative Xcode project.
- `TreadmillRemote/Assets.xcassets` contains the app icon. Keep its
  `AppIcon.appiconset` resource referenced by the target's Resources phase.
- Make routine changes directly in source files. Do not run XcodeGen after
  every change; it can rewrite unrelated project settings.
- Do not change `CODE_SIGN_STYLE`, `CODE_SIGN_IDENTITY`, bundle identifiers, or
  other signing settings unless the user explicitly requests it.
- Keep `.claude/settings.local.json` ignored by `.gitignore`.

## BLE behavior

- Do not create `CBCentralManager` until the user taps **Connect** or starts a
  scan. This preserves the permission prompt timing.
- Scan broadly, then filter candidates using treadmill names and advertised
  Fitness Machine/configured services. Proprietary treadmill boards often do
  not advertise their service UUID before connection.
- Do not treat RSSI as device identity. Show the name, match reason, advertised
  services, and GATT results.
- Treadmill controls must remain disabled until the configured target service
  and a writable characteristic have been discovered.
- Preserve the live hex console for every outgoing write and incoming
  notification.
- Avoid writing to unknown OTA/DFU-looking characteristics.

## FitShow protocol

- Default GATT: service `FFF0`, notify `FFF1`, write `FFF2`.
- Frames are `02 | payload | XOR(payload) | 03`.
- Default control codes are start `01`, target speed/incline `02`, stop `03`,
  and pause `0A`. Some older implementations report pause as `06`; keep frame
  overrides available rather than silently probing unsafe commands.
- `FFF2` generally requires `.withResponse` when its properties include
  `.write`. Use `.withoutResponse` only for characteristics that expose only
  `.writeWithoutResponse`.
- Do not claim a command works without a physical-device test and console
  evidence.

## Validation

Use the existing project and build command:

```sh
xcodebuild -project TreadmillRemote.xcodeproj \
  -scheme TreadmillRemote \
  -sdk iphonesimulator \
  -configuration Debug \
  CODE_SIGNING_ALLOWED=NO \
  build
```

For routine source edits, build the committed project directly. Only update
the generated project intentionally and inspect the diff for signing or
bundle-setting changes before committing.
