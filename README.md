<p align="center">
  <img src="docs/favicon.png" width="120" alt="TrainTime" />
</p>

<h1 align="center">TrainTime</h1>

<p align="center">
  Swiss public transport departures on your wrist.<br />
  Walk times, delays, platforms - glance and go.
</p>

<p align="center">
  <a href="https://apps.apple.com/ch/app/traintime/id6760388620"><img src="docs/app-store-badge.svg" alt="Download on the App Store" height="44" /></a>&nbsp;
  <a href="https://apps.garmin.com/apps/c70bbfae-846a-4d00-9e96-d485217035fb"><img src="docs/connect-iq-badge.svg" alt="Available on Connect IQ" height="44" /></a>
</p>

<p align="center">
  <a href="https://traintime.ch/privacy">Privacy</a>&nbsp;&nbsp;·&nbsp;&nbsp;<a href="https://traintime.ch">Website</a>
</p>

---

<p align="center">
  <img src="docs/screenshots/apple/01-station-view.png" width="180" alt="Watch station departures" />&nbsp;&nbsp;
  <img src="docs/screenshots/apple/02-focused-tracking.png" width="180" alt="Watch focused tracking" />&nbsp;&nbsp;
  <img src="docs/screenshots/apple/03-station-picker.png" width="180" alt="Watch station picker" />
</p>

<p align="center">
  <img src="docs/screenshots/garmin/01-station-view-framed.png" width="160" alt="Garmin station departures" />&nbsp;&nbsp;
  <img src="docs/screenshots/garmin/03-focused-tracking-framed.png" width="160" alt="Garmin focused tracking" />&nbsp;&nbsp;
  <img src="docs/screenshots/garmin/04-station-picker-framed.png" width="160" alt="Garmin station picker" />
</p>

<p align="center">
  <img src="docs/screenshots/iphone/01-station-view.png" width="140" alt="iPhone departure list" />&nbsp;&nbsp;
  <img src="docs/screenshots/iphone/02-focused-tracking.png" width="140" alt="iPhone focused tracking" />&nbsp;&nbsp;
  <img src="docs/screenshots/iphone/03-station-picker.png" width="140" alt="iPhone station picker" />
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
| [Apple Watch & iPhone](https://apps.apple.com/ch/app/traintime/id6760388620) | Available |
| [Garmin](https://apps.garmin.com/apps/c70bbfae-846a-4d00-9e96-d485217035fb) | Available |

## Build

### Apple Watch

Open `apple/TrainTimeWatch.xcodeproj` in Xcode.

### Garmin

```bash
cd garmin
./setup.sh           # Install Connect IQ SDK
./build.sh           # Build for fenix6pro (default)
./build.sh release   # Build .iq package for all devices
```

## API

Uses a self-hosted worker API backed by [Open Transport Data Switzerland](https://opentransportdata.swiss). Source: [traintime-api](https://github.com/evanjt/traintime-api). Copy `Secrets.swift.example` / `Secrets.mc.example` to `Secrets.swift` / `Secrets.mc` and fill in your API key.

## License

&copy; 2026 Evan Thomas
