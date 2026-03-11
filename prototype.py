#!/usr/bin/env python3
"""Quick prototype to test the traintime-api Cloudflare Worker."""

import sys
import json
import urllib.request
from datetime import datetime, timezone

DEFAULT_LAT = 46.2312
DEFAULT_LON = 7.3577
BASE_URL = "http://localhost:8787"


def fetch_json(url):
    req = urllib.request.Request(url, headers={"User-Agent": "traintime-prototype/0.1"})
    with urllib.request.urlopen(req) as resp:
        return json.loads(resp.read())


def find_stations(lat, lon):
    url = f"{BASE_URL}/v1/nearby?lat={lat}&lon={lon}"
    print(f"\n--- Nearby stations ---")
    print(f"GET {url}\n")
    data = fetch_json(url)

    all_stations = {}
    for mode in ("train", "bus", "tram"):
        stations = data.get(mode, [])
        if stations:
            all_stations[mode] = stations
            print(f"  {mode.upper()} ({len(stations)}):")
            for s in stations:
                has_deps = " [departures]" if s.get("departures") else ""
                print(f"    {s.get('name', '?'):30s}  id={s.get('id', 'N/A'):10s}  dist={s.get('dist', '?')}m{has_deps}")
            print()

    if not all_stations:
        print("  No stations found.")

    return all_stations


def show_departures(departures, station_name):
    print(f"\n--- Departures: {station_name} ---\n")
    now_ts = datetime.now(timezone.utc).timestamp()

    if not departures:
        print("  No departures found.")
        return

    print(f"  {'MIN':>5}  {'DELAY':>5}  {'PL':>4}  DESTINATION")
    print(f"  {'---':>5}  {'-----':>5}  {'--':>4}  -----------")

    for dep in departures:
        dest = dep.get("to", "?")
        dep_ts = dep.get("departure")
        delay = dep.get("delay", 0) or 0
        platform = dep.get("platform", "")
        pl_changed = dep.get("platformChanged", False)

        if pl_changed and platform:
            platform = f"{platform}!"

        if dep_ts:
            mins = int((dep_ts - now_ts) / 60)
            min_str = f"{mins}'"
        else:
            min_str = "?"

        delay_str = f"+{delay}" if delay > 0 else ""

        print(f"  {min_str:>5}  {delay_str:>5}  {platform:>4}  {dest}")


def get_departures(station_id, station_name, limit=8):
    url = f"{BASE_URL}/v1/departures?id={station_id}&limit={limit}"
    print(f"\nGET {url}")
    data = fetch_json(url)
    departures = data.get("departures", [])
    show_departures(departures, station_name)
    return departures


def main():
    if len(sys.argv) >= 3:
        lat, lon = float(sys.argv[1]), float(sys.argv[2])
    else:
        lat, lon = DEFAULT_LAT, DEFAULT_LON
        print(f"Usage: {sys.argv[0]} <lat> <lon>")
        print(f"Using default: EPFL Valais/Sion (Alpole) @ {lat}, {lon}")

    all_stations = find_stations(lat, lon)

    if not all_stations:
        print("No stations found!")
        sys.exit(1)

    # Show embedded departures from each mode's closest station
    for mode, stations in all_stations.items():
        closest = stations[0]
        embedded = closest.get("departures")
        if embedded:
            print(f"\n=== Embedded departures ({mode}) ===")
            show_departures(embedded, closest.get("name", "?"))

    # Find the overall closest station across all modes and poll its departures
    overall_closest = None
    for stations in all_stations.values():
        for s in stations:
            if overall_closest is None or s.get("dist", float("inf")) < overall_closest.get("dist", float("inf")):
                overall_closest = s

    if overall_closest:
        print(f"\n=== Polling closest station: {overall_closest.get('name', '?')} ({overall_closest.get('dist', '?')}m) ===")
        get_departures(overall_closest["id"], overall_closest.get("name", "?"))


if __name__ == "__main__":
    main()
