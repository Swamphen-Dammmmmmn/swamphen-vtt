"""Infrastructure-only TLS/TURN check. Does not run Godot or load game data."""
import argparse
import asyncio
import hashlib
import hmac
import json
import secrets
import socket
import ssl
import struct

from websockets.asyncio.client import connect

MAGIC = 0x2112A442


def attribute(kind, value):
    return struct.pack("!HH", kind, len(value)) + value + b"\0" * (-len(value) % 4)


def packet(kind, values, authentication=None):
    transaction = secrets.token_bytes(12)
    length = len(values) + (24 if authentication else 0)
    data = struct.pack("!HHI", kind, length, MAGIC) + transaction + values
    if authentication:
        data += attribute(8, hmac.new(authentication, data, hashlib.sha1).digest())
    return data, transaction


def attributes(data):
    if len(data) < 20 or struct.unpack("!I", data[4:8])[0] != MAGIC:
        raise RuntimeError("Invalid STUN response")
    result, offset = {}, 20
    while offset + 4 <= len(data):
        kind, size = struct.unpack("!HH", data[offset:offset + 4])
        offset += 4
        result[kind] = data[offset:offset + size]
        offset += size + (-size % 4)
    return result


def address(value):
    if len(value) != 8 or value[1] != 1:
        raise RuntimeError("Expected IPv4 TURN address")
    port = struct.unpack("!H", value[2:4])[0] ^ 0x2112
    ip = bytes(a ^ b for a, b in zip(value[4:8], struct.pack("!I", MAGIC)))
    return socket.inet_ntoa(ip), port


def encode_address(endpoint):
    ip, port = endpoint
    raw = bytes(a ^ b for a, b in zip(socket.inet_aton(ip), struct.pack("!I", MAGIC)))
    return b"\0\1" + struct.pack("!H", port ^ 0x2112) + raw


class Allocation:
    def __init__(self, host, port, username, credential):
        self.socket = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
        self.socket.settimeout(8)
        self.server = (host, port)
        self.username = username.encode()
        requested = attribute(0x19, b"\x11\0\0\0")
        response = self.exchange(3, requested)
        challenge = attributes(response)
        if 0x14 not in challenge or 0x15 not in challenge:
            raise RuntimeError("TURN authentication challenge missing")
        self.realm, self.nonce = challenge[0x14], challenge[0x15]
        self.key = hashlib.md5(self.username + b":" + self.realm + b":" + credential.encode()).digest()
        response = self.exchange(3, requested, True)
        if struct.unpack("!H", response[:2])[0] != 0x103:
            raise RuntimeError("TURN authenticated allocation rejected")
        self.relay = address(attributes(response)[0x16])

    def exchange(self, kind, values, authenticated=False):
        if authenticated:
            values += attribute(6, self.username) + attribute(0x14, self.realm) + attribute(0x15, self.nonce)
        data, transaction = packet(kind, values, self.key if authenticated else None)
        self.socket.sendto(data, self.server)
        while True:
            response, source = self.socket.recvfrom(65536)
            if source == self.server and response[8:20] == transaction:
                return response

    def permit(self, peer):
        response = self.exchange(8, attribute(0x12, encode_address(peer)), True)
        if struct.unpack("!H", response[:2])[0] != 0x108:
            raise RuntimeError("TURN permission rejected")

    def close(self):
        try:
            self.exchange(4, attribute(0x0D, struct.pack("!I", 0)), True)
        finally:
            self.socket.close()


async def check(args):
    context = ssl.create_default_context(cafile=args.certificate)
    async with connect(f"wss://{args.host}:{args.signal_port}", ssl=context,
                       compression=None, open_timeout=12) as websocket:
        await websocket.send(json.dumps({"type": "create"}))
        response = json.loads(await websocket.recv())
        if response.get("type") != "created":
            raise RuntimeError("Signaling registration failed")
        credentials = response["ice_servers"][1]
        first = second = None
        try:
            first = Allocation(args.host, args.turn_port, credentials["username"], credentials["credential"])
            second = Allocation(args.host, args.turn_port, credentials["username"], credentials["credential"])
            if first.relay[0] != args.host or second.relay[0] != args.host:
                raise RuntimeError("TURN advertised an incorrect public relay address")
            first.permit(second.relay)
            second.permit(first.relay)
            payload = b"relay-infrastructure-check"
            message, _ = packet(0x16, attribute(0x12, encode_address(second.relay)) + attribute(0x13, payload))
            first.socket.sendto(message, first.server)
            received, _ = second.socket.recvfrom(65536)
            if attributes(received).get(0x13) != payload:
                raise RuntimeError("TURN relay data mismatch")
            print("TLS verified; signaling registration verified; authenticated TURN allocation and relay verified")
        finally:
            for allocation in [first, second]:
                if allocation:
                    allocation.close()


if __name__ == "__main__":
    parser = argparse.ArgumentParser()
    parser.add_argument("--host", required=True)
    parser.add_argument("--certificate", required=True)
    parser.add_argument("--signal-port", type=int, default=10130)
    parser.add_argument("--turn-port", type=int, default=10131)
    asyncio.run(check(parser.parse_args()))
