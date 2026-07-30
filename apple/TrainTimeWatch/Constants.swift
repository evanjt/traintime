import SwiftUI
#if !os(watchOS)
import UIKit
#endif

enum AppColors {
    // On watchOS the dark value is used verbatim (no trait-based resolution), keeping
    // the watch look byte-identical. On iOS/widget the colour follows light/dark.
    #if os(watchOS)
    private static func adaptive(light: Color, dark: Color) -> Color { dark }
    #else
    private static func adaptive(light: Color, dark: Color) -> Color {
        Color(uiColor: UIColor { $0.userInterfaceStyle == .dark ? UIColor(dark) : UIColor(light) })
    }
    #endif

    static let stationName = Color.white
    static let walkInfo = Color(red: 0xAA/255, green: 0xAA/255, blue: 0xAA/255)
    static let separator = Color(red: 0x44/255, green: 0x44/255, blue: 0x44/255)
    static let minutesGone = Color(red: 0x66/255, green: 0x66/255, blue: 0x66/255)
    static let minutesNow = adaptive(
        light: Color(red: 0xB5/255, green: 0x89/255, blue: 0x00/255),
        dark: Color(red: 1.0, green: 1.0, blue: 0.0))
    static let minutesSoon = adaptive(
        light: Color(red: 0x1E/255, green: 0x7D/255, blue: 0x32/255),
        dark: Color(red: 0.0, green: 1.0, blue: 0.0))
    static let delay = adaptive(
        light: Color(red: 0xC7/255, green: 0x3E/255, blue: 0x00/255),
        dark: Color(red: 1.0, green: 0x55/255, blue: 0.0))
    static let platform = adaptive(
        light: Color(red: 0x00/255, green: 0x61/255, blue: 0xC2/255),
        dark: Color(red: 0x55/255, green: 0xAA/255, blue: 1.0))
    static let platformChanged = Color.red
    static let platformChangedText = Color.white
    static let bodyStatus = Color(red: 0xAA/255, green: 0xAA/255, blue: 0xAA/255)
    static let background = Color.black

    // Selection highlight (State 1)
    static let selectionHighlight = Color(red: 0x00/255, green: 0x44/255, blue: 0x88/255)
    static let selectionAccent = Color(red: 0x55/255, green: 0xAA/255, blue: 0xFF/255)

    // Platform changed in tracking mode
    static let platformChangedOrange = adaptive(
        light: Color(red: 0xC5/255, green: 0x30/255, blue: 0x00/255),
        dark: Color(red: 0xFF/255, green: 0x44/255, blue: 0x00/255))

    // Favourite highlight
    static let favouriteBackground = adaptive(
        light: Color(red: 0xF7/255, green: 0xEF/255, blue: 0xD2/255),
        dark: Color(red: 0x33/255, green: 0x28/255, blue: 0x00/255))
    static let favouriteSeparator = adaptive(
        light: Color(red: 0xB8/255, green: 0x9B/255, blue: 0x00/255),
        dark: Color(red: 0x99/255, green: 0x88/255, blue: 0x00/255))
    static let favouriteStar = adaptive(
        light: Color(red: 0xA0/255, green: 0x78/255, blue: 0x00/255),
        dark: Color(red: 1.0, green: 0xD7/255, blue: 0x00/255))

    // SBB-style line-pill fills (white text on top); colour = product category.
    // Deep enough for white text in both light and dark.
    static let lineLongDistance = adaptive(
        light: Color(red: 0xD5/255, green: 0x00/255, blue: 0x1C/255),
        dark: Color(red: 0xE6/255, green: 0x39/255, blue: 0x50/255))
    static let lineRegional = adaptive(
        light: Color(red: 0x00/255, green: 0x61/255, blue: 0xC2/255),
        dark: Color(red: 0x2E/255, green: 0x86/255, blue: 0xE0/255))
    static let lineBus = adaptive(
        light: Color(red: 0x4E/255, green: 0x62/255, blue: 0x73/255),
        dark: Color(red: 0x6E/255, green: 0x85/255, blue: 0x97/255))
    static let lineTram = adaptive(
        light: Color(red: 0x00/255, green: 0x7A/255, blue: 0x87/255),
        dark: Color(red: 0x1A/255, green: 0xA2/255, blue: 0xB0/255))

    private static let longDistancePrefixes: Set<String> =
        ["IC", "ICE", "EC", "ICN", "IR", "RJ", "RJX", "TGV", "EN", "NJ", "PE"]

    // Long-distance vs regional by line prefix; number-only lines (bus/tram) by mode.
    static func linePill(_ line: String, mode: TransportMode) -> Color {
        let prefix = line.prefix { $0.isLetter }.uppercased()
        if prefix.isEmpty {
            switch mode {
            case .bus: return lineBus
            case .tram: return lineTram
            default: return lineRegional
            }
        }
        return longDistancePrefixes.contains(prefix) ? lineLongDistance : lineRegional
    }

    // Tracking bar colors
    static let darkGreen = adaptive(
        light: Color(red: 0x1E/255, green: 0x8E/255, blue: 0x3E/255),
        dark: Color(red: 0.0, green: 1.0, blue: 0.0))
    static let lightGreen = adaptive(
        light: Color(red: 0x6F/255, green: 0xCF/255, blue: 0x82/255),
        dark: Color(red: 0x55/255, green: 0xFF/255, blue: 0x55/255))
    static let darkRed = adaptive(
        light: Color(red: 0xD3/255, green: 0x2F/255, blue: 0x2F/255),
        dark: Color(red: 1.0, green: 0.0, blue: 0.0))
    static let amber = adaptive(
        light: Color(red: 0xE0/255, green: 0x8A/255, blue: 0x00/255),
        dark: Color(red: 1.0, green: 0xAA/255, blue: 0.0))
    static let barGray = adaptive(
        light: Color(red: 0xC7/255, green: 0xC7/255, blue: 0xCC/255),
        dark: Color(red: 0x44/255, green: 0x44/255, blue: 0x44/255))
    static let trackingBarBackground = adaptive(
        light: Color(red: 0xE5/255, green: 0xE5/255, blue: 0xEA/255),
        dark: Color.black)

    // Status colors
    static let ahead = adaptive(light: Color(red: 0x1B/255, green: 0x7D/255, blue: 0x2C/255), dark: Color.green)
    static let onTime = adaptive(light: Color(red: 0xB5/255, green: 0x89/255, blue: 0x00/255), dark: Color.yellow)
    static let behind = adaptive(light: Color(red: 0xC6/255, green: 0x28/255, blue: 0x28/255), dark: Color.red)
}

enum SharedDefaults {
    static let appGroupId = "group.com.evanjt.traintime"

    // The widget process has its own standard defaults, so favourites and the widget
    // cache must live in the shared App Group container to cross the process boundary.
    // watchOS has no App Group with the phone (different device) and keeps standard defaults.
    static var store: UserDefaults {
        #if os(watchOS)
        return .standard
        #else
        if let suite = UserDefaults(suiteName: appGroupId) {
            return suite
        }
        print("[SharedDefaults] App Group \(appGroupId) unavailable, falling back to .standard")
        return .standard
        #endif
    }
}

enum SwissBounds {
    static let latMin = 45.8
    static let latMax = 47.8
    static let lonMin = 5.9
    static let lonMax = 10.5

    static func contains(lat: Double, lon: Double) -> Bool {
        lat >= latMin && lat <= latMax && lon >= lonMin && lon <= lonMax
    }
}

enum Timing {
    static let normalRefreshInterval: TimeInterval = 5.0
    static let trackingRefreshInterval: TimeInterval = 1.0
    static let fetchCooldownNormal: TimeInterval = 30.0
    static let fetchCooldownTracking: TimeInterval = 10.0
    static let requestTimeout: TimeInterval = 30.0
    static let inactivityTimeout: TimeInterval = 60.0
}

enum Thresholds {
    static let movementThreshold = 500.0 // meters
    static let walkSpeed = 83.0 // meters per minute
    static let barScale = 3.0 // minutes mapped to half bar width
    static let maxStationsPerMode = 5
    static let maxDepartures = 20
    static let fallbackSearchRadius = 5000.0 // meters
    static let consecutiveErrorLimit = 3
}

// How to run location for a proximity tier while tracking in the background.
enum LocationTier { case off, balanced, high }

// A polling tier chosen by how far the departure is. apiInterval == nil means
// paused: no fetch, coarsest location, the Live Activity lives on its own timer.
struct PollTier {
    let apiInterval: TimeInterval?
    let location: LocationTier
}

// Mirror of Android TrackingLogic.pollTier so both platforms scale identically:
// far out costs nothing, tightening to fast polls + precise GPS near departure.
enum TrackingTiers {
    static let pauseMin = 360.0 // > 6 h: paused
    static let farMin = 60.0 // 1–6 h
    static let midMin = 30.0 // 30–60 m
    static let nearMin = 10.0 // 10–30 m
    static let closeMin = 2.0 // 2–10 m

    static func pollTier(minutesUntil: Double) -> PollTier {
        switch minutesUntil {
        case let m where m > pauseMin: return PollTier(apiInterval: nil, location: .off)
        case let m where m > farMin: return PollTier(apiInterval: 900, location: .off)
        case let m where m > midMin: return PollTier(apiInterval: 450, location: .off)
        case let m where m > nearMin: return PollTier(apiInterval: 60, location: .balanced)
        case let m where m > closeMin: return PollTier(apiInterval: 30, location: .high)
        default: return PollTier(apiInterval: 15, location: .high)
        }
    }

}
