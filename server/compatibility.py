"""Shared protocol declaration; room versions exist only in memory."""
import json
import os
import re
from pathlib import Path

CONTRACT_PATH = Path(os.environ.get("NETWORK_CONTRACT", Path(__file__).resolve().parent.parent / "assets/network/contract.json"))
CONTRACT = json.loads(CONTRACT_PATH.read_text(encoding="utf-8"))
if set(CONTRACT) != {"protocol", "data_schema"} or any(type(v) is not int or v < 1 for v in CONTRACT.values()):
    raise RuntimeError("Invalid network contract configuration")


def valid_version(value):
    return (type(value) is dict and set(value) == {"app", "protocol", "data_schema"}
            and type(value["app"]) is str
            and re.fullmatch(r"[0-9]+\.[0-9]+\.[0-9]+[a-z]?(?:[-+][A-Za-z0-9.-]+)?", value["app"]) is not None
            and len(value["app"]) <= 64
            and all(type(value[key]) is int and value[key] == CONTRACT[key] for key in CONTRACT))
