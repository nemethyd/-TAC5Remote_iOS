# TAC5 Register Map

This is a working reference for the TAC5 / EOLE 4 Modbus map.

Important indexing note:

- The live Modbus reads in this repo use 0-based holding register offsets.
- The vendor-style document addresses use 41xxx/42xxx references.
- Both forms are listed below so the map is easier to cross-check.

## Confidence legend

- confirmed: directly verified from capture and/or stable readback behavior
- likely confirmed: repeatedly observed, but vendor mapping is still not formally verified
- doc-confirmed: explicitly documented in vendor TAC5 Modbus table, not yet fully capture-verified on this unit

Ordering principle for the table below:

- rows are sorted in ascending order by document address (`raw offset + 40001`), matching the layout used in `docs/TAC5_MODBUS_TABLE_SUMMARY.md`
- rows tagged `[vendor §x.y]` in the Notes column have an explicit, matching entry in `docs/TAC5_MODBUS_TABLE_SUMMARY.md` at that section; untagged rows are either undocumented gaps or were only confirmed by capture/live-probe evidence
- a previous duplicate entry for raw offset `253` / `40254` (`INITIALIZATION_FLOW_1` and `CP_START_AIRFLOW`) has been merged into a single row, since both referred to the same register and the same observed write-10-then-reset-to-0 behavior
- `LS_K3_TARGET_SIDE` document address was corrected from `TBD` to `40584` (`raw 583 + 40001`)

| Key | Raw offset | Document address | Access | Type | Scale | Unit | Status | Notes |
| --- | --- | --- | --- | --- | --- | --- | --- | --- |
| SWEGON_MAGIC_SIGNATURE | 0..1 | 40001..40002 | ro | ascii4/uint32 | - | - | confirmed | `[vendor §4.1]` live read returned words `19533/20051`, which decode to `LMNS`, or `1314081869` if read as a single 32-bit value |
| PRODUCT_CID | 2 | 40003 | ro | uint16 | 1 | - | confirmed | `[vendor §4.1]` Swegon product identification code number (CID); live read on current unit returned `26002` |
| MODBUS_MAP_VERSION | 3 | 40004 | ro | uint16 | 1 | version | confirmed | `[vendor §4.1]` encoded as `major * 100 + minor`; live read on current unit returned `20` |
| SW_VERSION_MAJOR | 4 | 40005 | ro | uint16 | 1 | version | confirmed | `[vendor §4.1]` software version major component; live read on current unit returned `4` |
| SW_VERSION_MINOR | 5 | 40006 | ro | uint16 | 1 | version | confirmed | `[vendor §4.1]` software version minor component; live read on current unit returned `1` |
| SW_VERSION_REVISION | 6 | 40007 | ro | uint16 | 1 | version | confirmed | `[vendor §4.1]` software version revision component; live read on current unit returned `2` |
| CONTROLLER_RESET_FLAG | 7 | 40008 | rw | uint16 | 1 | bool-like | confirmed | `[vendor §4.1]` latched reset indicator; after the mural reboot live read returned `1`, and writing `0` cleared it immediately without visible side effects |
| SW_BUILD_NUMBER | 8 | 40009 | ro | uint16 | 1 | build | confirmed | `[vendor §4.1]` software build number; live read on current unit returned `2890` |
| UNIT_NAME_ASCII | 9..16 | 40010..40017 | rw | ascii16 | - | text | confirmed | `[vendor §4.1]` unit name stored as eight 2-character alphanumeric ASCII registers (`40010` = chars 1-2, ..., `40017` = chars 15-16); live FC06 writes stored `Moderato`, and a later factory reset cleared the block back to zeros |
| UNKNOWN_40018 | 17 | 40018 | ro | uint16 | 1 | - | confirmed | undocumented in the vendor table; live read returned `0`, and FC06 write-back of the same value was rejected with Modbus exception code `2` |
| UNKNOWN_40019 | 18 | 40019 | ro | uint16 | 1 | - | confirmed | undocumented in the vendor table; live read returned `0`, and FC06 write-back of the same value was rejected with Modbus exception code `2` |
| REC_TYPE_CONFIGURATION | 19..20 | 40020..40021 | ro | uint32 | - | - | confirmed | factory configuration `REC TYPE`; live read returned words `32305/13` |
| PREHEAT_OPTION | 21 | 40022 | ro | uint16 | 1 | enum | confirmed | vendor `0=OFF, 1=ON-KWin`; live read returned `0` |
| POSTHEAT_OPTION | 22 | 40023 | ro | uint16 | 1 | enum | confirmed | vendor `0=OFF, 1=ON-KWout, 2=ON-NV`; live read returned `0` |
| CT_IN_DAMPER_OPTION | 23 | 40024 | ro | uint16 | 1 | bool-like | confirmed | factory damper option; vendor `0=NO, 1=YES`; live read returned `0` |
| PROPORTIONAL_BYPASS_OPTION | 24 | 40025 | ro | uint16 | 1 | bool-like | confirmed | vendor `BYPASS%` factory flag for proportional bypass; live read returned `0` |
| BACKWARD_FANS_OPTION | 25 | 40026 | ro | uint16 | 1 | bool-like | confirmed | vendor `Has Backward fans?`; live read returned `0` |
| HEAT_WHEEL_OPTION | 26 | 40027 | ro | uint16 | 1 | bool-like | confirmed | vendor `Has Heat wheel?`; live read returned `0` |
| FACTORY_TQ_MODE_OPTION | 27 | 40028 | ro | uint16 | 1 | bool-like | confirmed | vendor `Mode TQ?`; live read returned `0` |
| CAISSON_MK3_OPTION | 28 | 40029 | ro | uint16 | 1 | bool-like | confirmed | vendor `Caisson MK3?`; live read returned `0` |
| HEAT_WHEEL_RPM_AT_10V | 29 | 40030 | ro | uint16 | 1 | rpm_like | confirmed | vendor range `5..40`; current unit returned `0`, consistent with no heat-wheel option enabled |
| BACKWARD_FANS_HAVE_SENSOR | 30 | 40031 | ro | uint16 | 1 | bool-like | confirmed | vendor `Backward fans have sensor?`; live read returned `0` |
| RESERVED_40032_40049 | 31..48 | 40032..40049 | ro | block | - | - | confirmed | vendor 4.2.1 table leaves this range undescribed; live read after factory reset returned all zeros |
| FAN_TYPE_CONFIGURATION | 49..50 | 40050..40051 | ro | uint32 | - | - | confirmed | vendor `FAN TYPE`; live read returned words `32304/13` |
| CURRENT_WORKING_MODE | 51 | 40052 | ro | uint16 | 1 | enum | confirmed | `[vendor §4.2.1]` vendor `0=OFF, 1=CA, 2=LS, 4=CPs, 5=CAs, 6=TQ, 9=INIT`; live read returned `1` = CA |
| CURRENT_SPEED_POSITION | 52 | 40053 | ro | uint16 | 1 | enum | confirmed | `[vendor §4.2.1]` vendor `0=STOP, 1=LOW/I, 2=MEDIUM/II, 3=HIGH/III`; live read returned `3` = HIGH / III |
| CURRENT_SETPOINT_VALUE | 53 | 40054 | ro | uint16 | 1 | dynamic | confirmed | `[vendor §4.2.1]` current setpoint value; live read returned `600`; interpret using `CURRENT_SETPOINT_UNIT` |
| CURRENT_SETPOINT_UNIT | 54 | 40055 | ro | uint16 | 1 | enum | confirmed | `[vendor §4.2.1]` vendor `0=m3/h, 1=Pa, 2=0.1V, 3=%TQ`; live read returned `0` = m3/h |
| CURRENT_SETPOINT_SUPPLY | 55 | 40056 | ro | uint16 | 1 | dynamic | confirmed | `[vendor §4.2.1]` current setpoint for supply fans F1/F2; live read returned `600` |
| CURRENT_SETPOINT_EXHAUST | 56 | 40057 | ro | uint16 | 1 | dynamic | confirmed | `[vendor §4.2.1]` current setpoint for extraction fans F3/F4; live read returned `600` |
| PREHEAT_SETPOINT | 57 | 40058 | ro | int16 | 0.1 | C | confirmed | vendor preheat setpoint display register; live read returned `10` = `1.0 C` |
| CURRENT_COMFORT_SETPOINT | 58 | 40059 | ro | uint16 | 0.1 | C | confirmed | `[vendor §4.2.1]` TAC5 SC current comfort temperature setpoint; live read returned `0`, meaning heating/cooling comfort control currently OFF |
| F2_F1_UNBALANCE_PERCENT | 59 | 40060 | ro | uint16 | 1 | percent | confirmed | current F2/F1 imbalance percentage; live read returned `100`, indicating balanced 100% |
| FAN1_PRESSURE_ALARM_REF_FLOW | 60 | 40061 | ro | uint16 | 1 | m3_h | confirmed | vendor pressure-alarm reference flow for fan 1; live read returned `0` |
| FAN1_PRESSURE_ALARM_REF_PRESSURE | 61 | 40062 | ro | uint16 | 1 | Pa | confirmed | vendor pressure-alarm reference pressure for fan 1; live read returned `1000` |
| FAN2_PRESSURE_ALARM_REF_FLOW | 62 | 40063 | ro | uint16 | 1 | m3_h | confirmed | vendor pressure-alarm reference flow for fan 2; live read returned `0` |
| FAN2_PRESSURE_ALARM_REF_PRESSURE | 63 | 40064 | ro | uint16 | 1 | Pa | confirmed | vendor pressure-alarm reference pressure for fan 2; live read returned `1000` |
| FAN1_FLOW_OR_TORQUE | 64 | 40065 | ro | uint16 | 1 | dynamic | confirmed | `[vendor §4.2.1]` actual fan 1 / supply 1 flow or torque display register; live read returned `599` |
| FAN1_PRESSURE | 65 | 40066 | ro | uint16 | 1 | Pa_like | confirmed | `[vendor §4.2.1]` actual fan 1 pressure display register; live read returned `567` |
| FAN1_SENT_TORQUE | 66 | 40067 | ro | uint16 | 1 | raw255 | confirmed | vendor sent-torque register where `127` is `50%`; live read returned `144` |
| FAN1_RPM | 67 | 40068 | ro | uint16 | 1 | rpm | confirmed | `[vendor §4.2.1]` actual fan 1 RPM; live read returned `1885` |
| FAN2_FLOW_OR_TORQUE | 68 | 40069 | ro | uint16 | 1 | dynamic | confirmed | actual fan 2 / supply 2 flow or torque display register; live read returned `0` |
| FAN2_PRESSURE | 69 | 40070 | ro | uint16 | 1 | Pa_like | confirmed | actual fan 2 pressure display register; live read returned `0` |
| FAN2_SENT_TORQUE | 70 | 40071 | ro | uint16 | 1 | raw255 | confirmed | vendor sent-torque register for fan 2; live read returned `0` |
| FAN2_RPM | 71 | 40072 | ro | uint16 | 1 | rpm | confirmed | actual fan 2 RPM; live read returned `0` |
| FAN3_FLOW_OR_TORQUE | 72 | 40073 | ro | uint16 | 1 | dynamic | confirmed | `[vendor §4.2.1]` actual fan 3 / exhaust 1 flow or torque display register; live read returned `597` |
| FAN3_PRESSURE | 73 | 40074 | ro | uint16 | 1 | Pa_like | confirmed | `[vendor §4.2.1]` actual fan 3 pressure display register; live read returned `566` |
| FAN3_SENT_TORQUE | 74 | 40075 | ro | uint16 | 1 | raw255 | confirmed | vendor sent-torque register for fan 3; live read returned `143` |
| FAN3_RPM | 75 | 40076 | ro | uint16 | 1 | rpm | confirmed | actual fan 3 RPM; live read returned `1878` |
| FAN4_FLOW_OR_TORQUE | 76 | 40077 | ro | uint16 | 1 | dynamic | confirmed | actual fan 4 / exhaust 2 flow or torque display register; live read returned `0` |
| FAN4_PRESSURE | 77 | 40078 | ro | uint16 | 1 | Pa_like | confirmed | actual fan 4 pressure display register; live read returned `0` |
| FAN4_SENT_TORQUE | 78 | 40079 | ro | uint16 | 1 | raw255 | confirmed | vendor sent-torque register for fan 4; live read returned `0` |
| FAN4_RPM | 79 | 40080 | ro | uint16 | 1 | rpm | confirmed | actual fan 4 RPM; live read returned `0` |
| UNIT_RUNTIME_HOURS | 80..81 | 40081..40082 | ro | uint32 | 1 | h | confirmed | `[vendor §4.2.1]` vendor 32-bit RUN TIME counter; live read returned words `0/0` |
| INTEGRATED_ANTIFREEZE_STATUS | 82 | 40083 | ro | uint16 | 1 | enum | confirmed | vendor integrated exchanger antifreeze status; `0=OFF, 1=air-air exchanger active, 2=warm-water exchanger active`; live read returned `0` |
| BYPASS_STATUS | 83 | 40084 | ro | uint16 | 1 | enum | confirmed | `[vendor §4.2.1]` vendor bypass status; `0=CLOSED, 1=OPEN, 2=PARTIALLY OPEN`; live read returned `0` |
| CTIN_DAMPER_STATUS | 84 | 40085 | ro | uint16 | 1 | enum | confirmed | vendor CTin damper status; `0=CLOSED/CLOSING, 1=OPENING, 2=OPEN`; live read returned `0` |
| POST_VENTILATION_STATUS | 85 | 40086 | ro | uint16 | 1 | bool-like | confirmed | vendor post-ventilation status; `0=NO, 1=active`; live read returned `0` |
| CURRENT_CONTROL_MODE_SOURCE | 86 | 40087 | ro | uint16 | 1 | enum | confirmed | `[vendor §4.2.1]` vendor control-source indicator; `1=Fatal error, 2=Fire, 3=RC, 4=External contacts, 5=RC scheduler, 6=Modbus/GRC scheduler, 7=Modbus 40201, 8=Bypass, 9=Boost, 10=Modbus 40204/40205, 11=KNX`; live read returned `3` = RC |
| EXTERNAL_ANTIFREEZE_STATUS | 87 | 40088 | ro | uint16 | 1 | enum | confirmed | vendor external exchanger antifreeze status; `0=OFF, 1=BA+ active, 2=BA- active, 3=BA+ and BA- active`; live read returned `0` |
| CURRENT_COMFORT_HEATING_SETPOINT | 88 | 40089 | ro | uint16 | 0.1 | C | confirmed | vendor current comfort heating setpoint display register; live read returned `0`, meaning heating OFF |
| CURRENT_COMFORT_COOLING_SETPOINT | 89 | 40090 | ro | uint16 | 0.1 | C | confirmed | vendor current comfort cooling setpoint display register; live read returned `0`, meaning cooling OFF; same-value FC06 write-back was rejected with Modbus exception code `2`, consistent with read-only access |
| BYPASS_VALVE_POSITION | 90 | 40091 | ro | uint16 | 1 | percent | confirmed | vendor bypass valve position; live read returned `0`, consistent with closed bypass |
| HEAT_WHEEL_RPM_LIVE | 91 | 40092 | ro | uint16 | 1 | rpm | confirmed | live heat-wheel RPM display register; live read returned `0` |
| UNKNOWN_40093_40094 | 92..93 | 40093..40094 | ro | block | - | - | confirmed | vendor table leaves this pair undocumented; live reads returned `0/0`; same-value FC06 write-back on both registers was rejected with Modbus exception code `2` |
| MK3_STATE | 94 | 40095 | ro | uint16 | 1 | enum | confirmed | vendor MK3 state; `0=CLOSED, 1=OPEN, 2=OPENING, 3=CLOSING`; live read returned `0` |
| MINOR_MAINTENANCE_HOURS | 95..96 | 40096..40097 | ro | uint32 | 1 | h | confirmed | vendor 32-bit minor-maintenance hours counter starting at `40096`; live read returned words `0/0`; same-value FC06 probe on companion word `40097` was rejected with Modbus exception code `2` |
| CHANGEOVER_STATUS | 97 | 40098 | ro | uint16 | 1 | enum | confirmed | vendor changeover status; `0=inactive, 1=heating, 2=cooling`; live read returned `0` |
| DEFROST_STATE | 98 | 40099 | ro | uint16 | 1 | enum | confirmed | vendor defrost state; `0=IDLE, 1=ACTIVE, 2=STOP to drain water`; live read returned `0` |
| UNKNOWN_40100 | 99 | 40100 | ro | uint16 | 1 | - | confirmed | vendor table leaves this register undocumented; live read returned `0`, and same-value FC06 write-back was rejected with Modbus exception code `2` |
| UNKNOWN_40101_40103 | 100..102 | 40101..40103 | ro | block | - | - | confirmed | vendor table leaves this range undocumented; live reads returned `0/0/0`; same-value FC06 write-back on each sampled register in the range was rejected with Modbus exception code `2` |
| DELTA_SUPPLY_PA_ALARM_PERCENT | 103 | 40104 | ro | uint16 | 1 | percent | confirmed | vendor delta supply pressure alarm percentage; live read returned `0`; same-value FC06 write-back was rejected with Modbus exception code `2`, consistent with read-only access |
| DELTA_EXHAUST_PA_ALARM_PERCENT | 104 | 40105 | ro | uint16 | 1 | percent | confirmed | vendor delta exhaust pressure alarm percentage; live read returned `0` |
| UNKNOWN_40106_40108 | 105..107 | 40106..40108 | ro | block | - | - | confirmed | vendor table leaves this range undocumented; live reads returned `0/0/0`; same-value FC06 write-back on each sampled register in the range was rejected with Modbus exception code `2` |
| MAJOR_MAINTENANCE_HOURS | 108..109 | 40109..40110 | ro | uint32 | 1 | h | confirmed | vendor 32-bit major-maintenance hours counter; live read returned words `0/0`; same-value FC06 write-back at `40109` was rejected with Modbus exception code `2`, consistent with read-only access |
| UNKNOWN_40111_40149 | 110..148 | 40111..40149 | ro | block | - | - | confirmed | vendor table leaves this range undocumented; live sweep returned all zeros across the full range; sampled same-value FC06 write-back at `40111` was rejected with Modbus exception code `2` |
| DIGITAL_INPUT_STATUS_BLOCK0 | 149 | 40150 | ro | bitmap16 | 1 | bitfield | confirmed | vendor digital-input status word; live read returned `4096`, which corresponds to bit 12 set if interpreted as an LSB-first bitmap (`IN10`, SATBA post-cooling OFF) |
| UNKNOWN_40151 | 150 | 40151 | ro | uint16 | 1 | - | confirmed | vendor table leaves this register undocumented; live read returned `0`, and same-value FC06 write-back was rejected with Modbus exception code `2` |
| K1_ANALOG_VOLTAGE | 151 | 40152 | ro | uint16 | 0.1 | V | confirmed | vendor K1 analog voltage display register (`0..100` => `0.0..10.0 V`); live read returned `0` |
| K2_ANALOG_VOLTAGE | 152 | 40153 | ro | uint16 | 0.1 | V | confirmed | vendor K2 analog voltage display register (`0..100` => `0.0..10.0 V`); live read returned `0` |
| K3_ANALOG_VOLTAGE | 153 | 40154 | ro | uint16 | 0.1 | V | confirmed | vendor K3 analog voltage display register (`0..100` => `0.0..10.0 V`); live read returned `0` |
| T1 | 154 | 40155 | ro | int16 | 0.1 | C | confirmed | `[vendor §4.2.1]` current live sweep returned `249` = `24.9 C` |
| T2 | 155 | 40156 | ro | int16 | 0.1 | C | confirmed | `[vendor §4.2.1]` current live sweep returned `256` = `25.6 C` |
| T3 | 156 | 40157 | ro | int16 | 0.1 | C | confirmed | `[vendor §4.2.1]` current live sweep returned `248` = `24.8 C` |
| T4 | 157 | 40158 | ro | int16 | 0.1 | C | confirmed | distinct T4 register (Water coil temperature, NV option); current live sweep returned `64537` = signed `-999`, so it is separate from T7 and currently behaves like a missing/open-circuit sentinel on this unit/configuration |
| T5 | 158 | 40159 | ro | int16 | 0.1 | C | confirmed | `[vendor §4.2.1]` current live sweep returned `154` = `15.4 C` |
| UNKNOWN_40160 | 159 | 40160 | ro | int16 | 0.1 | C_like | confirmed | vendor table leaves this register undocumented; live read returned `64537` = signed `-999`, so this appears to be another temperature-region sentinel/gap; same-value FC06 write-back was rejected with Modbus exception code `2` |
| T7 | 160 | 40161 | ro | int16 | 0.1 | C | confirmed | current live sweep returned `260` = `26.0 C`; earlier post-factory-reset read returned `237` = `23.7 C`; the sensor value remained present in Modbus even when the local visualization no longer showed T7; user confirmed the local UI diagram that contains T7 appears when the `SAT BA` selector is anything other than `None` |
| T8 | 161 | 40162 | ro | int16 | 0.1 | C | confirmed | current live sweep returned `64537` = signed `-999`, which behaves like an open-circuit / not-present sentinel on this unit/configuration |
| BACKWARD_FANS_DP_INPUT_PR1_SCALED | 162 | 40163 | ro | uint16 | 0.1 | V | confirmed | vendor backward-fans inlet differential-pressure analogue input PR1 (`0..100` => `0.0..10.0 V`); live read returned `0` |
| BACKWARD_FANS_DP_INPUT_PR2_SCALED | 163 | 40164 | ro | uint16 | 0.1 | V | confirmed | vendor backward-fans inlet differential-pressure analogue input PR2 (`0..100` => `0.0..10.0 V`); live read returned `0` |
| BACKWARD_FANS_DP_INPUT_PR1_RAW | 164 | 40165 | ro | uint16 | 1 | raw16383 | confirmed | vendor backward-fans inlet differential-pressure raw analogue input PR1 (`0..16383` => `0.0..10.0 V`); live read returned `0` |
| BACKWARD_FANS_DP_INPUT_PR2_RAW | 165 | 40166 | ro | uint16 | 1 | raw16383 | confirmed | vendor backward-fans inlet differential-pressure raw analogue input PR2 (`0..16383` => `0.0..10.0 V`); live read returned `0` |
| UNKNOWN_40167 | 166 | 40167 | ro | uint16 | 1 | - | confirmed | vendor table leaves this register undocumented; live read returned `0`, and same-value FC06 write-back was rejected with Modbus exception code `2` |
| DIGITAL_OUTPUT_STATUS_BLOCK0 | 167 | 40168 | ro | bitmap16 | 1 | bitfield | confirmed | vendor digital-output status word; live read returned `1217`, which corresponds to bits `0`, `6`, `7`, and `10` set if interpreted as an LSB-first bitmap |
| DIGITAL_OUTPUT_STATUS_BLOCK1 | 168 | 40169 | ro | bitmap16 | 1 | bitfield | confirmed | vendor second digital-output status word for `OUT1..OUT5`; live read returned `0` |
| ANALOG_OUTPUT_OUT1 | 169 | 40170 | ro | uint16 | 0.1 | V | confirmed | vendor OUT1 analogue output image (`0..100` => `0.0..10.0 V`); live read returned `0` |
| ANALOG_OUTPUT_OUT2 | 170 | 40171 | ro | uint16 | 0.1 | V | confirmed | vendor OUT2 analogue output image (`0..100` => `0.0..10.0 V`); live read returned `0` |
| ANALOG_OUTPUT_OUT4_NV | 171 | 40172 | ro | uint16 | 0.1 | V | confirmed | vendor OUT4 analogue output image for post-heat NV valve (`0..100` => `0.0..10.0 V`); live read returned `100` = `10.0 V` |
| UNKNOWN_40173 | 172 | 40173 | ro | uint16 | 1 | - | confirmed | vendor table leaves this register undocumented; live read returned `0`, and same-value FC06 write-back was rejected with Modbus exception code `2` |
| ANALOG_OUTPUT_OUT7_BA_PLUS | 173 | 40174 | ro | uint16 | 0.1 | V | confirmed | vendor OUT7 analogue output image for post-heat/cool BA+ or BA+/- valve (`0..100` => `0.0..10.0 V`); live read returned `0` |
| ANALOG_OUTPUT_OUT8_BA_MINUS | 174 | 40175 | ro | uint16 | 0.1 | V | confirmed | vendor OUT8 analogue output image for post-cool BA- valve (`0..100` => `0.0..10.0 V`); live read returned `0` |
| UNKNOWN_40176_40185 | 175..184 | 40176..40185 | ro | block | - | - | confirmed | vendor table leaves this range undocumented; live sweep returned all zeros across the full range |
| OUTPUT_KWIN_PERCENT | 185 | 40186 | ro | uint16 | 1 | percent | confirmed | vendor preheat KWin output power; live read returned `0` |
| OUTPUT_KWOUT_PERCENT | 186 | 40187 | ro | uint16 | 1 | percent | confirmed | vendor post-heat KWout output power; live read returned `0` |
| OUTPUT_EXTERNAL_KW_PERCENT | 187 | 40188 | ro | uint16 | 1 | percent | confirmed | vendor external SAT BA/KW output power; live read returned `0` |
| HEAT_WHEEL_MEASURED_RPM | 188 | 40189 | ro | uint16 | 0.1 | rpm | confirmed | vendor heat-wheel measured RPM (`0..300` => `0.0..30.0 RPM`); live read returned `0` |
| CP_SUPPLY_PRESSURE_MEASURED | 189 | 40190 | ro | uint16 | 1 | Pa | confirmed | vendor Modbus-sensor pressure for supply fan in CP mode; live read returned `0` |
| CP_EXHAUST_PRESSURE_MEASURED | 190 | 40191 | ro | uint16 | 1 | Pa | confirmed | vendor Modbus-sensor pressure for exhaust fan in CP mode; live read returned `0` |
| UNKNOWN_40192_40199 | 191..198 | 40192..40199 | ro | block | - | - | confirmed | vendor table leaves this range undocumented; live sweep returned all zeros across the full range; sampled same-value FC06 write-back at `40192` and `40199` was rejected with Modbus exception code `2` |
| CONTROL_MASTER_SELECT | 199 | 40200 | rw | uint16 | 1 | enum | confirmed | `[vendor §4.2.2]` vendor control-master selector; live read returned `0` = RC TAC5; captures showed `40200=2` when switching to schedule/timetable and `40200=0` when returning to manual/RC control |
| MODBUS_SPEED_SELECT | 200 | 40201 | rw | uint16 | 1 | enum | likely confirmed | `[vendor §4.2.2]` vendor Modbus speed selector used only if `40200=1`; live read returned `0` and a companion `40201=0` write was observed when switching from schedule back to manual/RC |
| UNKNOWN_40202 | 201 | 40202 | rw? | uint16 | 1 | - | confirmed | vendor control section leaves this register undocumented; current live read returned `0`; not write-probed because this is a live control block with potential side effects |
| PRESET_STATE | 202 | 40203 | rw | uint16 | 1 | enum | confirmed | undocumented but capture-confirmed preset selector/state; live read returned `3` = K3; isolated preset transitions showed writes `1/2/3` for K1/K2/K3 after forcing `40200=0` |
| MODBUS_SUPPLY_FLOW_SETPOINT | 203 | 40204 | rw | uint16 | 1 | dynamic | confirmed | `[vendor §4.2.2]` vendor supply airflow/torque selection via Modbus when `40200=3`; current live read returned `0` |
| MODBUS_EXHAUST_FLOW_SETPOINT | 204 | 40205 | rw | uint16 | 1 | dynamic | confirmed | `[vendor §4.2.2]` vendor exhaust airflow/torque selection via Modbus when `40200=3`; current live read returned `0` |
| UNKNOWN_40206_40220 | 205..219 | 40206..40220 | rw? | block | - | - | confirmed | vendor control section leaves this range undocumented; live sweep returned all zeros; not write-probed because hidden control functions here could have side effects |
| EXTERNAL_PRESSURE_ALARM_FORCE | 220 | 40221 | rw | uint16 | 1 | bool-like | confirmed | vendor external pressure alarm forcing status; live read returned `0` = no alarm |
| FIRE_ALARM_FORCE_STATUS | 221 | 40222 | rw | uint16 | 1 | bool-like | confirmed | `[vendor §4.2.2]` vendor fire-alarm forcing status; live read returned `0` = no alarm |
| BYPASS_ENABLE | 222 | 40223 | rw | uint16 | 1 | enum-like | confirmed | `[vendor §4.2.2]` vendor bypass override register; live read returned `0` = auto; observed app usage writes `0/1`, and vendor also defines `2 = force close` |
| FORCE_AUTOMATIC_MODE | 223 | 40224 | rw | uint16 | 1 | bool-like | confirmed | vendor override for automatic mode; live read returned `0` |
| POSTHEAT_DISABLE | 224 | 40225 | rw | uint16 | 1 | bool-like | confirmed | `[vendor §4.2.2]` vendor ON/OFF post-heat deactivation register; live read returned `0` = post-heating allowed |
| FIRE_ALARM_SUPPLY_RUN | 225 | 40226 | rw | uint16 | 1 | bool-like | confirmed | vendor fire-alarm supply-fan behavior; live read returned `0` = stop supply fan in fire alarm |
| FIRE_ALARM_EXHAUST_RUN | 226 | 40227 | rw | uint16 | 1 | bool-like | confirmed | vendor fire-alarm exhaust-fan behavior; live read returned `0` = stop exhaust fan in fire alarm |
| BOOST_ENABLE | 227 | 40228 | rw | uint16 | 1 | bool-like | confirmed | `[vendor §4.2.2]` vendor boost control register; live read returned `0`; FC06 writes `1/0` were previously confirmed as Boost on/off |
| POSTCOOL_DISABLE | 228 | 40229 | rw | uint16 | 1 | bool-like | confirmed | vendor ON/OFF post-cool deactivation register; live read returned `0` = cooling allowed |
| SAT_BA_HEAT_COOL_SELECT | 229 | 40230 | rw | uint16 | 1 | bool-like | confirmed | vendor SAT BA heating/cooling selector; `0=heating position`, `1=cooling position`; live read returned `0` |
| FORCE_MK3_ACTIVE | 230 | 40231 | rw | uint16 | 1 | bool-like | confirmed | vendor MK3 force-active override; live read returned `0` |
| UNKNOWN_40232_40249 | 231..248 | 40232..40249 | rw? | block | - | - | confirmed | vendor control section leaves this range undocumented; live sweep returned all zeros; not write-probed because this is a live control block |
| RESET_CONTROLLER | 249 | 40250 | rw | uint16 | 1 | trigger | confirmed | `[vendor §4.2.2]` vendor reset register to clear pending alarms and resume normal work; live read returned `0`; a real write `1` was tested live and immediately caused a Modbus exception (fc03 code 6) and a brief (~1.5 min) unavailable window before communication recovered, confirming this is a genuine reset trigger (see `captures/reset_controller_probe_40250_trigger.csv` and `captures/reset_controller_probe_40250_recovery_check.csv`) |
| RESET_FACTORY_DEFAULTS | 250 | 40251 | rw | uint16 | 1 | trigger | confirmed | `[vendor §4.2.2]` vendor factory-reset register; live read returned `0`; write `1` triggers factory default reset |
| RESET_RUNTIME_HOURS | 251 | 40252 | rw | uint16 | 1 | trigger | confirmed | vendor run-time-hours reset register; live read returned `0` |
| PRESSURE_ALARM_INITIALIZATION_START | 252 | 40253 | rw | uint16 | 1 | trigger | confirmed | vendor pressure-alarm initialization trigger; live read returned `0` = idle |
| INITIALIZATION_FLOW_1 | 253 | 40254 | rw | uint16 | 1 | dynamic | confirmed | `[vendor §3.2 CPs Mode]` vendor reference flow/torque 1 used by pressure-alarm initialization and by the CP-mode start airflow setpoint (also referred to as `CP_START_AIRFLOW` in earlier notes for this same register/behavior); live read returned `0`; isolated capture (`cp_pressure_start_combo_20260628_live.pcapng`) showed a transient write `10` followed by an automatic reset back to `0` |
| CPF_MODE_INITIALIZATION_START | 254 | 40255 | rw | uint16 | 1 | trigger | doc-confirmed | `[vendor §4.3.2, §3.2 CPs Mode]` vendor CPf-mode initialization trigger; current live read returned `0` |
| CPS_MODE_INITIALIZATION_START | 255 | 40256 | rw | uint16 | 1 | trigger | doc-confirmed | `[vendor §3.2 CPs Mode]` vendor CPs-mode initialization trigger; current live read returned `0` |
| INITIALIZATION_FLOW_2 | 256 | 40257 | rw | uint16 | 1 | dynamic | doc-confirmed | `[vendor §3.2 CPs Mode]` vendor reference flow 2 used by CPs SUP+EXH initialization; current live read returned `0` |
| FORCE_PROPORTIONAL_BYPASS_POSITION | 257 | 40258 | rw | int16 | 1 | percent | doc-confirmed | vendor proportional-bypass override; `-1 = no override`, `0..100 = forced position`; current live read returned `0` |
| FORCE_HEAT_WHEEL_RPM | 258 | 40259 | rw | int16 | 1 | rpm_like | doc-confirmed | vendor heat-wheel RPM override; `-1 = no override`, other values force RPM; current live read returned `0` |
| RESET_MINOR_MAINTENANCE_HOURS | 259 | 40260 | rw | uint16 | 1 | trigger | doc-confirmed | vendor minor-maintenance-hours reset register; current live read returned `0` |
| RESET_MAJOR_MAINTENANCE_HOURS | 260 | 40261 | rw | uint16 | 1 | trigger | confirmed | vendor major-maintenance-hours reset register; current live read returned `0` |
| UNKNOWN_40262_40299 | 261..298 | 40262..40299 | rw? | block | - | - | confirmed | no vendor row found in the current extract for this range; live sweep returned all zeros; not write-probed because these addresses sit in the live control block |
| ALARM_BITMAP_0 | 299 | 40300 | ro | bitmap16 | 1 | bitfield | confirmed | `[vendor §4.2.3]` vendor alarm bitmap word; live read returned `0`; bits `0..15` cover program/data/fan/pressure and T1..T4 open/short alarms |
| ALARM_BITMAP_1 | 300 | 40301 | ro | bitmap16 | 1 | bitfield | confirmed | vendor table does not spell out this word's bit layout; live read returned `64` (bit `6` set), stable across three repeated reads one second apart; same-value FC06 write-back was rejected with Modbus exception code `2`, consistent with read-only access; bit-level meaning not yet mapped to a named alarm |
| ALARM_BITMAP_2 | 301 | 40302 | ro | bitmap16 | 1 | bitfield | confirmed | vendor table does not spell out this word's bit layout; live read returned `0` |
| ALARM_BITMAP_3 | 302 | 40303 | ro | bitmap16 | 1 | bitfield | confirmed | `[vendor §4.2.3]` vendor alarm bitmap word; live read returned `0`; bits `4..5`=Maintenance Warn/Fatal, bit `6`=DPA (Diff Pressure Alarm), bit `7`=Fire Alarm |
| UNKNOWN_40304_40399 | 303..398 | 40304..40399 | ro | block | - | - | confirmed | vendor table leaves this range undocumented beyond the general `40300...` "Alarms / Read only" heading; live sweep returned all zeros across the full range; sampled same-value FC06 write-back at `40350` was rejected with Modbus exception code `2`, consistent with read-only access |
| RTC_SECONDS | 399 | 40400 | rw | uint16 | 1 | s | confirmed | `[vendor §4.2.4]` current time seconds (vendor documented); observed in sync-write burst |
| RTC_MINUTES | 400 | 40401 | rw | uint16 | 1 | min | confirmed | `[vendor §4.2.4]` current time minutes (vendor documented); observed in sync-write burst |
| RTC_HOURS | 401 | 40402 | rw | uint16 | 1 | h | confirmed | `[vendor §4.2.4]` current time hours (vendor documented); observed in sync-write burst |
| RTC_DAY_OF_MONTH | 402 | 40403 | rw | uint16 | 1 | day | confirmed | `[vendor §4.2.4]` current date day-of-month (vendor documented); observed in sync-write burst |
| RTC_MONTH | 403 | 40404 | rw | uint16 | 1 | month | confirmed | `[vendor §4.2.4]` current date month (vendor documented); observed in sync-write burst |
| RTC_YEAR | 404 | 40405 | rw | uint16 | 1 | year | confirmed | `[vendor §4.2.4]` current date year (vendor documented); observed in sync-write burst |
| RTC_DAY_OF_WEEK | 405 | 40406 | ro | uint16 | 1 | enum | confirmed | 0=Mon .. 6=Sun; read-only, auto-derived from date |
| UNKNOWN_40407_40420 | 406..419 | 40407..40420 | rw | block | - | - | confirmed | vendor table leaves this range undocumented; live sweep returned all zeros across the full range; sampled same-value FC06 write-back at `40407` and `40420` returned `OK`, so (unlike the 40300 alarms block) this setup-parameters range is genuinely writable, matching the vendor `40400...` "Setup parameters / Read and write" heading |
| UNKNOWN_40421_40422 | 420..421 | 40421..40422 | rw | uint32 | - | - | confirmed | vendor table does not document this pair at this offset; live read returned words `32304/13`, the exact same values as `FAN_TYPE_CONFIGURATION` at raw `49..50` (doc `40050..40051`); same-value FC06 write-back at both words returned `OK`, so this looks like a writable setup-block mirror of the factory `FAN TYPE` code rather than a coincidence; not yet confirmed whether writing a different value here actually changes fan-type behavior |
| UNKNOWN_40423 | 422 | 40423 | rw | uint16 | 1 | - | confirmed | vendor table does not document this register; live read returned `2`; same-value FC06 write-back returned `OK` |
| UNKNOWN_40424_40425 | 423..424 | 40424..40425 | rw | block | - | - | confirmed | vendor table does not document this pair; live read returned `0/0`; same-value FC06 write-back at `40424` returned `OK` |
| OPERATION_MODE | 425 | 40426 | rw | uint16 | 1 | enum | confirmed | `[vendor §4.2.4]` OFF=0, CA=1, LS=2, CP=4 (capture-verified); vendor table uses 40426 for mode selection |
| RATIO_EXH_SUP | 426 | 40427 | rw | uint16 | 0.01 | ratio | confirmed | capture-verified write target for exhaust/supply ratio; repeatedly confirmed by app write/readback and multiple captures |
| AIRFLOW_I | 427 | 40428 | rw | uint16 | 1 | m3_h | confirmed | `[vendor §4.2.4]` CA mode supply setpoint I; capture-tested with 200 / 100 |
| AIRFLOW_II | 428 | 40429 | rw | uint16 | 1 | m3_h | confirmed | `[vendor §4.2.4]` CA mode supply setpoint II; capture-tested with 400 / 200 |
| AIRFLOW_III | 429 | 40430 | rw | uint16 | 1 | m3_h | confirmed | `[vendor §4.2.4]` CA mode supply setpoint III; capture-tested with 600 / 300 |
| UNKNOWN_40431 | 430 | 40431 | rw | uint16 | 1 | - | confirmed | vendor table does not document this register; live read returned `0`; same-value FC06 write-back returned `OK` |
| UNKNOWN_40432_40433 | 431..432 | 40432..40433 | rw | uint16 | 1 | dynamic | confirmed | vendor table does not document this pair; live read returned `300/300`; same-value FC06 write-back at both registers returned `OK`; values look airflow-like (m3/h range) but no controlled experiment has linked them to a specific mode/field yet |
| UNKNOWN_40434 | 433 | 40434 | rw | uint16 | 1 | - | confirmed | vendor table does not document this register; live read returned `0` |
| UNKNOWN_40435_40437 | 434..436 | 40435..40437 | rw | uint16 | 1 | dynamic | confirmed | vendor table does not document this range; live read returned `700/0/700`; same-value FC06 write-back at `40435` and `40437` returned `OK`; values look airflow-like (m3/h range) but no controlled experiment has linked them to a specific mode/field yet |
| LS_VMIN | 437 | 40438 | rw | uint16 | 0.1 | V | confirmed | `[vendor §3.2 LS Mode]` LS mode minimum analog input threshold; 0.9 V produced raw value 9 |
| LS_VMAX | 438 | 40439 | rw | uint16 | 0.1 | V | confirmed | `[vendor §3.2 LS Mode]` LS mode maximum analog input threshold; 9.5 V and 10.0 V produced raw values 95 and 100 |
| LS_AIRFLOW_AT_VMIN | 439 | 40440 | rw | uint16 | 1 | m3_h | confirmed | `[vendor §3.2 LS Mode]` LS mode airflow setpoint at Vmin; capture-tested with 100 and 150 |
| LS_AIRFLOW_AT_VMAX | 440 | 40441 | rw | uint16 | 1 | m3_h | confirmed | `[vendor §3.2 LS Mode]` LS mode airflow setpoint at Vmax; capture-tested with 800 and 840 |
| LS_K3_SLEEP_FACTOR | 441 | 40442 | rw | uint16 | 1 | percent | confirmed | K3 sleep factor; repeated captures and app write/readback confirmed final writes 90 and 100, with Eole often emitting intermediate artifact value 1 |
| CP_ON_MODE | 442 | 40443 | rw | uint16 | 1 | enum | confirmed | `[vendor §3.2 CPs Mode]` CP mode `CP on` selector; capture-tested transitions showed 0 = Supply, 1 = Exhaust, 2 = Supply / Exhaust |
| UNKNOWN_40444_40445 | 443..444 | 40444..40445 | rw | block | - | - | confirmed | vendor table does not document this pair; live read returned `0/0`; same-value FC06 write-back at `40444` returned `OK` |
| CP_SUPPLY_VOLTAGE | 445 | 40446 | rw | uint16 | 0.1 | V | confirmed | `[vendor §3.2 CPs Mode]` CP voltage setpoint 1 for supply (or single-side CP mode); raw value 9 observed for 0.9 V |
| UNKNOWN_40447_40448 | 446..447 | 40447..40448 | rw | block | - | - | confirmed | vendor table does not document this pair; live read returned `0/0`; same-value FC06 write-back at `40447` returned `OK` |
| CP_EXHAUST_VOLTAGE | 448 | 40449 | rw | uint16 | 0.1 | V | confirmed | `[vendor §3.2 CPs Mode]` CP reference voltage for exhaust in SUP+EXH mode; raw value 9 observed for 0.9 V |
| UNKNOWN_40450_40499 | 449..498 | 40450..40499 | rw | block | - | - | confirmed | vendor table leaves this range undocumented; live sweep returned all zeros across the full range; sampled same-value FC06 write-back at `40499` returned `OK`, consistent with the rest of this writable setup-parameters block |
| LS_STOP_IF_BELOW_VLOW | 500 | 40501 | rw | uint16 | 1 | bool-like | confirmed | LS mode stop-fan enable for low analog threshold; clean capture showed 1/0 writes |
| LS_VLOW | 501 | 40502 | rw | uint16 | 0.1 | V | confirmed | LS mode low stop threshold; clean capture showed raw value 5 for 0.5 V |
| LS_STOP_IF_ABOVE_VHIGH | 502 | 40503 | rw | uint16 | 1 | bool-like | confirmed | LS mode stop-fan enable for high analog threshold; clean capture showed 1/0 writes |
| LS_VHIGH | 503 | 40504 | rw | uint16 | 0.1 | V | confirmed | LS mode high stop threshold; clean capture showed raw values 95 and 100 for 9.5 V and 10.0 V |
| LS_K3_010V_ENABLE | 504 | 40505 | rw | uint16 | 1 | bool-like | confirmed | K3 analog signal enable on LS mode; clean capture showed No -> enabled -> No as 0/1/0 |
| UNKNOWN_40506_40520 | 505..519 | 40506..40520 | rw | uint16 | 1 | dynamic | confirmed | vendor only documents this range at the high level `40500...` "Advanced setup parameters / Read and write" heading; live sweep returned `10,1,2,1,0,0,0,150,220,0,0,0,10,1,10`; same-value FC06 write-back sampled at `40506` (`10`) and `40513` (`150`) both returned `OK`; no controlled experiment ties these to a specific mode/field yet |
| UNKNOWN_40521 | 520 | 40521 | ro | uint16 | 1 | dynamic | confirmed | vendor does not document this register; live read returned `50`; FC06 write-back was rejected with Modbus exception code `2` (illegal address for write), confirming read-only access regardless of the value attempted |
| UNKNOWN_40522_40542 | 521..541 | 40522..40542 | rw | uint16 | 1 | dynamic | confirmed | vendor does not document this range; live sweep returned `1,5,150,0,5,5,30,11,0,1,1,90,1,1,0,0,0,0,0,0,0`; same-value FC06 write-back sampled at `40533` (`90`) returned `OK` (this register was briefly and accidentally overwritten to `1` during probe construction on 2026-07-05, then restored to `90` and reverified against the original sweep baseline with no other discrepancies found across the full `40500..40599` block) |
| MODBUS_UNIT_ADDRESS | 542 | 40543 | rw | uint16 | 1 | - | confirmed | `[vendor §3.1]` register used to change this unit's Modbus address; live read returned `1`, matching the documented default address; not write-tested (changing this would require re-pointing all tooling at a new unit id) |
| UNKNOWN_40544_40583 | 543..582 | 40544..40583 | rw | uint16 | 1 | dynamic | confirmed | vendor does not document this range beyond the general `40500...` heading; live sweep returned `0,0,0,0,840,840,2,5,40,40,40,0,0,0,0,70,0,0,0,0,0,0,0,0,0,0,8,150,280,0,0,5030,0,60,40,20,95,20,95`; notably `40548/40549 = 840/840` matches the live `LS_AIRFLOW_AT_VMAX` value and `40581/40583 = 95/95` matches the live `LS_VHIGH` value, suggesting this block mirrors/derives some LS-mode parameters; same-value FC06 write-back sampled at `40572` (`150`) returned `OK` (this register was also briefly and accidentally overwritten to `8` during probe construction on 2026-07-05, then restored to `150` and reverified) |
| LS_K3_TARGET_SIDE | 583 | 40584 | rw | uint16 | 1 | enum | confirmed | K3 target side when 0-10V on K3 is enabled; clean capture showed 0 = Exhaust and 1 = Supply; live-reread on 2026-07-05 returned `0` = Exhaust, consistent |
| UNKNOWN_40585_40599 | 584..598 | 40585..40599 | rw | uint16 | 1 | dynamic | confirmed | vendor does not document this range; live sweep returned `0,0,3,40,0,0,0,30,0,0,0,0,0,0,0`; same-value FC06 write-back sampled at `40588` (`40`) returned `OK` (this register was also briefly and accidentally overwritten to `3` during probe construction on 2026-07-05, then restored to `40` and reverified) |
| REC_TYPE_CONFIGURATION_MIRROR | 599..600 | 40600..40601 | rw | uint32 | - | - | confirmed | vendor does not document this pair at this offset; live read returned words `32305/13`, the exact same values as `REC_TYPE_CONFIGURATION` at raw `19..20` (doc `40020..40021`); same-value FC06 write-back at raw `599` returned `OK`, so (like the `40421..40422` fan-type mirror) this looks like a writable advanced-setup mirror of the factory `REC TYPE` code |
| UNKNOWN_40602_40700 | 601..699 | 40602..40700 | rw | block | - | - | confirmed | vendor table leaves this range undocumented; live sweep returned all zeros across the full range; sampled same-value FC06 write-back at `40602` returned `OK` |
| UNKNOWN_40701_40721 | 700..720 | 40701..40721 | rw | uint16 | 1 | dynamic | confirmed | vendor does not document this range; live sweep returned `10,55,103,124,10,55,103,124,0,0,100,0,0,0,100,0,0,0,1000,1000,1000` (note the repeated `10,55,103,124` quadruplet and the repeated `100`/`1000` triplets); same-value FC06 write-back sampled at `40701` (`10`), `40711` (`100`), and `40719` (`1000`) all returned `OK`; no controlled experiment ties these to a specific mode/field yet |
| UNKNOWN_40722_40800 | 721..799 | 40722..40800 | rw | block | - | - | confirmed | vendor table leaves this range undocumented; live sweep returned all zeros across the full range |
| UNKNOWN_40801 | 800 | 40801 | ro | uint16 | 1 | - | confirmed | vendor does not document this register; live read returned `0`; FC06 write-back was rejected with Modbus exception code `2`, confirming read-only access, unlike the surrounding writable gap registers |
| UNKNOWN_40802_40999 | 801..998 | 40802..40999 | rw | block | - | - | confirmed | vendor table leaves this range undocumented; live sweep returned all zeros across the full range; sampled same-value FC06 write-back at `40901` and `40999` both returned `OK` |
| TIMETABLE_WEEK_BASE | 999 | 41000 | rw | block | - | - | confirmed | `[vendor §5]` weekly timetable block base (vendor documented); live sweep of the full `41000..41417` block confirmed the vendor's documented 10-register-per-slot structure across all 42 slots (7 days x 6 slots): every slot currently reads `[start=65535 (signed -1, Not used), mode=1 (CA), undocumented=1, setpoint1=0, setpoint2=0, heat_setpoint=0, cool_setpoint=0, bypass_mode=0 (Auto), undocumented=0, undocumented=0]`, i.e. no custom weekly schedule is currently configured on this unit (consistent with the unit currently running in manual/RC control per `CONTROL_MASTER_SELECT=0`); the vendor-documented fields are offsets 0 (start), 1 (mode), 3 (setpoint1), 4 (setpoint2), 5 (heat setpoint), 6 (cool setpoint), 7 (bypass mode); offsets 2, 8, 9 within each slot are undocumented and were observed as `1, 0, 0` respectively on every slot |
| TIMETABLE_WEEK_END | 1416 | 41417 | rw | block | - | - | confirmed | `[vendor §5]` weekly timetable block end (vendor documented); live read matches the last field of the Sunday slot 6 segment, value `0`, consistent with the uniform unconfigured-slot pattern described above |
| UNKNOWN_41418_41799 | 1417..1798 | 41418..41799 | rw | block | - | - | confirmed | gap between the vendor-documented weekly timetable block (ending `41417`) and the vendor-documented season management block (starting `41800`); not present in `docs/TAC5_MODBUS_TABLE_SUMMARY.md`; live sweep across the full range returned all zeros, and the addresses do respond (no Modbus exceptions on read), so this range exists on this unit even though the vendor extract does not document it |
| BYPASS_DISABLE_PERIOD | 1799..1802 | 41800..41803 | rw | block (4x uint16) | - | day/month | confirmed | `[vendor §6]` season-management disable window for bypass: `Start Day (1..31)`, `Start Month (1..12)`, `End Day (1..31)`, `End Month (1..12)`; live read returned `0,0,0,0`, consistent with the vendor convention that all-zero disables seasonal management for this feature |
| POSTHEAT_DISABLE_PERIOD | 1803..1806 | 41804..41807 | rw | block (4x uint16) | - | day/month | confirmed | `[vendor §6]` season-management disable window for post-heating, same `Start Day/Month, End Day/Month` structure as `BYPASS_DISABLE_PERIOD`; live read returned `0,0,0,0`, consistent with seasonal management disabled |
| COOLING_DISABLE_PERIOD | 1807..1810 | 41808..41811 | rw | block (4x uint16) | - | day/month | confirmed | `[vendor §6]` season-management disable window for cooling, same `Start Day/Month, End Day/Month` structure as `BYPASS_DISABLE_PERIOD`; live read returned `0,0,0,0`, consistent with seasonal management disabled; this is the last register documented in `docs/TAC5_MODBUS_TABLE_SUMMARY.md` -- the vendor document ends here |
| UNKNOWN_41812_41999 | 1811..1998 | 41812..41999 | ro | block | - | - | confirmed | beyond the end of `docs/TAC5_MODBUS_TABLE_SUMMARY.md` (which stops at `41811`); live sweep across the full range returned all zeros, and the addresses do respond to reads (no Modbus exceptions); same-value FC06 write-back sampled at `41901` and `41999` were both rejected with Modbus exception code `2`, confirming this entire tail range is read-only |
| END_OF_VALID_REGISTER_SPACE | 1999 | 42000 | - | - | - | - | confirmed | binary-searched boundary: `41999` is the last document address that responds to FC03 reads on this unit; `42000` and above return Modbus exception code `2` (illegal data address); this is the hard upper limit of the Modbus register map on this TAC5 unit, beyond anything covered by `docs/TAC5_MODBUS_TABLE_SUMMARY.md` |

## Confirmed write sequences (capture-based)

- Preset transitions (capture: k123_cycle_new.pcapng):
  - K3 -> K1: 40200=0, then 40203=1
  - K1 -> K2: 40200=0, then 40203=2
  - K2 -> K3: 40200=0, then 40203=3
- Manual / schedule selector (captures: manual_to_schedule_only_20260628_live.pcapng, schedule_to_manual_only_20260628_live.pcapng, manual_schedule_confirm_20260628_live.pcapng):
  - Manual / RC -> Schedule / Timetable produced 40200=2
  - Schedule / Timetable -> Manual / RC produced 40200=0 and companion 40201=0
  - Best-fit interpretation is 40200 = CONTROL_MASTER_SELECT with 0 = RC/manual and 2 = Timetable/schedule; 40201 behaves consistently with the vendor Modbus speed-selection register rather than a commit field
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
  - 40254 received a write of 10, then returned to 0 automatically; this matches the broader initialization flow 1 field used by pressure-alarm / CP initialization

## Observed runtime behavior

- The app writes preset changes as a two-step command: 40200=0, then 40203=<1|2|3>.
- The app writes bypass as a single FC06 command to register 222.
- The app writes boost as a single FC06 command to register 227.
- The exhaust/supply ratio behaves as a shared/global parameter across modes rather than a CA-only value.
- The Eole/TACTouch UI can emit intermediate artifact writes while editing LS/K3 fields; current evidence suggests these are UI side effects, not values the app should intentionally mirror.
- The CP `CP on` field is separate from the LS K3 `504/583` pair; CP uses register 442.
- The CP `Pressure / Airflow` selector still has no confirmed standalone write; current evidence suggests it may only affect how other CP fields are interpreted or when writes are committed.
- The app is currently behaving well for manual settings; the remaining uncertainty is focused on selector-style fields rather than the already-mapped manual parameter writes.

## Vendor doc cross-check (TAC5 + MODBUS TABLE)

Reference source used for this cross-check:

- `docs/TAC5_MODBUS_TABLE_SUMMARY.md` (official TAC5 + MODBUS TABLE installation/user's manual summary, converted to Markdown in this repo)

The main table above now tags every row that has an explicit, matching entry in that document with `[vendor §x.y]`, pointing at the exact summary section (for example `[vendor §4.2.2]` for the Control section, `[vendor §3.2 CPs Mode]` for the CPs Mode functionality summary). Untagged rows were only confirmed by live probing/capture evidence on this unit, or sit in vendor-documented gaps.

What is now directly documented and matches capture evidence:

- RTC register block is explicitly documented at document addresses `40400..40406`.
- Week scheduler is explicitly documented as `7 days x 6 slots/day` with register range `41000..41417`; live sweep of the entire block confirmed the vendor's 10-register-per-slot layout on all 42 slots, and every slot currently reads as unconfigured (start time `-1`).
- Season management block (`41800..41811`) is explicitly documented and live-confirmed: all three disable-period windows (bypass, post-heat, cooling) currently read all-zero, meaning seasonal management is disabled for all three features on this unit.
- The `41418..41799` gap between the timetable and season-management blocks is not present in `docs/TAC5_MODBUS_TABLE_SUMMARY.md`, but live sweeping confirms these addresses do exist and respond (all read as `0`).
- Beyond the vendor document's last register (`41811`), live probing found the unit's Modbus register map actually continues, read-only and all-zero, through `41999`; `42000` and above return Modbus exception code `2` on read, giving a confirmed hard upper bound for this unit's entire register space (`40001..41999`).
- Capture and app behavior align with RTC writes using 0-based wire offsets `399..404`.
- The Modbus unit-address register (`40543`, section 3.1) is documented by the vendor but has not yet been live-tested on this unit; it is listed as `MODBUS_UNIT_ADDRESS` with status `doc-confirmed`.

Important reconciliation note:

- Modbus packets and app internals in this repo use 0-based offsets.
- Vendor documentation uses 4xxxx document-style addresses.
- Conversion used here: `document_address = raw_offset + 40001`.

Documented behavior of the mobile sync action (inferred from doc + capture):

- `Synchronize the date and time with your mobile device` writes the current mobile time/date to the RTC write block.
- Observed write burst maps as: `399..404` -> seconds, minutes, hours, day, month, year.
- `40406` (day of week) remains read-only and is computed by the controller from the date.

Operational guidance from vendor text:

- Do not write RTC registers cyclically/continuously; periodic forced time writes can degrade clock behavior.

## Open questions

- Whether 52 is strictly the active preset index or a broader working mode selector.
- Whether register 52 mirrors active preset for all firmware variants.
- Whether Boost is a dedicated mode bit or an alternate setpoint profile.
- What OPERATION_MODE value 3 means (currently unobserved; planned experiment).
- Whether T4 can become a live, non-sentinel sensor on this unit/configuration; current live read is signed `-999` at `40158` while T7 remains valid at `40161`.
- Which Modbus register backs the local `SAT BA` selector that gates whether the UI diagram containing T7 is shown.
- What bit `6` at `40301` (`ALARM_BITMAP_1`) represents; the vendor extract used here only documents bit layouts for `40300` and `40303`, so this bit is confirmed live/stable but not yet named.
- What `40421..40422` actually control; live values exactly match `FAN_TYPE_CONFIGURATION` (raw `49..50`) and both words accept same-value FC06 writes, but no controlled experiment has confirmed whether this is a true writable mirror or an unrelated field that happens to share the same factory value.
- What `40432..40433` (`300/300`) and `40435..40437` (`700/0/700`) represent; these read as writable, airflow-like values in the setup-parameters block but are not in the vendor extract used here and have not been tied to a specific mode/experiment yet.
