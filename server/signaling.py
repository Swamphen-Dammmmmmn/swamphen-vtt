"""In-memory connection coordination. No game messages, identities or files."""
import asyncio
import base64
import hashlib
import hmac
import json
import logging
import os
import secrets
import ssl
import time
from dataclasses import dataclass, field

from websockets.asyncio.server import serve
from websockets.exceptions import ConnectionClosed

logging.disable(logging.CRITICAL)
MAX_ROOMS = 64
MAX_PEERS = 16
ROOMS = {}
CONNECTIONS = {}
SOCKETS = set()


@dataclass
class Room:
    peers: dict = field(default_factory=dict)
    next_peer: int = 2


async def send(socket, data):
    try:
        async with asyncio.timeout(5):
            await socket.send(json.dumps(data, separators=(",", ":")))
        return True
    except (ConnectionClosed, TimeoutError):
        return False


def turn_servers():
    expires = int(time.time()) + 86400
    username = f"{expires}:{secrets.token_hex(8)}"
    credential = base64.b64encode(hmac.new(
        os.environ["TURN_SECRET"].encode(), username.encode(), hashlib.sha1
    ).digest()).decode()
    host = os.environ["PUBLIC_ADDRESS"]
    port = int(os.environ.get("TURN_PORT", "10131"))
    return [{"urls": [f"stun:{host}:{port}"]},
            {"urls": [f"turn:{host}:{port}?transport=udp"],
             "username": username, "credential": credential}]


async def leave(socket):
    existing = CONNECTIONS.pop(socket, None)
    if not existing:
        return
    code, peer_id = existing
    room = ROOMS.get(code)
    if not room:
        return
    room.peers.pop(peer_id, None)
    if peer_id == 1:
        ROOMS.pop(code, None)
        for peer in list(room.peers.values()):
            CONNECTIONS.pop(peer, None)
            await send(peer, {"type": "room_closed"})
            await peer.close()
    else:
        host = room.peers.get(1)
        if host:
            await send(host, {"type": "peer_left", "peer": peer_id})


async def handle(socket):
    if len(SOCKETS) >= 128:
        await socket.close(code=1013)
        return
    SOCKETS.add(socket)
    window, count = time.monotonic(), 0
    try:
        while True:
            try:
                async with asyncio.timeout(20 if socket not in CONNECTIONS else 120):
                    raw = await socket.recv()
            except TimeoutError:
                # Established hosts can keep their rooms open without messages.
                if socket in CONNECTIONS:
                    continue
                await socket.close(code=1008)
                return
            now = time.monotonic()
            if now - window >= 1:
                window, count = now, 0
            count += 1
            if count > 40 or not isinstance(raw, str):
                await socket.close(code=1008)
                return
            try:
                message = json.loads(raw)
            except (ValueError, TypeError):
                await socket.close(code=1008)
                return
            if not isinstance(message, dict):
                await socket.close(code=1008)
                return
            kind = message.get("type")
            if kind == "create" and socket not in CONNECTIONS:
                remote = socket.remote_address[0] if socket.remote_address else ""
                existing_hosts = sum(1 for room in ROOMS.values()
                                     if room.peers[1].remote_address and room.peers[1].remote_address[0] == remote)
                if existing_hosts >= 4:
                    await send(socket, {"type": "error", "reason": "busy"})
                    continue
                if len(ROOMS) >= MAX_ROOMS:
                    await send(socket, {"type": "error", "reason": "busy"})
                    continue
                code = secrets.token_hex(4).upper()
                while code in ROOMS:
                    code = secrets.token_hex(4).upper()
                ROOMS[code] = Room({1: socket})
                CONNECTIONS[socket] = (code, 1)
                await send(socket, {"type": "created", "room": code,
                                    "peer": 1, "ice_servers": turn_servers()})
            elif kind == "join" and socket not in CONNECTIONS:
                code = message.get("room")
                if not isinstance(code, str) or len(code) != 8:
                    await send(socket, {"type": "error", "reason": "missing"})
                    continue
                room = ROOMS.get(code.upper())
                if not room:
                    await send(socket, {"type": "error", "reason": "missing"})
                    continue
                if len(room.peers) >= MAX_PEERS:
                    await send(socket, {"type": "error", "reason": "full"})
                    continue
                peer_id = room.next_peer
                room.next_peer += 1
                room.peers[peer_id] = socket
                CONNECTIONS[socket] = (code.upper(), peer_id)
                await send(socket, {"type": "joined", "peer": peer_id,
                                    "ice_servers": turn_servers()})
                await send(room.peers[1], {"type": "peer_joined", "peer": peer_id})
            elif kind == "forward" and socket in CONNECTIONS:
                code, source = CONNECTIONS[socket]
                target = message.get("peer")
                payload = message.get("data")
                if type(target) is not int or not isinstance(payload, dict):
                    await socket.close(code=1008)
                    return
                # Only negotiation messages are accepted. Never game payloads.
                valid = (payload.get("kind") == "description"
                         and payload.get("description_type") in ("offer", "answer")
                         and isinstance(payload.get("sdp"), str)
                         and len(payload["sdp"]) <= 32768) or (
                    payload.get("kind") == "candidate"
                    and isinstance(payload.get("mid"), str)
                    and len(payload["mid"]) <= 256
                    and type(payload.get("index")) is int
                    and 0 <= payload["index"] <= 256
                    and isinstance(payload.get("candidate"), str)
                    and len(payload["candidate"]) <= 4096)
                if not valid or (source != 1 and target != 1) or target == source:
                    await socket.close(code=1008)
                    return
                fields = ("kind", "description_type", "sdp") if payload["kind"] == "description" else ("kind", "mid", "index", "candidate")
                payload = {key: payload[key] for key in fields}
                room = ROOMS.get(code)
                if room and target in room.peers:
                    await send(room.peers[target], {"type": "forward",
                               "peer": source, "data": payload})
            elif kind == "kick" and socket in CONNECTIONS:
                code, source = CONNECTIONS[socket]
                target = message.get("peer")
                if source == 1 and type(target) is int and target != 1:
                    peer = ROOMS[code].peers.get(target)
                    if peer:
                        await peer.close(code=1008)
            else:
                await socket.close(code=1008)
                return
    except ConnectionClosed:
        pass
    finally:
        await leave(socket)
        SOCKETS.discard(socket)


async def main():
    if not os.environ.get("PUBLIC_ADDRESS") or not os.environ.get("TURN_SECRET"):
        raise SystemExit("Missing service configuration")
    context = ssl.SSLContext(ssl.PROTOCOL_TLS_SERVER)
    context.minimum_version = ssl.TLSVersion.TLSv1_2
    context.load_cert_chain("/certs/public.crt", "/certs/private.key")
    async with serve(handle, "0.0.0.0", int(os.environ.get("SIGNAL_PORT", "10130")),
                     ssl=context, compression=None, max_size=65536, max_queue=8,
                     ping_interval=20, ping_timeout=20, close_timeout=3,
                     open_timeout=10, server_header=None):
        await asyncio.Future()


if __name__ == "__main__":
    asyncio.run(main())
