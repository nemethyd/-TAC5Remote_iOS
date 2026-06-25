# iOS Rewrite MVP Plan

## Product Direction
A modern replacement app focused on reliability, readable UX, and safe configuration.

## Must-Have Features
- Connect screen
: Host, port (default 502), unitId, timeout
- Visualization screen
: airflow, T1/T2/T3(+T4 if available), status
- Setup screen
: selected writable fields only
- Planner (phase 2)
: week planner first, year planner later
- Diagnostics
: communication log, register read errors, reconnect state

## Security and Safety
- Local network only by default
- Explicit "write enabled" toggle
- Confirmation dialogs for writes
- Optional read-only mode lock

## Technical Milestones
1. Modbus transport implementation (Network.framework)
2. Register map validation against physical TAC5 unit
3. Snapshot polling + state cache
4. SwiftUI screens and navigation
5. Write operations with guardrails
6. TestFlight pilot build

## Risks
- Register map mismatch between TAC5 variants
- Vendor-specific scaling and signed value handling
- Write side effects on live ventilation behavior

## Validation Checklist
- Read telemetry stable for 24h
- No crashes under intermittent Wi-Fi
- Correct scaling for temperatures and airflow
- Safe rollback path for setup changes
