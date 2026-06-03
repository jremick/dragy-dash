# Dragy Pro BLE Notes

Version: 0.2.0
Last updated: 2026-06-03

These are sanitized notes from building DragyDash against a Dragy Pro. Device suffixes, persistent identifiers, and route/location values are intentionally redacted.

## BLE Identity

Observed Dragy Pro advertising pattern:

- Local name: `DRG70-xxxxxx`
- Advertised service: `FD00`
- Manufacturer/model values from Device Information service identify the device as Dragy hardware.

DragyDash treats a peripheral as a candidate when the name/local name looks like Dragy/DRG, the advertised services include `FD00`, or manufacturer data contains a Dragy-looking ASCII value.

## Services And Characteristics

Primary service:

- `FD00`
  - `FD01`: read, write; descriptor label `spp data tx`
  - `FD02`: notify; descriptor label `spp data rx`
  - `FD03`: read, write; descriptor label `spp config`
  - `FD04`: read, write, notify; descriptor label `device control`
  - `FD05`: read, write; descriptor label `MCU update`
  - `FD11`: read, write; descriptor label `Factory test`

Other observed services:

- `00006287-3C17-D293-8E48-14FE2E4DA212`
  - `00006387-3C17-D293-8E48-14FE2E4DA212`: writeWithoutResponse
  - `00006487-3C17-D293-8E48-14FE2E4DA212`: write, notify
- `0000D0FF-3C17-D293-8E48-14FE2E4DA212`
  - `FFD1`, `FFD8`: writeWithoutResponse
  - `FFD2`, `FFD3`, `FFD4`, `FFD5`, `FFF1`, `FFE0`: read
  - `FFF2`: write
- `180A` Device Information
  - Standard read characteristics such as manufacturer, model, serial, firmware, hardware, software, system ID, and PnP ID.

## Handshake

Passive subscription to `FD02` was not enough to receive live GPS. The Dragy Pro starts streaming after a challenge/response on `FD03`.

Observed handshake:

1. Read `FD03`.
2. Treat the first two bytes as challenge bytes `a` and `b`.
3. Write four bytes back to `FD03`: `[a, b, a XOR b, a AND b]`.
4. After the write acknowledgment, `FD02` starts sending fragmented live telemetry notifications.

DragyDash performs this once per connection.

## Live GPS Stream

The live stream on this device uses UBX NAV-PVT packets over `FD02`.

- Message class/id: `01 07`
- Payload length: `5C 00` / 92 bytes
- Full frame length with UBX sync/checksum: 100 bytes
- CoreBluetooth commonly delivers fragments, often in small chunks, so DragyDash buffers and reassembles complete frames before decoding.

Decoded NAV-PVT fields used by DragyDash:

- fix type -> no fix / 2D / 3D / estimated
- satellite count
- latitude / longitude
- altitude
- horizontal accuracy
- ground speed (`gSpeed`, mm/s -> km/h)
- heading of motion

When fix quality is no-fix, DragyDash displays speed as 0 and does not feed that packet into distance or rolling averages.

## Battery / Device Status

`FD04` emits device-control/status values. DragyDash currently treats byte 1 as battery percentage when it is in the range `0...100`.

Example shape:

- `01 54` -> `84%`

Unknown or out-of-range values are ignored.

## Motion And Sensor Values

This Dragy Pro stream exposed GNSS-derived motion, not a complete raw IMU packet map.

Current derived values:

- Longitudinal G is estimated from speed delta over elapsed time.
- Lateral G is estimated from speed and heading-rate change.
- Yaw rate can be derived internally from heading-rate change, but the app no longer displays yaw.

Current displayed sensor/session values:

- satellites
- horizontal accuracy
- altitude
- battery
- lateral G
- longitudinal G
- peak speed
- distance
- 0-60 and 0-100 timing
- rolling speed averages

## Filtering And Accuracy

Stationary GNSS speed flicker is expected. DragyDash applies display/stat filtering:

- below 5 km/h while stopped: displayed as 0
- once moving, speed must fall to 2 km/h or below before returning to stopped state
- no-fix packets are kept as raw samples for diagnostic CSV, but are not counted toward distance, acceleration targets, peak speed, or rolling averages

Rolling average buffers retain enough usable GNSS history for 15 km.

## Session Data

Saved sessions are CSV files in the app documents area.

- Saving is on by default.
- Session reset saves the current session first when saving is enabled and there are samples.
- Manual save/export is available in Settings.
- Only the newest 3 saved session files are retained.

## Remaining Unknowns

- Whether all Dragy Pro firmware variants expose the same `FD00` layout.
- Whether a richer raw IMU packet exists outside the decoded UBX stream.
- Whether multiple centrals can maintain live connections to one Dragy Pro at the same time. This matters for the later ESP32 display.
