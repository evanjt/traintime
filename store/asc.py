#!/usr/bin/env python3
"""Upload the App Store header and search assets through the App Store Connect API.

fastlane does not cover the asset library yet, so this does the reserve, upload,
commit and place steps for store/manual/app-store/<locale>/{header,search}.

    export ASC_KEY_ID=... ASC_ISSUER_ID=... ASC_KEY_PATH=~/.appstoreconnect/AuthKey_XXX.p8
    python3 store/asc.py refdata              # writes the asset specs to store/out/
    python3 store/asc.py upload 0.8.0         # places every asset on that version
    python3 store/asc.py upload 0.8.0 --still # the png instead of the mp4
"""

import argparse
import json
import os
import sys
import time
from pathlib import Path

import socket

import jwt
import requests
from urllib3.connection import HTTPConnection

API = "https://api.appstoreconnect.apple.com/v1"
APP_ID = "6760388620"
SCRIPT_DIR = Path(__file__).resolve().parent
ASSETS = SCRIPT_DIR / "manual" / "app-store"
OUT = SCRIPT_DIR / "out"

# App Store locale -> asset folder; en-GB and en-AU share the English set.
LOCALES = {"en-AU": "en-AU", "en-GB": "en-AU", "de-DE": "de-DE", "fr-FR": "fr-FR", "it": "it-IT"}


def blob_session():
    # Apple's upload hosts answer full-size segments, which a jumbo-frame LAN with a
    # path MTU black hole drops; a 1400-byte MSS keeps every packet under 1500.
    opts = HTTPConnection.default_socket_options + [(socket.IPPROTO_TCP, socket.TCP_MAXSEG, 1400)]
    adapter = requests.adapters.HTTPAdapter(max_retries=2)
    adapter.init_poolmanager(10, 10, socket_options=opts)
    s = requests.Session()
    s.mount("https://", adapter)
    return s


def token():
    key = Path(os.path.expanduser(os.environ["ASC_KEY_PATH"])).read_text()
    now = int(time.time())
    claims = {"iss": os.environ["ASC_ISSUER_ID"], "iat": now, "exp": now + 1200,
              "aud": "appstoreconnect-v1"}
    return jwt.encode(claims, key, algorithm="ES256", headers={"kid": os.environ["ASC_KEY_ID"]})


class Client:
    def __init__(self):
        self.s = requests.Session()
        self.s.headers["Authorization"] = f"Bearer {token()}"

    def call(self, method, path, body=None, **params):
        r = self.s.request(method, path if path.startswith("http") else API + path,
                           json=body, params=params or None, timeout=60)
        if r.status_code >= 400:
            sys.exit(f"{method} {path}: {r.status_code}\n{r.text}")
        return r.json() if r.content else None


def refdata(c):
    OUT.mkdir(exist_ok=True)
    data = c.call("GET", "/appAssetLibraryRefData")
    (OUT / "asc-refdata.json").write_text(json.dumps(data, indent=2))
    for word in ("HEADER", "SEARCH"):
        found = sorted({s for s in _strings(data) if word in s})
        print(word.lower(), found)
    print("full reference data in", OUT / "asc-refdata.json")


def _strings(node):
    if isinstance(node, str):
        yield node
    elif isinstance(node, dict):
        for v in node.values():
            yield from _strings(v)
    elif isinstance(node, list):
        for v in node:
            yield from _strings(v)


def reserve_upload_commit(c, library, path, kind):
    rtype = "appAssetLibraryVideos" if kind == "video" else "appAssetLibraryImages"
    name = f"{path.parent.name} {path.stem} {kind}"
    attrs = {"fileName": path.name, "fileSize": path.stat().st_size,
             "category": "CREATIVE_ASSETS", "referenceName": name}
    # A rerun after a failed upload finds its own reservation under the same name.
    folder = "videos" if kind == "video" else "images"
    for old in c.call("GET", f"/appAssetLibraries/{library}/{folder}",
                      **{"filter[referenceName]": name})["data"]:
        if old["attributes"]["state"] in ("AWAITING_UPLOAD", "FAILED"):
            c.call("DELETE", f"/{rtype}/{old['id']}")
        else:
            attrs["referenceName"] = f"{name} {int(time.time())}"
    if kind == "video":
        attrs["previewFrameTimeCode"] = "00:00:00:00"
    asset = c.call("POST", f"/{rtype}", {"data": {
        "type": rtype, "attributes": attrs,
        "relationships": {"assetLibrary": {"data": {"type": "appAssetLibraries", "id": library}}}}})["data"]
    blob = path.read_bytes()
    uploader = blob_session()
    for op in asset["attributes"]["uploadOperations"]:
        part = blob[op["offset"]:op["offset"] + op["length"]]
        headers = {h["name"]: h["value"] for h in op["requestHeaders"]}
        for attempt in range(3):
            r = uploader.request(op["method"], op["url"], data=part, headers=headers, timeout=300)
            if r.ok:
                break
        else:
            sys.exit(f"upload of {path} failed: {r.status_code} {r.text}")
    c.call("PATCH", f"/{rtype}/{asset['id']}", {"data": {
        "type": rtype, "id": asset["id"], "attributes": {"uploaded": True}}})
    while True:
        state = c.call("GET", f"/{rtype}/{asset['id']}")["data"]["attributes"]
        if state["state"] == "PREPARE_FOR_SUBMISSION":
            return rtype, asset["id"]
        if state["state"] == "FAILED":
            sys.exit(f"{path} failed processing: {state.get('stateDetails')}")
        time.sleep(5)


def upload(c, version, still, types, group):
    library = c.call("GET", f"/apps/{APP_ID}/assetLibrary")["data"]["id"]
    v = c.call("GET", f"/apps/{APP_ID}/appStoreVersions",
               **{"filter[versionString]": version, "filter[platform]": "IOS"})["data"]
    if not v:
        sys.exit(f"no iOS version {version}")
    locs = c.call("GET", f"/appStoreVersions/{v[0]['id']}/appStoreVersionLocalizations", limit=50)["data"]
    kind, ext = ("image", "png") if still else ("video", "mp4")
    for loc in locs:
        folder = LOCALES.get(loc["attributes"]["locale"])
        if not folder:
            print("skip", loc["attributes"]["locale"])
            continue
        for name, ptype in types.items():
            path = ASSETS / folder / f"{name}.{ext}"
            existing = c.call("GET", f"/appStoreVersionLocalizations/{loc['id']}/placements",
                              **{"filter[placementType]": ptype})["data"]
            rtype, asset = reserve_upload_commit(c, library, path, kind)
            for p in existing:
                c.call("DELETE", f"/appAssetLibraryPlacements/{p['id']}")
            c.call("POST", "/appAssetLibraryPlacements", {"data": {
                "type": "appAssetLibraryPlacements",
                "attributes": {"placementType": ptype, "placementGroup": group},
                "relationships": {
                    kind: {"data": {"type": rtype, "id": asset}},
                    "appStoreVersionLocalization": {"data": {"type": "appStoreVersionLocalizations",
                                                             "id": loc["id"]}}}}})
            print(f"{loc['attributes']['locale']} {name} placed from {path.relative_to(SCRIPT_DIR)}")


def main():
    ap = argparse.ArgumentParser()
    sub = ap.add_subparsers(dest="cmd", required=True)
    sub.add_parser("refdata")
    up = sub.add_parser("upload")
    up.add_argument("version")
    up.add_argument("--still", action="store_true")
    up.add_argument("--header-type", default="PRODUCT_PAGE_HEADER_ASSET")
    up.add_argument("--search-type", default="APP_STORE_SEARCH_RESULTS_ASSET")
    up.add_argument("--group", default="DEFAULT_PROFILE")
    args = ap.parse_args()
    c = Client()
    if args.cmd == "refdata":
        refdata(c)
    else:
        upload(c, args.version, args.still,
               {"header": args.header_type, "search": args.search_type}, args.group)


if __name__ == "__main__":
    main()
