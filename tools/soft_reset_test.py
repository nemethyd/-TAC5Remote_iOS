#!/usr/bin/env python3
"""
soft_reset_test.py — Test whether writing reset trigger register=value restores connection after a freeze

Usage:
    python tools/soft_reset_test.py [--host <ip>] [--port <502>] [--interval-s <2>] [--reset-register <199|999>] [--reset-value <0>]

Logic:
  - Continuously reads OPERATION_MODE (reg 425)
  - On any read failure (timeout, empty, or None), perform soft reset:
      write(RESET_REGISTER, RESET_VALUE)
    then retry once
  - Log all events to stdout and debug.log

Dependencies: pymodbus (same as modbus_disconnect_probe.py)
"""

import asyncio
import logging
import sys
from pathlib import Path
from datetime import datetime

# Configure pymodbus logging (optional)
logging.getLogger("pymodbus").setLevel(logging.WARNING)

try:
    from pymodbus.client import ModbusTcpClient # pyright: ignore[reportMissingImports]
    import pymodbus.client
except ImportError as e:
    print(f"[ERROR] Missing dependency: pip install pymodbus")
    sys.exit(1)


# --- CONFIGURATION ---
HOST = "192.168.10.80"  # Eole/TACTouch IP (hálózati modul)
PORT = 502
INTERVAL_S = 2.0
REG_OPERATION_MODE = 425
REG_RESET_TRIGGER = 199
RESET_VALUE = 0

# Optional: increase timeout if network is slow
CLIENT_TIMEOUT = 3.0


# --- LOGGING SETUP ---
LOG_FILE = Path("tools/debug.log")
def log(msg: str, to_stdout=True, to_file=True):
    ts = datetime.now().isoformat(timespec="seconds")
    line = f"[{ts}] {msg}"
    if to_stdout:
        print(line)
    if to_file:
        with LOG_FILE.open("a", encoding="utf-8") as f:
            f.write(line + "\n")


async def read_operation_mode(client: pymodbus.client.ModbusTcpClient) -> int | None:
    """Read OPERATION_MODE, return value or None on failure."""
    try:
        rr = client.read_holding_registers(REG_OPERATION_MODE, 1, slave=1)
        if not rr.isError() and hasattr(rr, "registers") and rr.registers:
            return rr.registers[0]
        else:
            return None
    except Exception as e:
        log(f"Read ERROR: {e}", to_file=True)
        return None


async def soft_reset(client: pymodbus.client.ModbusTcpClient) -> bool:
    """Write configured reset trigger register/value, return True on success."""
    try:
        result = client.write_register(REG_RESET_TRIGGER, RESET_VALUE, slave=1)
        if not result.isError():
            log(f"✅ Soft reset ({REG_RESET_TRIGGER}={RESET_VALUE}) sent", to_stdout=True)
            return True
        else:
            log(f"⚠️ Write {REG_RESET_TRIGGER}={RESET_VALUE} failed: {result}", to_stdout=False)
            return False
    except Exception as e:
        log(f"Write ERROR for {REG_RESET_TRIGGER}={RESET_VALUE}: {e}", to_file=True)
        return False


async def main():
    log(
        f"🚀 Starting soft_reset_test.py — monitoring OPERATION_MODE (425), "
        f"reset trigger={REG_RESET_TRIGGER}, value={RESET_VALUE}"
    )
    if not hasattr(pymodbus.client.ModbusTcpClient, "read_holding_registers"):
        # sanity-check for pymodbus v3 vs v2
        log("⚠️ Warning: pymodbus API mismatch. Adjust imports if needed.", to_stdout=True)

    client = pymodbus.client.ModbusTcpClient(HOST, port=PORT, timeout=CLIENT_TIMEOUT)
    if not client.connect():
        log(f"[FATAL] Could not connect to {HOST}:{PORT}", to_file=False)
        sys.exit(1)
    else:
        log(f"✅ Connected to Eole at {HOST}:{PORT}")

    failures_in_row = 0
    while True:
        try:
            op_mode = await read_operation_mode(client)
            if op_mode is None:
                failures_in_row += 1
                log(f"[WARN] Read failed ({failures_in_row}× in a row)")
                # Try soft reset on >=2 consecutive failures
                if failures_in_row >= 2:
                    log(f"🔁 Attempting soft reset (write {REG_RESET_TRIGGER}={RESET_VALUE})...")
                    if await soft_reset(client):
                        # retry immediately after reset
                        await asyncio.sleep(0.5)
                        op_mode = await read_operation_mode(client)
                        if op_mode is not None:
                            failures_in_row = 0
                            log(f"✅ Connection restored: OPERATION_MODE={op_mode}")
                            continue
                    # Reset didn’t help — break or keep retrying? Keep for now.
            else:
                failures_in_row = 0
                log(f"STATE: OPERATION_MODE = {op_mode}")

            await asyncio.sleep(INTERVAL_S)
        except KeyboardInterrupt:
            log("\n🛑 Stopped by user.")
            break
    client.close()


if __name__ == "__main__":
    # Simple arg parsing (optional overrides)
    for i, arg in enumerate(sys.argv):
        if arg.startswith("--host="): HOST = arg.split("=")[1]
        elif arg == "--host" and i+1 < len(sys.argv): HOST = sys.argv[i+1]
        elif arg.startswith("--port="): PORT = int(arg.split("=")[1])
        elif arg == "--port" and i+1 < len(sys.argv): PORT = int(sys.argv[i+1])
        elif arg.startswith("--interval-s="): INTERVAL_S = float(arg.split("=")[1])
        elif arg == "--interval-s" and i+1 < len(sys.argv): INTERVAL_S = float(sys.argv[i+1])
        elif arg.startswith("--reset-register="): REG_RESET_TRIGGER = int(arg.split("=")[1])
        elif arg == "--reset-register" and i+1 < len(sys.argv): REG_RESET_TRIGGER = int(sys.argv[i+1])
        elif arg.startswith("--reset-value="): RESET_VALUE = int(arg.split("=")[1])
        elif arg == "--reset-value" and i+1 < len(sys.argv): RESET_VALUE = int(sys.argv[i+1])

    asyncio.run(main())
