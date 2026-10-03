"""Command line test tool: read/set the soundbar volume.

    volume.py get | set N | up [N] | down [N] | mute | unmute | refresh | listen

The soundbar is taken from the SoundbarKeys app (the one it found last), otherwise it is
searched via Bonjour. With several Bose devices on the network, pass --host and --guid.
"""

import argparse
import asyncio
import json
import plistlib
import ssl
import subprocess
import time

import jwt
import websockets
from pybose.BoseAuth import BoseAuth
from zeroconf import ServiceBrowser, ServiceStateChange, Zeroconf

import tokenstore

PRODUCT_QUERY = "product=Madrid-iOS:31019F02-F01F-4E73-B495-B96D33AD3664"
SERVICE_TYPE = "_bose-passport._tcp.local."
DISCOVERY_SECONDS = 3
API_PORT = 8082
REFRESH_MARGIN_SECONDS = 300
RESPONSE_TIMEOUT_SECONDS = 10
DEFAULT_STEP = 4
APP_BUNDLE_ID = "io.github.niko11111.SoundbarKeys"


def token_exp(token: str) -> int:
    return jwt.decode(token, options={"verify_signature": False})["exp"]


def fmt(ts: int) -> str:
    return time.strftime("%Y-%m-%d %H:%M", time.localtime(ts))


def access_token(force_refresh: bool = False) -> str:
    t = tokenstore.load()
    if force_refresh or token_exp(t["access_token"]) - time.time() < REFRESH_MARGIN_SECONDS:
        print(f"Token valid until {fmt(token_exp(t['access_token']))}, refreshing ...")
        auth = BoseAuth()
        auth.set_access_token(t["access_token"], t["refresh_token"], t["bose_person_id"])
        auth.set_azure_refresh_token(t["azure_refresh_token"])
        new = auth.do_token_refresh()
        t = {**new, "azure_refresh_token": auth.get_azure_refresh_token()}
        tokenstore.save(t)
        print(f"Refreshed, new token valid until {fmt(token_exp(t['access_token']))}")
    return t["access_token"]


def discover(timeout: float = DISCOVERY_SECONDS) -> list[tuple[str, str]]:
    """(IP, GUID) of every Bose ECO2 device. Names are collected first and resolved afterwards:
    resolving inside the browser callback (as pybose's BoseDiscovery does) blocks and times out."""
    zc = Zeroconf()
    names: list[str] = []
    try:
        ServiceBrowser(zc, SERVICE_TYPE, handlers=[
            lambda zeroconf, service_type, name, state_change:
                names.append(name) if state_change is ServiceStateChange.Added else None
        ])
        time.sleep(timeout)
        devices = []
        for name in names:
            info = zc.get_service_info(SERVICE_TYPE, name, timeout=int(timeout * 1000))
            guid = info and info.properties.get(b"GUID")
            if guid and info.parsed_addresses():
                devices.append((info.parsed_addresses()[0], guid.decode()))
        return devices
    finally:
        zc.close()


def app_cached_device() -> tuple[str, str] | None:
    """(host, GUID) of the soundbar the SoundbarKeys app found last (stored in its UserDefaults).
    Python's own multicast discovery is often blocked by macOS Local Network privacy."""
    out = subprocess.run(["defaults", "export", APP_BUNDLE_ID, "-"], capture_output=True)
    if out.returncode != 0:
        return None
    try:
        cached = json.loads(plistlib.loads(out.stdout).get("soundbar", b"null"))
    except (plistlib.InvalidFileException, ValueError):
        return None
    return (cached["host"], cached["guid"]) if cached else None


def find_device(host: str | None, guid: str | None) -> tuple[str, str]:
    if host and guid:
        return host, guid
    cached = app_cached_device()
    if cached and host is None and guid in (None, cached[1]):
        return cached
    for ip, device_guid in discover():
        if (host is None or ip == host) and (guid is None or device_guid == guid):
            return ip, device_guid
    raise SystemExit("No Bose device found on the network.")


class Client:
    def __init__(self, ws, token: str, guid: str):
        self.ws, self.token, self.guid, self.req_id = ws, token, guid, 0

    async def request(self, method: str, resource: str, body: dict | None = None) -> dict:
        self.req_id += 1
        await self.ws.send(json.dumps({
            "header": {"device": self.guid, "method": method, "msgtype": "REQUEST",
                       "reqID": self.req_id, "resource": resource, "status": 200,
                       "token": self.token, "version": 1},
            "body": body or {},
        }))
        while True:
            msg = json.loads(await asyncio.wait_for(self.ws.recv(), RESPONSE_TIMEOUT_SECONDS))
            h = msg["header"]
            if h.get("msgtype") == "RESPONSE" and h.get("reqID") == self.req_id:
                if h.get("status") != 200:
                    raise RuntimeError(f"{method} {resource} -> {h.get('status')}: {msg.get('error')}")
                return msg.get("body", {})


async def main(args: argparse.Namespace) -> None:
    token = access_token(force_refresh=(args.command == "refresh"))
    if args.command == "refresh":
        return

    host, guid = find_device(args.host, args.guid)
    ctx = ssl.SSLContext(ssl.PROTOCOL_TLS_CLIENT)
    ctx.check_hostname = False
    ctx.verify_mode = ssl.CERT_NONE  # the soundbar uses a self-signed certificate
    url = f"wss://{host}:{API_PORT}/?{PRODUCT_QUERY}"
    async with websockets.connect(url, subprotocols=["eco2"], ssl=ctx, open_timeout=RESPONSE_TIMEOUT_SECONDS) as ws:
        # PUTs sent before "FrontDoorReady" are acknowledged but ignored.
        while json.loads(await asyncio.wait_for(ws.recv(), RESPONSE_TIMEOUT_SECONDS))["header"].get("resource") != "FrontDoorReady":
            pass

        c = Client(ws, token, guid)
        if args.command == "listen":
            # Subscribe without waiting for the response; everything is printed below anyway.
            await ws.send(json.dumps({
                "header": {"device": guid, "method": "PUT", "msgtype": "REQUEST", "reqID": 0,
                           "resource": "/subscription", "status": 200, "token": token, "version": 2},
                "body": {"notifications": [{"resource": "/audio/volume", "version": 1}]},
            }))
            print("Waiting for volume notifications (Ctrl+C to stop) ...")
            async for raw in ws:
                print(raw[:500])
            return

        vol = await c.request("GET", "/audio/volume")
        step = args.value if args.value is not None else DEFAULT_STEP
        if args.command == "set":
            vol = await c.request("PUT", "/audio/volume", {"value": args.value})
        elif args.command == "up":
            vol = await c.request("PUT", "/audio/volume", {"value": min(vol["max"], vol["value"] + step)})
        elif args.command == "down":
            vol = await c.request("PUT", "/audio/volume", {"value": max(0, vol["value"] - step)})
        elif args.command in ("mute", "unmute"):
            vol = await c.request("PUT", "/audio/volume", {"muted": args.command == "mute"})
        print(json.dumps({k: vol.get(k) for k in ("value", "muted", "min", "max")}))


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("command", choices=["get", "set", "up", "down", "mute", "unmute", "refresh", "listen"])
    parser.add_argument("value", nargs="?", type=int, help="volume for 'set', step for 'up'/'down'")
    parser.add_argument("--host", help="IP address of the soundbar (skips discovery together with --guid)")
    parser.add_argument("--guid", help="device GUID")
    a = parser.parse_args()
    if a.command == "set" and a.value is None:
        parser.error("'set' needs a value")
    asyncio.run(main(a))
