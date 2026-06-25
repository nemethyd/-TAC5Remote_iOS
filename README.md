# TAC5 Remote iOS (New Client)

This workspace contains a clean iOS-oriented foundation for a modern TAC5 client.

## Goal

Build a modern, stable app for TAC5-compatible units over Modbus TCP (default port 502), with a cleaner UX than legacy vendor apps.

## Scope (MVP)

- Device discovery by manual host entry (IP + port)
- Safe connect/disconnect
- Read core telemetry (airflow, T1/T2/T3 and other available registers)
- Visualization screen (unit status + key values)
- Basic setup screen (read/write selected writable registers)
- Error handling and reconnect strategy

## Architecture

- `TAC5Core` Swift package for protocol and business logic
- iOS app layer (SwiftUI) for UI and state management
- Register map kept external so model variants are easier to support

## Naming and Bundle ID

- Domain owner: `moderato.hu`
- Recommended app name: `TAC5 Remote`
- Recommended bundle identifier: `hu.moderato.tac5remote`
- Optional split by targets:
  - iOS app: `hu.moderato.tac5remote.ios`
  - Internal test app (if needed): `hu.moderato.tac5remote.internal`

## Important

- Register addresses and writable capabilities must be validated on real hardware.
- Do not assume all TAC5 variants expose the same register set.
- Start read-only, then enable write operations after validation.

## Next Build Steps

1. Generate the iOS app project from `project.yml`:
   - `brew install xcodegen`
   - `xcodegen generate`
2. Open `TAC5Remote_iOS_App.xcodeproj` and run scheme `TAC5Remote_iOS_App`.
3. Replace mock connect flow with real Modbus transport (`Network.framework`).
4. Fill register map from validated TAC5 documentation/device tests.
5. Add integration tests against a Modbus simulator.

## Included Minimal App Scaffold

- SwiftUI app sources in `App/Sources`
- XcodeGen project spec in `project.yml`
- Local package dependency wiring to `TAC5Core`
- Real connect/read/disconnect flow using `ModbusTCPClient`

## Current Status

- `ModbusTCPClient` now uses `Network.framework` transport for Modbus TCP exchange.
- App `Connect` executes a real register read (`TAC5Repository.readSnapshot()`).
- `Refresh` re-reads telemetry from the connected unit.
- Optional cloud upload flow added in app UI (`Cloud` section):
  - enable/disable cloud sync
  - set endpoint URL
  - set optional API key (`Authorization: Bearer <key>`)
  - run manual `Sync Now`

## Cloud Payload (App -> Cloud)

The app sends JSON payload with:

- `timestamp` (ISO-8601)
- `source` (`host`, `unitId`, `trigger`)
- `snapshot` (`t1/t2/t3/t4`, `supply/exhaust airflow`)

## Cloud Build

- GitHub Actions workflow: `.github/workflows/ios-cloud-build.yml`
- Jobs:
  - `swift_package_tests`: runs `swift test`
  - `ios_app_build`: generates Xcode project and runs `xcodebuild`
