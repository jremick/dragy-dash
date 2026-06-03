# Security Policy

## Reporting

Please do not open public issues containing raw BLE captures, route coordinates, full Dragy identifiers, exported CSV sessions, diagnostic reports, or personal device identifiers.

For public discussion, redact:

- Dragy device suffixes and persistent BLE identifiers
- latitude, longitude, and route traces
- phone UDIDs, Apple team IDs, and signing details
- packet captures that may identify a specific device or route

If you believe the project exposes sensitive data by default, open a minimal issue with redacted reproduction steps and note that private details are available if needed.

## Supported Versions

This is an experimental project. Only the current `main` branch is actively maintained.

## Scope

In scope:

- accidental disclosure of private telemetry, device identifiers, or route data
- unsafe diagnostic defaults
- dependency or build-chain issues that affect this repository

Out of scope:

- vulnerabilities in Dragy hardware, firmware, or official apps
- bypassing access controls on devices you do not own
- unsafe driving behavior or operation outside local laws
