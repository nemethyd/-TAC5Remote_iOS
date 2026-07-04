from __future__ import annotations

import argparse
import csv
import dataclasses
import socket
import struct
import time
from datetime import datetime
from typing import Iterable, List, Optional, Tuple


class ModbusProbeError(RuntimeError):
    pass


@dataclasses.dataclass
class ProbeStep:
    label: str
    address: int
    value: int


@dataclasses.dataclass
class ProbeResult:
    ts: str
    cycle: int
    index: int
    label: str
    address: int
    value: int
    status: str
    latency_ms: int
    detail: str


class ModbusTCPClient:
    def __init__(self, host: str, port: int, unit_id: int, timeout_s: float) -> None:
        self.host = host
        self.port = port
        self.unit_id = unit_id
        self.timeout_s = timeout_s
        self.sock: Optional[socket.socket] = None
        self.tx_id = 1

    def connect(self) -> None:
        self.close()
        self.sock = socket.create_connection((self.host, self.port), timeout=self.timeout_s)
        self.sock.settimeout(self.timeout_s)

    def close(self) -> None:
        if self.sock is not None:
            try:
                self.sock.close()
            except OSError:
                pass
            self.sock = None

    def _ensure_connected(self) -> None:
        if self.sock is None:
            self.connect()

    def _next_tx(self) -> int:
        tx = self.tx_id
        self.tx_id = 1 if self.tx_id >= 0xFFFF else self.tx_id + 1
        return tx

    def _recv_exact(self, n: int) -> bytes:
        assert self.sock is not None
        data = bytearray()
        while len(data) < n:
            chunk = self.sock.recv(n - len(data))
            if not chunk:
                raise ModbusProbeError("connection closed while receiving")
            data.extend(chunk)
        return bytes(data)

    def _exchange(self, pdu: bytes) -> bytes:
        self._ensure_connected()
        assert self.sock is not None

        tx = self._next_tx()
        mbap = struct.pack(">HHHB", tx, 0, 1 + len(pdu), self.unit_id)
        req = mbap + pdu

        try:
            self.sock.sendall(req)
            hdr = self._recv_exact(7)
            rx_tx, protocol, length, unit = struct.unpack(">HHHB", hdr)
            if rx_tx != tx or protocol != 0 or unit != self.unit_id:
                raise ModbusProbeError(
                    f"invalid response header tx={rx_tx} expected={tx} protocol={protocol} unit={unit}"
                )
            if length < 2:
                raise ModbusProbeError(f"invalid response length={length}")
            return self._recv_exact(length - 1)
        except (socket.timeout, OSError) as exc:
            self.close()
            raise ModbusProbeError(f"socket error: {exc}") from exc

    def read_holding(self, address: int, quantity: int = 1) -> List[int]:
        if not (1 <= quantity <= 125):
            raise ValueError("quantity out of range")
        pdu = struct.pack(">BHH", 0x03, address, quantity)
        resp = self._exchange(pdu)

        fn = resp[0]
        if fn == 0x83:
            code = resp[1] if len(resp) > 1 else -1
            raise ModbusProbeError(f"modbus exception fc03 code={code}")
        if fn != 0x03 or len(resp) < 2:
            raise ModbusProbeError("invalid fc03 response")

        byte_count = resp[1]
        if byte_count != quantity * 2 or len(resp) != 2 + byte_count:
            raise ModbusProbeError("invalid fc03 byte count")

        regs: List[int] = []
        for i in range(2, len(resp), 2):
            regs.append((resp[i] << 8) | resp[i + 1])
        return regs

    def write_single(self, address: int, value: int) -> None:
        pdu = struct.pack(">BHH", 0x06, address, value)
        resp = self._exchange(pdu)

        fn = resp[0]
        if fn == 0x86:
            code = resp[1] if len(resp) > 1 else -1
            raise ModbusProbeError(f"modbus exception fc06 code={code}")
        if fn != 0x06 or len(resp) < 5:
            raise ModbusProbeError("invalid fc06 response")


# This test set uses known, capture-validated command/value pairs.
def default_steps() -> List[ProbeStep]:
    return [
        ProbeStep("BYPASS_ON", 222, 1),
        ProbeStep("BYPASS_OFF", 222, 0),
        ProbeStep("BOOST_ON", 227, 1),
        ProbeStep("BOOST_OFF", 227, 0),
        ProbeStep("RATIO_90", 426, 90),
        ProbeStep("RATIO_80", 426, 80),
        ProbeStep("RATIO_100", 426, 100),
        ProbeStep("CA_I_200", 427, 200),
        ProbeStep("CA_II_400", 428, 400),
        ProbeStep("CA_III_600", 429, 600),
        ProbeStep("LS_VMIN_9", 437, 9),
        ProbeStep("LS_VMAX_95", 438, 95),
        ProbeStep("LS_AIRFLOW_MIN_150", 439, 150),
        ProbeStep("LS_AIRFLOW_MAX_840", 440, 840),
        ProbeStep("LS_STOP_LOW_ON", 500, 1),
        ProbeStep("LS_VLOW_5", 501, 5),
        ProbeStep("LS_STOP_HIGH_ON", 502, 1),
        ProbeStep("LS_VHIGH_95", 503, 95),
        ProbeStep("LS_K3_ENABLE", 504, 1),
        ProbeStep("LS_K3_TARGET_EXH", 583, 0),
        ProbeStep("LS_K3_DISABLE", 504, 0),
        ProbeStep("LS_K3_SLEEP_90", 441, 90),
        ProbeStep("CP_ON_SUPPLY", 442, 0),
        ProbeStep("CP_ON_EXHAUST", 442, 1),
        ProbeStep("CP_ON_BOTH", 442, 2),
        ProbeStep("CP_SUPPLY_V_9", 445, 9),
        ProbeStep("CP_EXHAUST_V_9", 448, 9),
        ProbeStep("CP_START_AIRFLOW_10", 253, 10),
    ]


def health_check(client: ModbusTCPClient) -> str:
    # Lightweight check around key live registers.
    mode = client.read_holding(425, 1)[0]
    supply = client.read_holding(64, 1)[0]
    exhaust = client.read_holding(72, 1)[0]
    return f"op_mode={mode} supply={supply} exhaust={exhaust}"


def run_probe(
    client: ModbusTCPClient,
    steps: Iterable[ProbeStep],
    cycles: int,
    delay_ms: int,
    reconnect_on_fail: bool,
) -> List[ProbeResult]:
    out: List[ProbeResult] = []
    seq = list(steps)

    for cycle in range(1, cycles + 1):
        for idx, step in enumerate(seq, start=1):
            t0 = time.perf_counter()
            ts = datetime.now().strftime("%Y-%m-%d %H:%M:%S.%f")[:-3]
            status = "OK"
            detail = ""
            try:
                client.write_single(step.address, step.value)
                detail = health_check(client)
            except Exception as exc:  # noqa: BLE001
                status = "FAIL"
                detail = str(exc)
                if reconnect_on_fail:
                    try:
                        client.connect()
                    except Exception as reconnect_exc:  # noqa: BLE001
                        detail += f" | reconnect_failed={reconnect_exc}"
            latency_ms = int((time.perf_counter() - t0) * 1000)

            result = ProbeResult(
                ts=ts,
                cycle=cycle,
                index=idx,
                label=step.label,
                address=step.address,
                value=step.value,
                status=status,
                latency_ms=latency_ms,
                detail=detail,
            )
            out.append(result)

            print(
                f"[{result.ts}] cycle={result.cycle} idx={result.index:02d} "
                f"{result.label} reg={result.address} val={result.value} "
                f"status={result.status} latency={result.latency_ms}ms detail={result.detail}",
                flush=True,
            )
            if delay_ms > 0:
                time.sleep(delay_ms / 1000.0)

    return out


def write_csv(path: str, rows: Iterable[ProbeResult]) -> None:
    with open(path, "w", newline="", encoding="utf-8") as fh:
        writer = csv.writer(fh)
        writer.writerow([
            "ts",
            "cycle",
            "index",
            "label",
            "address",
            "value",
            "status",
            "latency_ms",
            "detail",
        ])
        for r in rows:
            writer.writerow([
                r.ts,
                r.cycle,
                r.index,
                r.label,
                r.address,
                r.value,
                r.status,
                r.latency_ms,
                r.detail,
            ])


def parse_single_steps(single_args: List[str]) -> List[ProbeStep]:
    steps: List[ProbeStep] = []
    for item in single_args:
        try:
            reg_str, val_str = item.split(":", 1)
            reg = int(reg_str)
            val = int(val_str)
        except Exception as exc:  # noqa: BLE001
            raise argparse.ArgumentTypeError(
                f"invalid --single format '{item}', expected ADDRESS:VALUE"
            ) from exc
        steps.append(ProbeStep(label=f"SINGLE_{reg}_{val}", address=reg, value=val))
    return steps


def build_arg_parser() -> argparse.ArgumentParser:
    p = argparse.ArgumentParser(
        description=(
            "Probe TAC5 Modbus stability by replaying known valid FC06 writes "
            "and checking whether any write causes timeout/exception/disconnect."
        )
    )
    p.add_argument("--host", required=True, help="Target Modbus TCP host, e.g. 192.168.10.80")
    p.add_argument("--port", type=int, default=502, help="Target TCP port (default: 502)")
    p.add_argument("--unit", type=int, default=1, help="Modbus unit ID (default: 1)")
    p.add_argument("--timeout", type=float, default=2.5, help="Socket timeout seconds (default: 2.5)")
    p.add_argument("--cycles", type=int, default=3, help="Number of full step cycles (default: 3)")
    p.add_argument("--delay-ms", type=int, default=120, help="Delay between steps in ms (default: 120)")
    p.add_argument(
        "--single",
        action="append",
        default=[],
        metavar="ADDRESS:VALUE",
        help="Only test specified write(s); can be repeated, e.g. --single 438:95 --single 503:95",
    )
    p.add_argument(
        "--no-reconnect",
        action="store_true",
        help="Do not reconnect automatically after a failed step",
    )
    p.add_argument(
        "--csv",
        default="captures/modbus_disconnect_probe.csv",
        help="Output CSV path (default: captures/modbus_disconnect_probe.csv)",
    )
    return p


def main() -> int:
    args = build_arg_parser().parse_args()

    steps = parse_single_steps(args.single) if args.single else default_steps()
    if not steps:
        raise SystemExit("No probe steps configured")

    client = ModbusTCPClient(
        host=args.host,
        port=args.port,
        unit_id=args.unit,
        timeout_s=args.timeout,
    )

    try:
        client.connect()
        baseline = health_check(client)
        print(f"baseline: {baseline}", flush=True)

        results = run_probe(
            client=client,
            steps=steps,
            cycles=args.cycles,
            delay_ms=args.delay_ms,
            reconnect_on_fail=not args.no_reconnect,
        )
    finally:
        client.close()

    write_csv(args.csv, results)

    fail_count = sum(1 for r in results if r.status != "OK")
    print(f"summary: total={len(results)} fail={fail_count} csv={args.csv}", flush=True)
    if fail_count:
        first_fail = next(r for r in results if r.status != "OK")
        print(
            "first_failure: "
            f"cycle={first_fail.cycle} idx={first_fail.index} "
            f"label={first_fail.label} reg={first_fail.address} val={first_fail.value} "
            f"detail={first_fail.detail}",
            flush=True,
        )
        return 2
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
