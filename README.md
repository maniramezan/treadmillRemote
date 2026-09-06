# Treadmill Remote

Lightweight SwiftUI iOS remote for BLE treadmills that use the FitShow/Egofit
protocol family.

## Requirements

- Xcode 17 or newer
- iOS 17 or newer
- A BLE treadmill powered on and within range
- Bluetooth permission enabled for the app

## Build

Open `TreadmillRemote.xcodeproj` in Xcode and build the `TreadmillRemote`
scheme for an iPhone. The simulator can compile the target, but CoreBluetooth
device discovery and treadmill control require physical hardware.

The committed Xcode project is authoritative for normal development. The
`project.yml` file documents the original XcodeGen setup, but do not run
XcodeGen for routine source changes: regeneration can rewrite unrelated
`project.pbxproj` settings, including code signing and bundle configuration.

## Using the app

1. Power on the treadmill and keep the iPhone nearby.
2. Tap **Connect**. Bluetooth permission is requested at this point, not at
   app launch.
3. Select the Egofit/FitShow device from the filtered nearby-device list.
4. Open **Settings / GATT** to confirm the discovered service and writable
   characteristic.
5. Use the dashboard controls only after the configured GATT service and write
   characteristic are discovered.
6. Use **BLE Console** to inspect outgoing frames and treadmill notifications.

The scanner filters for recognizable treadmill names, the configured service
(default `FFF0`), or the standard Fitness Machine Service (`1826`). RSSI is a
relative radio-strength value, not a reliable distance or identity check.

## Protocol defaults

The default vendor GATT layout is:

| Item | UUID |
| --- | --- |
| Service | `FFF0` |
| Notify | `FFF1` |
| Write | `FFF2` |

FitShow frames use `02` as the header, `03` as the footer, and XOR the payload
bytes for the checksum. The app's defaults use:

- Start: control opcode `53 01`, followed by the normal-mode start payload
- Speed: control opcode `53 02`, with speed in tenths
- Pause: control opcode `53 0A`
- Stop: control opcode `53 03`

Firmware variants may expose `FFE0/FFE1`, `AE00/AE01`, or `FAB1/FAB2`-style
characteristics. The GATT Inspector supports overriding UUIDs and frames
without recompiling.

## Safety

This app sends commands directly to exercise equipment. Test at the lowest
speed, keep the treadmill's physical emergency stop accessible, and do not
rely on the app as the only safety mechanism.

