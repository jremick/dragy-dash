# Contributing

Contributions are welcome, but keep the project privacy-safe and device-safe.

## Ground Rules

- Do not commit raw BLE captures, route coordinates, exported session CSVs, full Dragy identifiers, phone UDIDs, or Apple signing details.
- Keep protocol examples sanitized and reproducible.
- Keep simulator-safe mock telemetry working so UI changes can be reviewed without hardware.
- Do not add dependencies unless they materially simplify the project.
- This project is unofficial and experimental; wording should not imply Dragy endorsement.

## Local Checks

```bash
swift tools/generate_app_icon.swift
xcodegen generate
xcodebuild -project DragyDash.xcodeproj -scheme DragyDash -destination 'platform=iOS Simulator,name=iPhone 17,OS=latest' test
```

Use another available iPhone simulator if `iPhone 17` is not installed locally.

## Device Testing

BLE behavior must be verified on a physical iPhone with a Dragy device. Before posting logs or screenshots, redact personal identifiers and location data.
