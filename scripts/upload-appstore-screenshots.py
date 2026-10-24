#!/usr/bin/env python3
"""Upload iPhone Duo screenshots to App Store Connect.

Validates the pixel sizes locally before touching the API, because App Store Connect only tells you
the size is wrong after the upload completes.

    python3 scripts/upload-appstore-screenshots.py --dir design/appstore/duo --dry-run
    python3 scripts/upload-appstore-screenshots.py --dir design/appstore/duo --version 1.1.14

Requires ASC_API_KEY and ASC_API_ISSUER in the environment, and the matching .p8 in
~/.appstoreconnect/private_keys/.

Notes
-----
* A released version is read-only. Screenshots can only be attached to a version in
  PREPARE_FOR_SUBMISSION, so `--version` names the version to create if it does not exist.
* The Duo display type is APP_IPHONE_DUO and accepts both poses in one set:
  outer 1398x2034, inner 2007x2853. Portrait only, no alpha channel.
"""

from __future__ import annotations

import argparse
import base64
import hashlib
import json
import os
import subprocess
import sys
import time
import urllib.error
import urllib.request
from pathlib import Path

BUNDLE_ID = "com.taption.encoder"
DISPLAY_TYPE = "APP_IPHONE_DUO"
REQUIRED_SIZES = {(1398, 2034), (2007, 2853)}
BASE = "https://api.appstoreconnect.apple.com"

KEY_ID = os.environ.get("ASC_API_KEY", "")
ISSUER = os.environ.get("ASC_API_ISSUER", "")
KEY_PATH = Path.home() / ".appstoreconnect" / "private_keys" / f"AuthKey_{KEY_ID}.p8"


# --- auth ---------------------------------------------------------------------------------------


def _b64(data: bytes) -> str:
    return base64.urlsafe_b64encode(data).rstrip(b"=").decode()


def _der_to_raw(der: bytes) -> bytes:
    """ECDSA DER -> fixed-width R||S, which is what JWT wants."""
    if der[0] != 0x30:
        raise ValueError(f"unexpected DER prefix {der[0]:#x}")
    index = 2
    if der[1] & 0x80:
        index = 2 + (der[1] & 0x7F)
    out = b""
    for _ in range(2):
        if der[index] != 0x02:
            raise ValueError("expected INTEGER")
        length = der[index + 1]
        value = der[index + 2: index + 2 + length]
        index += 2 + length
        out += value.lstrip(b"\x00").rjust(32, b"\x00")
    return out


def token() -> str:
    header = {"alg": "ES256", "kid": KEY_ID, "typ": "JWT"}
    now = int(time.time())
    payload = {"iss": ISSUER, "iat": now, "exp": now + 900, "aud": "appstoreconnect-v1"}
    signing_input = (
        f"{_b64(json.dumps(header, separators=(',', ':')).encode())}."
        f"{_b64(json.dumps(payload, separators=(',', ':')).encode())}"
    )
    signature = subprocess.run(
        ["openssl", "dgst", "-sha256", "-sign", str(KEY_PATH)],
        input=signing_input.encode(), capture_output=True, check=True,
    ).stdout
    return f"{signing_input}.{_b64(_der_to_raw(signature))}"


def call(path: str, method: str = "GET", body: dict | None = None, absolute: str | None = None):
    url = absolute or f"{BASE}{path}"
    data = json.dumps(body).encode() if body is not None else None
    request = urllib.request.Request(url, data=data, method=method)
    if absolute is None:
        request.add_header("Authorization", f"Bearer {token()}")
    if data:
        request.add_header("Content-Type", "application/json")
    try:
        with urllib.request.urlopen(request, timeout=120) as response:
            raw = response.read()
            return response.status, (json.loads(raw) if raw else {})
    except urllib.error.HTTPError as error:
        raw = error.read()
        try:
            return error.code, json.loads(raw)
        except Exception:
            return error.code, {"raw": raw.decode(errors="replace")}


def fail(message: str, payload=None) -> None:
    print(f"error: {message}", file=sys.stderr)
    if payload:
        print(json.dumps(payload, indent=2)[:2000], file=sys.stderr)
    sys.exit(1)


# --- local validation ---------------------------------------------------------------------------


def image_size(path: Path) -> tuple[int, int]:
    """Read the pixel size from the PNG header without Pillow."""
    with path.open("rb") as handle:
        header = handle.read(24)
    if header[:8] != b"\x89PNG\r\n\x1a\n":
        fail(f"{path.name} is not a PNG")
    return int.from_bytes(header[16:20], "big"), int.from_bytes(header[20:24], "big")


def validate(files: list[Path]) -> None:
    if not files:
        fail("no PNG files found")
    seen = set()
    for path in files:
        width, height = image_size(path)
        if (width, height) not in REQUIRED_SIZES:
            fail(f"{path.name} is {width}x{height}; Duo accepts {sorted(REQUIRED_SIZES)}")
        with path.open("rb") as handle:
            if b"tRNS" in handle.read():
                fail(f"{path.name} has an alpha channel; App Store rejects transparency")
        seen.add((width, height))
        print(f"  ok  {path.name}  {width}x{height}  {path.stat().st_size // 1024} KB")
    missing = REQUIRED_SIZES - seen
    if missing:
        print(f"  warn: no image for {sorted(missing)} — one pose will be missing from the set",
              file=sys.stderr)


# --- app store connect --------------------------------------------------------------------------


def find_app() -> str:
    status, payload = call(f"/v1/apps?filter%5BbundleId%5D={BUNDLE_ID}")
    if status != 200 or not payload.get("data"):
        fail(f"no app record for {BUNDLE_ID}", payload)
    return payload["data"][0]["id"]


def editable_version(app_id: str, version: str, create: bool) -> str:
    status, payload = call(
        f"/v1/apps/{app_id}/appStoreVersions"
        "?fields%5BappStoreVersions%5D=versionString,appStoreState&limit=20")
    if status != 200:
        fail("could not list versions", payload)
    for item in payload["data"]:
        state = item["attributes"]["appStoreState"]
        if state == "PREPARE_FOR_SUBMISSION":
            print(f"  using editable version {item['attributes']['versionString']} ({state})")
            return item["id"]
    if not create:
        fail("no version in PREPARE_FOR_SUBMISSION; a released version cannot be edited.\n"
             "       Re-run with --version <new version> to create one.")
    status, payload = call("/v1/appStoreVersions", "POST", {"data": {
        "type": "appStoreVersions",
        "attributes": {"versionString": version, "platform": "IOS"},
        "relationships": {"app": {"data": {"type": "apps", "id": app_id}}},
    }})
    if status not in (200, 201):
        fail("could not create the version", payload)
    print(f"  created version {version}")
    return payload["data"]["id"]


def localization(version_id: str, locale: str = "en-US") -> str:
    status, payload = call(
        f"/v1/appStoreVersions/{version_id}/appStoreVersionLocalizations"
        "?fields%5BappStoreVersionLocalizations%5D=locale")
    if status != 200:
        fail("could not list localizations", payload)
    for item in payload["data"]:
        if item["attributes"]["locale"] == locale:
            return item["id"]
    return payload["data"][0]["id"]


def screenshot_set(localization_id: str) -> str:
    status, payload = call(
        f"/v1/appStoreVersionLocalizations/{localization_id}/appScreenshotSets"
        "?fields%5BappScreenshotSets%5D=screenshotDisplayType")
    if status != 200:
        fail("could not list screenshot sets", payload)
    for item in payload["data"]:
        if item["attributes"]["screenshotDisplayType"] == DISPLAY_TYPE:
            print(f"  reusing the existing {DISPLAY_TYPE} set")
            return item["id"]
    status, payload = call("/v1/appScreenshotSets", "POST", {"data": {
        "type": "appScreenshotSets",
        "attributes": {"screenshotDisplayType": DISPLAY_TYPE},
        "relationships": {"appStoreVersionLocalization": {
            "data": {"type": "appStoreVersionLocalizations", "id": localization_id}}},
    }})
    if status not in (200, 201):
        fail("could not create the screenshot set", payload)
    print(f"  created the {DISPLAY_TYPE} set")
    return payload["data"]["id"]


def upload(set_id: str, path: Path) -> None:
    data = path.read_bytes()
    status, payload = call("/v1/appScreenshots", "POST", {"data": {
        "type": "appScreenshots",
        "attributes": {"fileName": path.name, "fileSize": len(data)},
        "relationships": {"appScreenshotSet": {
            "data": {"type": "appScreenshotSets", "id": set_id}}},
    }})
    if status not in (200, 201):
        fail(f"could not reserve {path.name}", payload)

    screenshot = payload["data"]
    for operation in screenshot["attributes"].get("uploadOperations", []):
        chunk = data[operation["offset"]: operation["offset"] + operation["length"]]
        request = urllib.request.Request(operation["url"], data=chunk, method=operation["method"])
        for header in operation.get("requestHeaders", []):
            request.add_header(header["name"], header["value"])
        with urllib.request.urlopen(request, timeout=180) as response:
            if response.status not in (200, 201):
                fail(f"chunk upload failed with {response.status}")

    status, payload = call(f"/v1/appScreenshots/{screenshot['id']}", "PATCH", {"data": {
        "type": "appScreenshots", "id": screenshot["id"],
        "attributes": {"uploaded": True},
    }})
    if status != 200:
        fail(f"could not commit {path.name}", payload)

    for _ in range(20):
        status, payload = call(
            f"/v1/appScreenshots/{screenshot['id']}?fields%5BappScreenshots%5D=assetDeliveryState")
        state = payload.get("data", {}).get("attributes", {}).get("assetDeliveryState", {})
        if state.get("state") == "COMPLETE":
            print(f"  uploaded {path.name}")
            return
        if state.get("state") == "FAILED":
            fail(f"{path.name} was rejected", state)
        time.sleep(3)
    print(f"  warn: {path.name} is still processing", file=sys.stderr)


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--dir", default="design/appstore/duo")
    parser.add_argument("--version", default=None, help="version to create if none is editable")
    parser.add_argument("--locale", default="en-US")
    parser.add_argument("--dry-run", action="store_true")
    args = parser.parse_args()

    files = sorted(Path(args.dir).glob("*.png"))
    print("==> Validating")
    validate(files)

    if args.dry_run:
        print("==> Dry run, nothing uploaded")
        return

    if not KEY_ID or not ISSUER:
        fail("set ASC_API_KEY and ASC_API_ISSUER")
    if not KEY_PATH.exists():
        fail(f"missing key at {KEY_PATH}")

    print("==> Resolving")
    app_id = find_app()
    version_id = editable_version(app_id, args.version, create=args.version is not None)
    localization_id = localization(version_id, args.locale)
    set_id = screenshot_set(localization_id)

    print("==> Uploading")
    for path in files:
        upload(set_id, path)
    print("==> Done. Review the screenshots in App Store Connect before submitting.")


if __name__ == "__main__":
    main()
