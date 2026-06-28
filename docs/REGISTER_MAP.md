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

Ordering principle for the table below:

- live read-only telemetry first
- shared/global writable controls next
- mode-specific writable parameters grouped after that

| Key | Raw offset | Document address | Access | Type | Scale | Unit | Status | Notes |
| --- | --- | --- | --- | --- | --- | --- | --- | --- |
| T1 | 154 | 41001 | ro | int16 | 0.1 | C | confirmed | live sensor value |
| T2 | 155 | 41002 | ro | int16 | 0.1 | C | confirmed | live sensor value |
| T3 | 156 | 41003 | ro | int16 | 0.1 | C | confirmed | live sensor value |
| T4 | 8 | 41004 | ro | int16 | 0.1 | C | alias | backward-compatible alias, currently mapped to T7 in code |
| T7 | 8 | 41004 | ro | int16 | 0.1 | C | confirmed | live sensor value |
| SUPPLY_AIRFLOW | 64 | 41010 | ro | uint16 | 1 | m3_h | confirmed | live supply airflow |
| EXHAUST_AIRFLOW | 72 | 41011 | ro | uint16 | 1 | m3_h | confirmed | live exhaust airflow |
| WORKING_MODE | 52 | 42001 | rw | uint16 | 1 | enum | confirmed | active mode / preset index; repeatedly verified in capture/behavior; K1=1, K2=2, K3=3, Boost observed as 1/3 transition |
| PRESET_STATE | 202 | 42005 | rw | uint16 | 1 | enum | confirmed | K1=1, K2=2, K3=3 |
| OPERATION_MODE | 425 | - | rw | uint16 | 1 | enum | confirmed | OFF=0, CA=1, LS=2, CP=4 (capture-verified) |
| BOOST_ENABLE | 227 | - | rw | uint16 | 1 | bool-like | confirmed | FC06 write single register: 1 = Boost on, 0 = Boost off (validated in Wireshark) |
| BYPASS_ENABLE | 222 | - | rw | uint16 | 1 | bool-like | confirmed | FC06 write single register: 1 = Bypass on, 0 = Bypass off |
| PRESET_WRITE_TRIGGER | 199 | - | rw | uint16 | 1 | trigger | confirmed | FC06 writes 0 before each preset change |
| MANUAL_SCHEDULE_MODE | 199 | - | rw | uint16 | 1 | enum | confirmed | manual / schedule selector; repeated isolated captures showed 0 = Manual and 2 = Schedule |
| RATIO_EXH_SUP | 426 | TBD | rw | uint16 | 0.01 | ratio | likely confirmed | capture-verified write target for exhaust/supply ratio; app writes directly to this register |
| AIRFLOW_I | 427 | TBD | rw | uint16 | 1 | m3_h | confirmed | CA mode supply setpoint I; capture-tested with 200 / 100 |
| AIRFLOW_II | 428 | TBD | rw | uint16 | 1 | m3_h | confirmed | CA mode supply setpoint II; capture-tested with 400 / 200 |
| AIRFLOW_III | 429 | TBD | rw | uint16 | 1 | m3_h | confirmed | CA mode supply setpoint III; capture-tested with 600 / 300 |
| LS_VMIN | 437 | TBD | rw | uint16 | 0.1 | V | confirmed | LS mode minimum analog input threshold; 0.9 V produced raw value 9 |
| LS_VMAX | 438 | TBD | rw | uint16 | 0.1 | V | confirmed | LS mode maximum analog input threshold; 9.5 V and 10.0 V produced raw values 95 and 100 |
| LS_AIRFLOW_AT_VMIN | 439 | TBD | rw | uint16 | 1 | m3_h | confirmed | LS mode airflow setpoint at Vmin; capture-tested with 100 and 150 |
| LS_AIRFLOW_AT_VMAX | 440 | TBD | rw | uint16 | 1 | m3_h | confirmed | LS mode airflow setpoint at Vmax; capture-tested with 800 and 840 |
| LS_STOP_IF_BELOW_VLOW | 500 | TBD | rw | uint16 | 1 | bool-like | confirmed | LS mode stop-fan enable for low analog threshold; clean capture showed 1/0 writes |
| LS_VLOW | 501 | TBD | rw | uint16 | 0.1 | V | confirmed | LS mode low stop threshold; clean capture showed raw value 5 for 0.5 V |
| LS_STOP_IF_ABOVE_VHIGH | 502 | TBD | rw | uint16 | 1 | bool-like | confirmed | LS mode stop-fan enable for high analog threshold; clean capture showed 1/0 writes |
| LS_VHIGH | 503 | TBD | rw | uint16 | 0.1 | V | confirmed | LS mode high stop threshold; clean capture showed raw values 95 and 100 for 9.5 V and 10.0 V |
| LS_K3_010V_ENABLE | 504 | TBD | rw | uint16 | 1 | bool-like | confirmed | K3 0-10V mode master enable; clean capture showed No -> enabled -> No as 0/1/0 |
| LS_K3_SLEEP_FACTOR | 441 | TBD | rw | uint16 | 1 | percent | likely confirmed | K3 sleep factor; editable in K3=No mode; Eole UI emitted intermediate value 1 before final writes 90 and 100 |
| CP_ON_MODE | 442 | TBD | rw | uint16 | 1 | enum | confirmed | CP mode `CP on` selector; capture-tested transitions showed 0 = Supply, 1 = Exhaust, 2 = Supply / Exhaust |
| CP_SUPPLY_VOLTAGE | 445 | TBD | rw | uint16 | 0.1 | V | confirmed | CP voltage field; raw value 9 observed for 0.9 V in Supply mode, and raw value 5 for 0.5 V in Supply / Exhaust mode |
| CP_EXHAUST_VOLTAGE | 448 | TBD | rw | uint16 | 0.1 | V | confirmed | CP Exhaust voltage field in Supply / Exhaust mode; raw value 9 observed for 0.9 V |
| LS_K3_TARGET_SIDE | 583 | TBD | rw | uint16 | 1 | enum | confirmed | K3 target side when 0-10V on K3 is enabled; clean capture showed 0 = Exhaust and 1 = Supply |
| CP_START_AIRFLOW | 253 | TBD | rw | uint16 | 1 | m3_h | likely confirmed | CP Airflow-mode start setpoint; isolated capture showed write 10 followed by automatic reset to 0 |

## Confirmed write sequences (capture-based)

- Preset transitions (capture: k123_cycle_new.pcapng):
  - K3 -> K1: 199=0, then 202=1
  - K1 -> K2: 199=0, then 202=2
  - K2 -> K3: 199=0, then 202=3
- Manual / schedule selector (captures: manual_to_schedule_only_20260628_live.pcapng, schedule_to_manual_only_20260628_live.pcapng, manual_schedule_confirm_20260628_live.pcapng):
  - Manual -> Schedule produced 199=2
  - Schedule -> Manual produced 199=0 and companion 200=0
  - Best-fit interpretation is 199 = MANUAL_SCHEDULE_MODE with 0 = Manual and 2 = Schedule; 200 appears to be a companion reset/commit field rather than the primary selector
- Bypass toggle (capture: bypass_test_capture.pcapng):
  - ON: 222=1
  - OFF: 222=0
- Boost toggle (multiple captures):
  - ON: 227=1
  - OFF: 227=0
- Operation mode transitions (capture: mode_off_ca_ls_cp_confirm.pcapng):
  - OFF -> CA -> LS -> CP -> OFF produced 425 values: 0 -> 1 -> 2 -> 4 -> 0
- Exhaust/supply ratio edit (capture: ratio_test_100_90_80_100.pcapng):
  - FC06 writes observed at 426 with values 90, 80, and 100 during manual ratio edits
- CA airflow setpoints edit (capture: Wan live write monitor):
  - FC06 writes observed at 427, 428, 429 while changing CA supply setpoints 200/400/600 to 100/200/300 and back
- LS analog scaling / airflow edit (captures: ls_vmin_vmax_mapping_live.pcapng, ls_vmin_only_clean.pcapng):
  - 437 = LS_VMIN with 0.1 V scaling; 0.9 V produced raw value 9
  - 438 = LS_VMAX with 0.1 V scaling; 9.5 V and 10.0 V produced raw values 95 and 100
  - 439 = LS_AIRFLOW_AT_VMIN; observed writes included 100 and 150
  - 440 = LS_AIRFLOW_AT_VMAX; observed writes included 800 and 840
- LS stop-threshold controls (capture: ls_stop_thresholds_confirm.pcapng):
  - 500 = LS_STOP_IF_BELOW_VLOW; observed 1/0 toggle writes
  - 501 = LS_VLOW with 0.1 V scaling; observed raw values 5 and 0
  - 502 = LS_STOP_IF_ABOVE_VHIGH; observed 1/0 toggle writes
  - 503 = LS_VHIGH with 0.1 V scaling; observed raw values 95 and 100
- LS K3 mode / sleep factor (capture: ls_k3_modes_live.pcapng):
  - 504/583 moved during `No -> Exhaust -> Supply -> No`; best-fit interpretation is 504 = K3 0-10V enable and 583 = Exhaust/Supply selector
  - 441 carried K3 sleep-factor edits in `No` mode; observed final writes included 90 and 100
  - 426 remained the shared ratio register across K3 modes
  - Eole emitted intermediate artifact writes before final values: 426=5 ahead of ratio updates, 441=1 ahead of sleep-factor updates
- LS K3 mode final confirmation (capture: ls_k3_mode_confirm.pcapng):
  - No -> Exhaust -> No produced 504=1, 583=0, then 504=0
  - No -> Supply -> No produced 504=1, 583=1, then 504=0
- CP `CP on` selector (capture: cp_on_mapping_20260628_live.pcapng):
  - Supply -> Exhaust -> Supply / Exhaust -> Supply produced writes 442=1, 442=2, 442=0
  - Best-fit interpretation is 442 = CP_ON_MODE with 0 = Supply, 1 = Exhaust, 2 = Supply / Exhaust
- CP voltage fields (captures: cp_supply_voltage_only_20260628_live.pcapng, cp_exhaust_voltage_only_20260628_live.pcapng, cp_supply_exhaust_mode_validation_20260628_live.pcapng):
  - 445 carries the CP voltage field in single-side mode and the Supply voltage field in Supply / Exhaust mode; observed writes included 5 and 9
  - 448 carries the Exhaust voltage field in Supply / Exhaust mode; observed writes included 9 and 0
- CP airflow start setpoint (capture: cp_pressure_start_combo_20260628_live.pcapng):
  - 253 received a write of 10, then returned to 0 automatically; likely the Airflow-mode `Start` setpoint field

## Observed runtime behavior

- The app writes preset changes as a two-step command: 199=0, then 202=<1|2|3>.
- The app writes bypass as a single FC06 command to register 222.
- The app writes boost as a single FC06 command to register 227.
- The exhaust/supply ratio behaves as a shared/global parameter across modes rather than a CA-only value.
- The Eole/TACTouch UI can emit intermediate artifact writes while editing LS/K3 fields; current evidence suggests these are UI side effects, not values the app should intentionally mirror.
- The CP `CP on` field is separate from the LS K3 `504/583` pair; CP uses register 442.
- The CP `Pressure / Airflow` selector still has no confirmed standalone write; current evidence suggests it may only affect how other CP fields are interpreted or when writes are committed.
- The app is currently behaving well for manual settings; the remaining uncertainty is focused on selector-style fields rather than the already-mapped manual parameter writes.

## Open questions

- Whether 52 is strictly the active preset index or a broader working mode selector.
- Whether register 52 mirrors active preset for all firmware variants.
- Whether Boost is a dedicated mode bit or an alternate setpoint profile.
- What OPERATION_MODE value 3 means (currently unobserved; planned experiment).
