<p align="center">
  <img src="docs/favicon.png" width="120" alt="TrainTime" />
</p>

<h1 align="center">TrainTime</h1>

<p align="center">
  Swiss public transport departures on your wrist.<br />
  Walk times, delays, platforms — glance and go.
</p>

<p align="center">
  <a href="https://traintime.evanjt.com/privacy">Privacy</a>&nbsp;&nbsp;·&nbsp;&nbsp;<a href="https://traintime.evanjt.com">Website</a>
</p>

---

<p align="center">
  <img src="docs/screenshots/apple/01-station-view.png" width="180" alt="Station departures" />&nbsp;&nbsp;
  <img src="docs/screenshots/apple/02-focused-tracking.png" width="180" alt="Focused tracking" />&nbsp;&nbsp;
  <img src="docs/screenshots/apple/03-station-picker.png" width="180" alt="Station picker" />
</p>

---

## Features

- **Nearby stations** - GPS-based discovery with live walk time and distance
- **Live departures** - Platform numbers, destinations, real-time delays
- **Focused tracking** - Tap a departure to track it with a live countdown
- **Train, bus, tram & more** - Switch between transport modes including boats, funiculars, and cable cars

## Platforms

| Platform | Status |
|----------|--------|
| Apple Watch | Available |
| Garmin | Available |

## Build

### Apple Watch

Open `apple-watch/TrainTimeWatch.xcodeproj` in Xcode.

### Garmin

```bash
cd garmin
./setup.sh           # Install Connect IQ SDK
./build.sh           # Build for fenix6pro (default)
./build.sh release   # Build .iq package for all devices
```

## API

Uses a self-hosted worker API backed by [Open Transport Data Switzerland](https://opentransportdata.swiss). Source: [evanjt/traintime-api](https://github.com/evanjt/traintime-api). Copy `Secrets.swift.example` / `Secrets.mc.example` to `Secrets.swift` / `Secrets.mc` and fill in your API key.

## License

&copy; 2026 Evan Thomas
