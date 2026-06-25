# TAC5 Remote iOS

Modern iOS client foundation for TAC5-compatible units over Modbus TCP.

## What this repo is

- `TAC5Core` contains the protocol and data model layer.
- `App/Sources` contains the SwiftUI iOS app shell.
- `project.yml` is the XcodeGen spec for generating the iOS project.
- `.github/workflows/ios-cloud-build.yml` runs the cloud build on macOS runners.

## Current status

- Modbus TCP connect/read/disconnect flow is implemented in `TAC5Core`.
- The app can read a snapshot and display telemetry placeholders.
- Cloud upload can be enabled from the UI and sends snapshot JSON to an HTTPS endpoint.
- The repository is set up for GitHub Actions based cloud build.

## Scope

- Manual host, port, and unit ID entry.
- Read telemetry values from the unit.
- Basic connect/disconnect and refresh flow.
- Optional cloud sync for snapshots.
- Later: write operations, diagnostics, planner screens, and richer device handling.

## Local development

1. Generate the Xcode project from the spec with `brew install xcodegen` and `xcodegen generate`.
2. Open `TAC5Remote_iOS_App.xcodeproj` in Xcode.
3. Run the `TAC5Remote_iOS_App` scheme on a simulator or device.

## Cloud build

The workflow runs on GitHub-hosted macOS runners:

- `swift_package_tests`: executes `swift test`
- `ios_app_build`: generates the Xcode project and runs `xcodebuild`

This is enough for build validation, but not for reading a device that only exists on your local network.

## TestFlight

- Manual TestFlight workflow: `.github/workflows/testflight-upload.yml`
- Setup notes: `docs/TESTFLIGHT_SETUP.md`

## Cloud sync payload

The app sends JSON with:

- `timestamp` in ISO-8601 format
- `source` containing `host`, `unitId`, and `trigger`
- `snapshot` with the telemetry fields (`t1` to `t4`, supply and exhaust airflow)

## Important notes

- TAC5 register addresses and scaling must still be validated on real hardware.
- Not every TAC5 variant exposes the same register set.
- Start with read-only behavior and enable writes only after validation.

## Repository layout

- `App/` - iOS app sources
- `Sources/TAC5Core/` - Modbus client and model logic
- `Tests/` - unit tests for the package
- `docs/` - project notes and register map templates
