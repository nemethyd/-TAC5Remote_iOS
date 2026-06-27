from __future__ import annotations

import argparse
import socket
import struct
import threading
from dataclasses import dataclass
from datetime import datetime
from typing import Optional


@dataclass
class ModbusMessage:
    transaction_id: int
    protocol_id: int
    length: int
    unit_id: int
    pdu: bytes


def now() -> str:
    return datetime.now().strftime("%H:%M:%S.%f")[:-3]


def recv_exact(sock: socket.socket, count: int) -> bytes:
    data = bytearray()
    while len(data) < count:
        chunk = sock.recv(count - len(data))
        if not chunk:
            raise ConnectionError("socket closed")
        data.extend(chunk)
    return bytes(data)


def read_message(sock: socket.socket) -> Optional[ModbusMessage]:
    header = sock.recv(7)
    if not header:
        return None
    while len(header) < 7:
        more = sock.recv(7 - len(header))
        if not more:
            return None
        header += more
    transaction_id, protocol_id, length, unit_id = struct.unpack(">HHHB", header)
    pdu = recv_exact(sock, length - 1)
    return ModbusMessage(transaction_id, protocol_id, length, unit_id, pdu)


def describe_request(msg: ModbusMessage) -> str:
    if not msg.pdu:
        return "empty PDU"

    function_code = msg.pdu[0]
    if function_code in (3, 4) and len(msg.pdu) >= 5:
        start, quantity = struct.unpack(">HH", msg.pdu[1:5])
        return f"fc={function_code} start={start} qty={quantity}"
    if function_code == 6 and len(msg.pdu) >= 5:
        address, value = struct.unpack(">HH", msg.pdu[1:5])
        return f"fc=6 addr={address} value={value}"
    if function_code == 16 and len(msg.pdu) >= 6:
        start, quantity, byte_count = struct.unpack(">HHB", msg.pdu[1:6])
        return f"fc=16 start={start} qty={quantity} bytes={byte_count}"
    return f"fc={function_code} pdu={msg.pdu.hex()}"


def describe_response(msg: ModbusMessage) -> str:
    if not msg.pdu:
        return "empty PDU"

    function_code = msg.pdu[0]
    if function_code in (3, 4) and len(msg.pdu) >= 2:
        byte_count = msg.pdu[1]
        return f"fc={function_code} bytes={byte_count}"
    if function_code in (6, 16) and len(msg.pdu) >= 5:
        address, quantity = struct.unpack(">HH", msg.pdu[1:5])
        return f"fc={function_code} addr={address} qty={quantity}"
    return f"fc={function_code} pdu={msg.pdu.hex()}"


def forward_stream(source: socket.socket, target: socket.socket, label: str, describe) -> None:
    try:
        while True:
            message = read_message(source)
            if message is None:
                break
            print(f"{now()} {label} TID={message.transaction_id} UID={message.unit_id} {describe(message)}", flush=True)
            target.sendall(struct.pack(">HHHB", message.transaction_id, message.protocol_id, message.length, message.unit_id) + message.pdu)
    except Exception as exc:
        print(f"{now()} {label} stopped: {exc}", flush=True)
    finally:
        try:
            target.shutdown(socket.SHUT_WR)
        except OSError:
            pass


def handle_client(client_sock: socket.socket, upstream_host: str, upstream_port: int) -> None:
    upstream_sock = socket.create_connection((upstream_host, upstream_port), timeout=5)
    upstream_sock.settimeout(None)
    client_sock.settimeout(None)
    print(f"{now()} client connected -> {upstream_host}:{upstream_port}", flush=True)

    to_upstream = threading.Thread(
        target=forward_stream,
        args=(client_sock, upstream_sock, "C->S", describe_request),
        daemon=True,
    )
    to_client = threading.Thread(
        target=forward_stream,
        args=(upstream_sock, client_sock, "S->C", describe_response),
        daemon=True,
    )
    to_upstream.start()
    to_client.start()
    to_upstream.join()
    to_client.join()

    try:
        client_sock.close()
    finally:
        upstream_sock.close()
    print(f"{now()} client disconnected", flush=True)


def main() -> None:
    parser = argparse.ArgumentParser(description="Simple Modbus TCP logging proxy")
    parser.add_argument("--listen-host", default="0.0.0.0")
    parser.add_argument("--listen-port", type=int, default=1502)
    parser.add_argument("--upstream-host", required=True)
    parser.add_argument("--upstream-port", type=int, default=502)
    args = parser.parse_args()

    server = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
    server.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
    server.bind((args.listen_host, args.listen_port))
    server.listen(5)

    print(
        f"{now()} listening on {args.listen_host}:{args.listen_port}, forwarding to {args.upstream_host}:{args.upstream_port}",
        flush=True,
    )

    try:
        while True:
            client_sock, client_addr = server.accept()
            print(f"{now()} accepted {client_addr[0]}:{client_addr[1]}", flush=True)
            threading.Thread(
                target=handle_client,
                args=(client_sock, args.upstream_host, args.upstream_port),
                daemon=True,
            ).start()
    except KeyboardInterrupt:
        pass
    finally:
        server.close()


if __name__ == "__main__":
    main()