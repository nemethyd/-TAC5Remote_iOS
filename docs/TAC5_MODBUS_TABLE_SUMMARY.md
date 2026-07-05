# TAC5 + MODBUS TABLE

## Installation and User's Manual

---

## 1. Scope

Description and details of Modbus tables and registers for Modbus RTU or TCP/IP communication between a BMS (master) and the control boards (slaves):

* **TAC5 DG** for HRglobal/HRup/HRflat/HRclassunit units
* **TAC5 DT** for HRtotal
* **TAC5 DM** for HRmural
* **TAC5 SC** for single flow COMPO units
* **TAC5 F** for controlling one or two fans (forward or backward)

The MODBUS communication with TAC5 control boards requires an additional satellite circuit which is used as communication interface:

* **MODBUS RTU communication protocol:** SAT MODBUS Option (on RS-485 physical network).
* **MODBUS TCP/IP communication protocol:**
  * SAT WIFI Option (on wireless Wi-Fi network).
  * SAT ETHERNET Option (on Ethernet over twisted pair 10 BASE T/100Base-TX IEEE 802.3 network).

---

## 2. Modbus Map Overview

The TAC5 regulation can be entirely monitored by the MODBUS communication. The MODBUS table is structured as follows:

| Registers | Group | Read/Write | Description |
| :--- | :--- | :--- | :--- |
| **40001 ...** | General info | Read only | Provides general information about the system. |
| **40020 ...** | Visualization | Read only | Shows actual values of a number of setup parameters and unit parameters (flows, pressures, inputs and outputs). |
| **40200 ...** | Control | Read and write | Control speed by different sources. Control of functionalities like bypass, fire alarm, post-heating. Run initialization of pressure parameters. Control of resets. |
| **40300 ...** | Alarms | Read only | Bitmap with alarm flags. |
| **40400 ...** | Setup parameters | Read and write | System setup configuration parameters. |
| **40500 ...** | Advanced setup parameters | Read and write | Advanced setup configuration parameters. |
| **41000 ...** | Time table configuration | Read and write | Configuration for time scheduler parameters. |

---

## 3. Use of MODBUS Commands

### 3.1 MODBUS Address

* **Default Address:** `1`
* **Register:** `40543` (used to modify the address value)
* *Caution:* only connect TAC5 circuits with different addresses to the network.

### 3.2 Principal Functionalities Summary (Registers)

#### Fans Working Modes (TAC5 DG/DM/DT)

* **CA Mode (Continuous Airflow via Modbus):** Set Master (`40200` = 3), Supply Airflow (`40204`), Exhaust Airflow (`40205`)
* **CA Mode (3 Set points):** Select mode (`40426`), set points 1/2/3 (`40428`, `40429`, `40430`), unbalance (`40427`), master selection (`40200`), position (`40201`)
* **TQ Mode (Continuous Torque %):** Set Master (`40200`), Supply Fan Torque (`40204`), Exhaust Fan Torque (`40205`)
* **LS Mode (0-10V Signal Link):** Mode selection (`40426`), Vmin/Vmax (`40438`/`40439`), airflow/torque at Vmin/Vmax (`40440`/`40441`)
* **CPs Mode (Constant Pressure):** Mode selection (`40426`), regulation flow side (`40443`), set points (`40446`, `40449`), initialization (`40254`, `40256`, `40257`)

#### Viewing Fan & Temperature Data

* **Operating Mode / Position:** `40052` / `40053`
* **Actual Airflow & Pressure:** Supply Fan 1 (`40065`/`40066`), Exhaust Fan 1 (`40073`/`40074`)
* **Temperatures:** Outside Air T1 (`40155`), Interior Stale Air T2 (`40156`), Exhaust T3 (`40157`), Supply T5 (`40159`)

---

## 4. Detailed MODBUS Table

### Legend

* **R** (Read/Write): Read only
* **R/W** (Read/Write): Read and write
* **E1** (Type): Register in EEPROM memory (endurance of 100,000 write cycles)
* **R** (Type): Register in non-volatile RAM memory

### 4.1 General Info (All Models)

| Register | Read/Write | Type | Description | Accepted Values / Examples |
| :--- | :--- | :--- | :--- | :--- |
| **40001-40002** | R | E1 | Magic number to detect Swegon product ("LMNS") | First word: 19533, second word: 20051 |
| **40003** | R | E1 | Swegon product identification code number (CID) | Unsigned 0..32767 |
| **40004** | R | E1 | Modbus mapping version (= Major * 100 + minor) | Example: 100 (v1.0) |
| **40005** | R | E1 | Software version, major | 0..99 |
| **40006** | R | E1 | Software version, minor | 0..99 |
| **40007** | R | E1 | Software version, revision | 0..99 |
| **40008** | R/W | E1 | Flag indicating that controller has been reset | 0 or 1 |
| **40009** | R | E1 | Software version, build number | Ex: 1984 |
| **40010-40017** | R/W | E1 | Unit name (alphanumeric ASCII, 2 chars per register) | Ex: 40010 = 16961 (BA) |

### 4.2 Specific Tables for TAC5 DG/DM/DT Regulations

#### 4.2.1 Visualization

| Register | R/W | Type | Description | Accepted Values |
| :--- | :--- | :--- | :--- | :--- |
| **40052** | R | E1 | Current Working Mode | 0=OFF, 1=CA, 2=LS, 4=CPs, 6=TQ, 9=INIT |
| **40053** | R | E1 | Current speed position | 0=STOP, 1=LOW/I, 2=MEDIUM/II, 3=HIGH/III |
| **40054** | R | E1 | Current set point value (SET VAL) | 0..9999 (m3/h, Pa, 0.1V or %) |
| **40055** | R | E1 | Current set point unit | 0=m3/h; 1=Pa; 2=0.1V; 3=% torque |
| **40056** | R | E1 | Current set point for supply fans F1/F2 | 0..max of unit |
| **40057** | R | E1 | Current set point for extraction fans F3/F4 | 0..max of unit |
| **40059** | R | E1 | Current comfort T° setpoint (in 0.1 °C units) | 0=OFF, 1..999 (+0.1 .. +99.9 °C) |
| **40065** | R | E1 | Fan 1 (Supply 1) flow or torque (%TQ) | 0..max of unit |
| **40066** | R | E1 | Fan 1 pressure | 0..max of unit |
| **40068** | R | E1 | Fan 1 RPM | 0..6000 |
| **40073** | R | E1 | Fan 3 (Exhaust 1) flow or torque (%TQ) | 0..max of unit |
| **40074** | R | E1 | Fan 3 pressure | 0..max of unit |
| **40081-40082** | R | E1 | Total working hours of the unit (RUN TIME) | 32-bit value in 2 words (0..999999 h) |
| **40084** | R | E1 | Bypass status | 0=CLOSED, 1=OPEN, 2=PARTIALLY OPEN |
| **40087** | R | E1 | Current control mode source | 1..11 (e.g. 2=Fire, 3=RC, 7=Modbus speed, 10=Modbus flow) |
| **40155** | R | E1 | Temperature T1 (Fresh air from outside), 0.1 °C | -990..+990 (-99..+99 °C), -999=open, +999=short |
| **40156** | R | E1 | Temperature T2 (Stale air from interior), 0.1 °C | -990..+990 (-99..+99 °C) |
| **40157** | R | E1 | Temperature T3 (Exhaust air to outside), 0.1 °C | -990..+990 (-99..+99 °C) |
| **40159** | R | E1 | Temperature T5 (Supply air to inside), 0.1 °C | -990..+990 (-99..+99 °C) |

#### 4.2.2 Control

| Register | R/W | Type | Description | Accepted Values |
| :--- | :--- | :--- | :--- | :--- |
| **40200** | R/W | R | Selection of the control master | 0=RC, 1=Modbus Speed, 2=Timetable, 3=Modbus Flows |
| **40201** | R/W | R | Speed selection via Modbus (if 40200=1) | 0=STOP, 1=LOW, 2=MEDIUM, 3=HIGH |
| **40204** | R/W | R | Supply airflow/torque selection via Modbus (if 40200=3) | 0..9999 (min..max of unit) |
| **40205** | R/W | R | Exhaust airflow/torque selection via Modbus (if 40200=3) | 0..9999 (min..max of unit) |
| **40222** | R/W | R | Fire alarm forcing status | 0=No alarm, 1=Fire alarm activated |
| **40223** | R/W | R | Override: force bypass open or closed | 0=Auto, 1=Force Open, 2=Force Close |
| **40225** | R/W | R | ON/OFF Post heat deactivation | 0=Post heating allowed, 1=Not allowed |
| **40228** | R/W | R | Boost control activation | 0=Not activated, 1=Activated |
| **40250** | R/W | E1 | Perform system RESET (clears pending fatal errors) | Read: 0, write: 1 to reset |
| **40251** | R/W | E1 | RESET TO FACTORY DEFAULT VALUES | Read: 0, write: 1 to reset |

#### 4.2.3 Alarms Bitmap (Read Only)

* **40300:** Bit 0=Prog Error, Bit 1=Data Error, Bit 2-5=Fan 1-4 Alarm, Bit 6-7=Pressure Alarm F1/F3, Bit 8-9=T1 Open/Short.
* **40303:** Bit 4-5=Maintenance Warn/Fatal, Bit 6=DPA (Diff Pressure Alarm), Bit 7=Fire Alarm.

#### 4.2.4 Setup Parameters

| Register | R/W | Type | Description | Accepted Values |
| :--- | :--- | :--- | :--- | :--- |
| **40400** | R/W | E1 | Current time: seconds | 0..59 |
| **40401** | R/W | E1 | Current time: minutes | 0..59 |
| **40402** | R/W | E1 | Current time: hours | 0..23 |
| **40403** | R/W | E1 | Current date: day of month | 1..31 |
| **40404** | R/W | E1 | Current date: month | 1..12 |
| **40405** | R/W | E1 | Current time: year | 2000..2099 |
| **40426** | R/W | E1 | Fans Working Mode Setup | 0=OFF, 1=CA, 2=LS, 4=CPs, 6=TQ, 9=INIT |
| **40428** | R/W | E1 | CA Airflow / TQ Torque Speed 1 (Pos. I) | 0..max of unit |
| **40429** | R/W | E1 | CA Airflow / TQ Torque Speed 2 (Pos. II) | 0..max of unit |
| **40430** | R/W | E1 | CA Airflow / TQ Torque Speed 3 (Pos. III) | 0..max of unit |

---

### 4.3 Specific Tables for TAC5 SC/F (Single Flow / Fan Controller)

#### 4.3.1 Visualization (SC/F)

| Register | R/W | Type | Description | Accepted Values |
| :--- | :--- | :--- | :--- | :--- |
| **40052** | R | E1 | Current Working Mode (SC/F) | 0=OFF, 1=CA, 2=LS, 3=CPf, 4=CPs, 6=TQ |
| **40056** | R | E1 | Current set point for fan F1 | 0..max of unit |
| **40057** | R | E1 | Current set point for fan F2 | 0..max of unit |
| **40065** | R | E1 | Fan 1 flow or torque (%TQ) | 0..max of unit |
| **40066** | R | E1 | Fan 1 pressure | 0..max of unit |
| **40073** | R | E1 | Fan 2 flow or torque (%TQ) | 0..max of unit |
| **40074** | R | E1 | Fan 2 pressure | 0..max of unit |

#### 4.3.2 Control (SC/F)

| Register | R/W | Type | Description | Accepted Values |
| :--- | :--- | :--- | :--- | :--- |
| **40204** | R/W | R | Fan 1 airflow/torque selection via Modbus (if 40200=3) | 0..9999 |
| **40205** | R/W | R | Fan 2 airflow/torque selection via Modbus (if 40200=3) | 0..9999 |
| **40255** | R/W | E1 | Do CPf mode initialization | Write 1 to start |

---

## 5. Time Scheduler Configuration (Registers 41xx0 ... 41xx7)

The system supports a 7 days / 6 timeslots per day programming matrix. Each segment occupies 10 registers (8 active parameters):

### Time Segment Structure

* **41xx0:** Start Time -> `(100 * hh) + mm` (e.g. `800 = 08:00`), `-1` = Not used
* **41xx1:** Working Mode -> `0=OFF, 1=CA, 2=LS, 3=CPf (SC/F only), 4=CPs, 6=TQ`
* **41xx3:** Set point 1 (Supply / Fan 1 Airflow or Torque %)
* **41xx4:** Set point 2 (Exhaust / Fan 2 Airflow or Torque % / Ratio)
* **41xx5:** T° Set point - Heating (0.1 °C units, 0 = OFF)
* **41xx6:** T° Set point - Cooling (0.1 °C units, 0 = OFF)
* **41xx7:** Bypass Mode (0=Auto, 1=Forced Close, 2=Forced Open) *(DG/DM/DT only)*

### Daily Mapping Ranges

* **Monday:** `41000 .. 41057` *(SC/F: `41000 .. 41056`)*
* **Tuesday:** `41060 .. 41117` *(SC/F: `41060 .. 41116`)*
* **Wednesday:** `41120 .. 41177` *(SC/F: `41120 .. 41176`)*
* **Thursday:** `41180 .. 41237` *(SC/F: `41180 .. 41236`)*
* **Friday:** `41240 .. 41297` *(SC/F: `41240 .. 41296`)*
* **Saturday:** `41300 .. 41357` *(SC/F: `41300 .. 41356`)*
* **Sunday:** `41360 .. 41417` *(SC/F: `41360 .. 41416`)*

---

## 6. Season Management (Registers 41800 ... 41811)

Allows disabling features (Bypass, Post-heating, Cooling) between specific dates. Formatted as 4 registers per feature: `Start Day (1..31)`, `Start Month (1..12)`, `End Day (1..31)`, `End Month (1..12)`. Set any register to `0` to disable seasonal management for that feature.

* **Bypass Disable Period:** `41800 .. 41803`
* **Post-Heating Disable Period:** `41804 .. 41807`
* **Cooling Disable Period:** `41808 .. 41811`

---

**SWEGON** | <www.swegon.com>
