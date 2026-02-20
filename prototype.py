#!/usr/bin/env python3
"""Quick prototype to test the search.ch + transport.opendata.ch API flow."""

import sys
import json
import urllib.request
from datetime import datetime, timezone

DEFAULT_LAT = 46.2312
DEFAULT_LON = 7.3577


def fetch_json(url):
    req = urllib.request.Request(url, headers={"User-Agent": "traintime-prototype/0.1"})
    with urllib.request.urlopen(req) as resp:
        return json.loads(resp.read())


def find_stations(lat, lon, radius=2000):
    url = (
        f"https://search.ch/timetable/api/completion.en.json"
        f"?latlon={lat},{lon}&accuracy={radius}&show_ids=1&show_coordinates=1"
    )
    print(f"\n--- Station search ---")
    print(f"GET {url}\n")
    data = fetch_json(url)
    print(f"Found {len(data)} stations:")
    for s in data:
        dist = s.get("dist", "?")
        print(f"  {s.get('label', '?'):30s}  id={s.get('id', 'N/A'):10s}  dist={dist}m")
    return data


def get_stationboard(station_id, station_name, limit=8):
    url = (
        f"https://transport.opendata.ch/v1/stationboard"
        f"?id={station_id}&limit={limit}"
        f"&fields[]=stationboard/to"
        f"&fields[]=stationboard/category"
        f"&fields[]=stationboard/number"
        f"&fields[]=stationboard/stop/departureTimestamp"
        f"&fields[]=stationboard/stop/delay"
        f"&fields[]=stationboard/stop/platform"
        f"&fields[]=stationboard/stop/prognosis/platform"
        f"&fields[]=stationboard/stop/prognosis/departure"
    )
    print(f"\n--- Stationboard: {station_name} ---")
    print(f"GET {url}\n")
    data = fetch_json(url)

    now_ts = datetime.now(timezone.utc).timestamp()
    departures = data.get("stationboard", [])

    if not departures:
        print("  No departures found.")
        return

    print(f"  {'MIN':>5}  {'DELAY':>5}  {'PL':>4}  {'CAT':>4}  DESTINATION")
    print(f"  {'---':>5}  {'-----':>5}  {'--':>4}  {'---':>4}  -----------")

    for dep in departures:
        dest = dep.get("to", "?")
        category = dep.get("category", "")
        number = dep.get("number", "")
        stop = dep.get("stop", {})

        dep_ts = stop.get("departureTimestamp")
        delay = stop.get("delay", 0) or 0
        platform = stop.get("platform", "")

        # Check for platform change
        prognosis = stop.get("prognosis") or {}
        prog_platform = prognosis.get("platform")
        pl_changed = prog_platform and platform and prog_platform != platform
        if pl_changed:
            platform = f"{prog_platform}!"

        # Minutes until departure (scheduled)
        if dep_ts:
            mins = int((dep_ts - now_ts) / 60)
            min_str = f"{mins}'"
        else:
            min_str = "?"

        delay_str = f"+{delay}" if delay > 0 else ""

        print(f"  {min_str:>5}  {delay_str:>5}  {platform:>4}  {category+number:>4}  {dest}")


def main():
    if len(sys.argv) >= 3:
        lat, lon = float(sys.argv[1]), float(sys.argv[2])
    else:
        lat, lon = DEFAULT_LAT, DEFAULT_LON
        print(f"Usage: {sys.argv[0]} <lat> <lon>")
        print(f"Using default: EPFL Valais/Sion (Alpole) @ {lat}, {lon}")

    stations = find_stations(lat, lon)

    if not stations:
        print("No stations found!")
        sys.exit(1)

    # Use the closest station
    best = stations[0]
    station_id = best.get("id")
    station_name = best.get("label", "?")
    dist = best.get("dist", "?")

    print(f"\nUsing closest: {station_name} ({dist}m away)")
    get_stationboard(station_id, station_name)


if __name__ == "__main__":
    main()
