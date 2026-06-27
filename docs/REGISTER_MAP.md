# TAC5 Register Map

This is a working reference for the TAC5 / EOLE 4 Modbus map.

Important indexing note:

- The live Modbus reads in this repo use 0-based holding register offsets.
- The vendor-style document addresses use 41xxx/42xxx references.
- Both forms are listed below so the map is easier to cross-check.

## Confidence legend

- confirmed: directly verified from capture and/or stable readback behavior
- likely confirmed: repeatedly observed, but vendor mapping is still not formally verified
- alias: compatibility alias in app code, not a distinct physical sensor

| Key | Raw offset | Document address | Access | Type | Scale | Unit | Status | Notes |
| --- | --- | --- | --- | --- | --- | --- | --- | --- |
| T1 | 154 | 41001 | ro | int16 | 0.1 | C | confirmed | live sensor value |
| T2 | 155 | 41002 | ro | int16 | 0.1 | C | confirmed | live sensor value |
| T3 | 156 | 41003 | ro | int16 | 0.1 | C | confirmed | live sensor value |
| T4 | 8 | 41004 | ro | int16 | 0.1 | C | alias | backward-compatible alias, currently mapped to T7 in code |
| T7 | 8 | 41004 | ro | int16 | 0.1 | C | confirmed | live sensor value |
| SUPPLY_AIRFLOW | 64 | 41010 | ro | uint16 | 1 | m3_h | confirmed | live supply airflow |
| EXHAUST_AIRFLOW | 72 | 41011 | ro | uint16 | 1 | m3_h | confirmed | live exhaust airflow |
| WORKING_MODE | 52 | 42001 | rw | uint16 | 1 | enum | likely confirmed | active mode / preset index; K1=1, K2=2, K3=3, Boost observed as 1/3 transition |
| PRESET_WRITE_TRIGGER | 199 | - | rw | uint16 | 1 | trigger | confirmed | FC06 writes 0 before each preset change |
| RATIO_EXH_SUP | 53 | 42002 | rw | uint16 | 0.01 | ratio | likely confirmed | tracks preset / boost setpoint block |
| AIRFLOW_I | 55 | 42003 | rw | uint16 | 1 | m3_h | likely confirmed | K1 preset value observed at 200, Boost at 840 |
| AIRFLOW_II | 56 | 42004 | rw | uint16 | 1 | m3_h | likely confirmed | K2 preset value observed at 300, Boost at 840 |
| PRESET_STATE | 202 | 42005 | rw | uint16 | 1 | enum | confirmed | K1=1, K2=2, K3=3 |
| BYPASS_ENABLE | 222 | - | rw | uint16 | 1 | bool-like | confirmed | FC06 write single register: 1 = Bypass on, 0 = Bypass off |
| BOOST_ENABLE | 227 | - | rw | uint16 | 1 | bool-like | confirmed | FC06 write single register: 1 = Boost on, 0 = Boost off (validated in Wireshark) |

## Confirmed write sequences (capture-based)

- Preset transitions (capture: k123_cycle_new.pcapng):
  - K3 -> K1: 199=0, then 202=1
  - K1 -> K2: 199=0, then 202=2
  - K2 -> K3: 199=0, then 202=3
- Bypass toggle (capture: bypass_test_capture.pcapng):
  - ON: 222=1
  - OFF: 222=0
- Boost toggle (multiple captures):
  - ON: 227=1
  - OFF: 227=0

## Observed runtime behavior

- K1 -> K2 -> K3 produced the following sequence:
  - 52: 1 -> 2 -> 3
  - 53: 200 -> 300 -> 400
  - 55: 200 -> 300 -> 400
  - 56: 200 -> 300 -> 400
  - 202: 1 -> 2 -> 3
- Boost on produced:
  - 52: 3 -> 1
  - 53: 400 -> 840
  - 55: 400 -> 840
  - 56: 400 -> 840
- Boost off returned:
  - 52: 1 -> 3
  - 53: 840 -> 400
  - 55: 840 -> 400
  - 56: 840 -> 400

- The app writes preset changes as a two-step command: 199=0, then 202=<1|2|3>.
- The app writes bypass as a single FC06 command to register 222.
- The app writes boost as a single FC06 command to register 227.

## Open questions

- Whether 52 is strictly the active preset index or a broader working mode selector.
- Whether register 52 mirrors active preset for all firmware variants.
- Whether AIRFLOW_I / II / III are three editable setpoints or a shared block with one active selector.
- Whether Boost is a dedicated mode bit or an alternate setpoint profile.
