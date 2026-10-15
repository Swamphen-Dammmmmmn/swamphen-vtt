"""Protocol unit checks, isolated from the live service and game clients."""
import asyncio
import json
import os
import unittest

import signaling
from compatibility import CONTRACT, valid_version
VERSION = {"app": "0.1.3a", **CONTRACT}
from websockets.exceptions import ConnectionClosedOK


class Socket:
    def __init__(self, messages=(), address="127.0.0.1"):
        self.messages = list(messages)
        self.sent = []
        self.closed = False
        self.close_options = {}
        self.remote_address = (address, 1)

    async def recv(self):
        if not self.messages:
            raise ConnectionClosedOK(None, None)
        return json.dumps(self.messages.pop(0))

    async def send(self, message):
        self.sent.append(json.loads(message))

    async def close(self, **_kwargs):
        self.closed = True
        self.close_options = _kwargs


class ProtocolChecks(unittest.IsolatedAsyncioTestCase):
    def test_revision_version_validation(self):
        self.assertTrue(valid_version({"app":"0.1.3a", **CONTRACT}))
        for app in ['0.1.3aa', '0.1.3A', '0.1.3a ', 'v0.1.3a']:
            self.assertFalse(valid_version({"app":app, **CONTRACT}))

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
        self.assertEqual(client.sent, [{"type": "room_closed", "reason": "host_disconnected"}])
        self.assertEqual(client.close_options, {"code":1000,"reason":"room_closed:host_disconnected"})

    async def test_explicit_host_close_is_distinguished(self):
        host, client = Socket(), Socket()
        host.close_code, host.close_reason = 1000, "host_closed"
        signaling.ROOMS["12345678"] = signaling.Room({1: host, 2: client})
        signaling.CONNECTIONS.update({host: ("12345678", 1), client: ("12345678", 2)})
        await signaling.leave(host)
        self.assertEqual(client.sent, [{"type": "room_closed", "reason": "host_closed"}])
        self.assertEqual(client.close_options, {"code":1000,"reason":"room_closed:host_closed"})
        self.assertFalse(signaling.ROOMS)
        self.assertFalse(signaling.CONNECTIONS)

    async def test_client_cannot_close_room_with_host_reason(self):
        host, client = Socket(), Socket()
        client.close_code, client.close_reason = 1000, "host_closed"
        signaling.ROOMS["12345678"] = signaling.Room({1: host, 2: client})
        signaling.CONNECTIONS.update({host: ("12345678", 1), client: ("12345678", 2)})
        await signaling.leave(client)
        self.assertIn("12345678", signaling.ROOMS)
        self.assertFalse(host.closed)
        self.assertEqual(host.sent, [{"type": "peer_left", "peer": 2}])

    async def test_slow_close_does_not_delay_other_notifications(self):
        release = asyncio.Event()
        notified = asyncio.Event()

        class SlowSocket(Socket):
            async def close(self, **kwargs):
                await release.wait()
                await super().close(**kwargs)

        class ObservedSocket(Socket):
            async def send(self, message):
                await super().send(message)
                notified.set()

        host, slow, fast = Socket(), SlowSocket(), ObservedSocket()
        host.close_code, host.close_reason = 1000, "host_closed"
        signaling.ROOMS["12345678"] = signaling.Room({1: host, 2: slow, 3: fast})
        signaling.CONNECTIONS.update({host: ("12345678", 1), slow: ("12345678", 2), fast: ("12345678", 3)})
        task = asyncio.create_task(signaling.leave(host))
        try:
            await asyncio.wait_for(notified.wait(), 1)
            self.assertEqual(fast.sent[0]["reason"], "host_closed")
        finally:
            release.set()
            await task

    async def test_client_cannot_kick_host(self):
        host = Socket()
        client = Socket([{"type": "kick", "peer": 1}])
        signaling.ROOMS["12345678"] = signaling.Room({1: host, 2: client})
        signaling.CONNECTIONS.update({host: ("12345678", 1), client: ("12345678", 2)})
        await signaling.handle(client)
        self.assertFalse(host.closed)
        self.assertIn("12345678", signaling.ROOMS)

    async def test_unknown_negotiation_fields_are_rejected(self):
        host = Socket()
        client = Socket([{"type": "forward", "peer": 1,
                          "data": {"kind": "candidate", "mid": "0", "index": 0,
                                   "candidate": "candidate:test", "extra": "discard"}}])
        signaling.ROOMS["12345678"] = signaling.Room({1: host, 2: client})
        signaling.CONNECTIONS.update({host: ("12345678", 1), client: ("12345678", 2)})
        await signaling.handle(client)
        self.assertTrue(client.closed)
        self.assertFalse(any(message["type"] == "forward" for message in host.sent))

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
        client = Socket([{"type": "create", "version": VERSION}], address="192.0.2.1")
        await signaling.handle(client)
        self.assertEqual(client.sent[0], {"type": "error", "reason": "busy"})
        self.assertEqual(len(signaling.ROOMS), 4)


    async def test_invalid_versions_do_not_allocate_rooms(self):
        variants = [None, {}, {**VERSION, "protocol": 1}, {**VERSION, "data_schema": 99},
                    {**VERSION, "protocol": True}, {**VERSION, "app": ""},
                    {**VERSION, "extra": "unknown"}]
        for version in variants:
            client = Socket([{"type": "create", "version": version}])
            await signaling.handle(client)
            self.assertEqual(client.sent[0]["reason"], "version_required")
            self.assertFalse(signaling.ROOMS)
            self.assertFalse(signaling.CONNECTIONS)

    async def test_different_app_is_rejected_before_peer_allocation(self):
        host = Socket()
        room = signaling.Room({1: host}, version=VERSION.copy())
        signaling.ROOMS["12345678"] = room
        client = Socket([{"type": "join", "room": "12345678",
                          "version": {**VERSION, "app": "0.1.4"}}])
        await signaling.handle(client)
        self.assertEqual(client.sent[0]["reason"], "version_mismatch")
        self.assertEqual(client.sent[0]["version"], VERSION)
        self.assertEqual(room.next_peer, 2)
        self.assertEqual(room.peers, {1: host})
        self.assertFalse(host.sent)

    async def test_matching_version_join(self):
        host = Socket()
        signaling.ROOMS["12345678"] = signaling.Room({1: host}, version=VERSION.copy())
        client = Socket([{"type": "join", "room": "12345678", "version": VERSION}])
        await signaling.handle(client)
        self.assertEqual(client.sent[0]["type"], "joined")
        self.assertEqual(client.sent[0]["version"], VERSION)
        self.assertEqual(host.sent[0], {"type": "peer_joined", "peer": 2})

    async def test_matching_version_create(self):
        client = Socket([{"type": "create", "version": VERSION}])
        await signaling.handle(client)
        self.assertEqual(client.sent[0]["type"], "created")
        self.assertEqual(client.sent[0]["version"], VERSION)
        self.assertFalse(signaling.ROOMS)

    async def test_supported_negotiation_preserves_all_fields(self):
        host = Socket()
        payload = {"kind": "candidate", "mid": "0", "index": 0, "candidate": "candidate:test"}
        client = Socket([{"type": "forward", "peer": 1, "data": payload}])
        signaling.ROOMS["12345678"] = signaling.Room({1: host, 2: client})
        signaling.CONNECTIONS.update({host: ("12345678", 1), client: ("12345678", 2)})
        await signaling.handle(client)
        self.assertEqual(host.sent[0]["data"], payload)


if __name__ == "__main__":
    unittest.main()
