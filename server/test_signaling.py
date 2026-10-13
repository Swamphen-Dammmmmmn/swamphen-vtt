"""Protocol unit checks, isolated from the live service and game clients."""
import asyncio
import json
import os
import unittest

import signaling
from websockets.exceptions import ConnectionClosedOK


class Socket:
    def __init__(self, messages=(), address="127.0.0.1"):
        self.messages = list(messages)
        self.sent = []
        self.closed = False
        self.remote_address = (address, 1)

    async def recv(self):
        if not self.messages:
            raise ConnectionClosedOK(None, None)
        return json.dumps(self.messages.pop(0))

    async def send(self, message):
        self.sent.append(json.loads(message))

    async def close(self, **_kwargs):
        self.closed = True


class ProtocolChecks(unittest.IsolatedAsyncioTestCase):
    def setUp(self):
        signaling.ROOMS.clear()
        signaling.CONNECTIONS.clear()
        signaling.SOCKETS.clear()
        os.environ["TURN_SECRET"] = "unit-test-only"
        os.environ["PUBLIC_ADDRESS"] = "127.0.0.1"

    async def test_host_departure_removes_room_and_connections(self):
        host, client = Socket(), Socket()
        signaling.ROOMS["12345678"] = signaling.Room({1: host, 2: client})
        signaling.CONNECTIONS.update({host: ("12345678", 1), client: ("12345678", 2)})
        await signaling.leave(host)
        self.assertFalse(signaling.ROOMS)
        self.assertFalse(signaling.CONNECTIONS)
        self.assertTrue(client.closed)
        self.assertEqual(client.sent, [{"type": "room_closed"}])

    async def test_client_cannot_kick_host(self):
        host = Socket()
        client = Socket([{"type": "kick", "peer": 1}])
        signaling.ROOMS["12345678"] = signaling.Room({1: host, 2: client})
        signaling.CONNECTIONS.update({host: ("12345678", 1), client: ("12345678", 2)})
        await signaling.handle(client)
        self.assertFalse(host.closed)
        self.assertIn("12345678", signaling.ROOMS)

    async def test_forward_only_negotiation_and_strip_extra_fields(self):
        host = Socket()
        client = Socket([{"type": "forward", "peer": 1,
                          "data": {"kind": "candidate", "mid": "0", "index": 0,
                                   "candidate": "candidate:test", "extra": "discard"}}])
        signaling.ROOMS["12345678"] = signaling.Room({1: host, 2: client})
        signaling.CONNECTIONS.update({host: ("12345678", 1), client: ("12345678", 2)})
        await signaling.handle(client)
        self.assertNotIn("extra", host.sent[0]["data"])
        self.assertEqual(host.sent[0]["peer"], 2)

    async def test_arbitrary_game_payload_is_rejected(self):
        host = Socket()
        client = Socket([{"type": "forward", "peer": 1,
                          "data": {"kind": "game", "payload": "discard"}}])
        signaling.ROOMS["12345678"] = signaling.Room({1: host, 2: client})
        signaling.CONNECTIONS.update({host: ("12345678", 1), client: ("12345678", 2)})
        await signaling.handle(client)
        self.assertTrue(client.closed)
        self.assertFalse(any(message["type"] == "forward" for message in host.sent))

    async def test_private_address_room_limit(self):
        for number in range(4):
            host = Socket(address="192.0.2.1")
            signaling.ROOMS[str(number)] = signaling.Room({1: host})
        client = Socket([{"type": "create"}], address="192.0.2.1")
        await signaling.handle(client)
        self.assertEqual(client.sent[0], {"type": "error", "reason": "busy"})
        self.assertEqual(len(signaling.ROOMS), 4)


if __name__ == "__main__":
    unittest.main()
