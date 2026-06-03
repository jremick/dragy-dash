# DragyDash Instructions

Version: 0.2.0
Last updated: 2026-06-04

## Scope

These instructions apply to the DragyDash iOS app project.

## Project Rules

- Keep the app public-repo safe: do not commit private device IDs, route data, signing details, or unsanitized captures.
- Treat the Dragy Pro protocol notes as experimental observations from limited hardware, not an official or complete specification.
- Keep Dragy-specific packet decoding isolated in `DragyDash/Services/DragyPacketDecoder.swift`.
- Keep simulator-safe mock telemetry available so UI work remains verifiable without the device.
- Never commit BLE captures that contain personal route/location data unless they have been intentionally sanitized.
- Use XcodeGen as the readable project source of truth. Regenerate `DragyDash.xcodeproj` after changing `project.yml`.

## Verification

- Run `xcodegen generate` after editing `project.yml`.
- Run a simulator build before claiming the app compiles.
- Run unit tests after touching packet decoding.
- Device-only Bluetooth behavior must be verified on an iPhone, not the simulator.
