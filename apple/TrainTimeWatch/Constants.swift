import SwiftUI

enum AppColors {
    static let stationName = Color.white
    static let walkInfo = Color(red: 0xAA/255, green: 0xAA/255, blue: 0xAA/255)
    static let separator = Color(red: 0x44/255, green: 0x44/255, blue: 0x44/255)
    static let minutesGone = Color(red: 0x66/255, green: 0x66/255, blue: 0x66/255)
    static let minutesNow = Color(red: 1.0, green: 1.0, blue: 0.0)
    static let minutesSoon = Color(red: 0.0, green: 1.0, blue: 0.0)
    static let delay = Color(red: 1.0, green: 0x55/255, blue: 0.0)
    static let platform = Color(red: 0x55/255, green: 0xAA/255, blue: 1.0)
    static let platformChanged = Color.red
    static let platformChangedText = Color.white
    static let bodyStatus = Color(red: 0xAA/255, green: 0xAA/255, blue: 0xAA/255)
    static let background = Color.black

    // Selection highlight (State 1)
    static let selectionHighlight = Color(red: 0x00/255, green: 0x44/255, blue: 0x88/255)
    static let selectionAccent = Color(red: 0x55/255, green: 0xAA/255, blue: 0xFF/255)

    // Platform changed in tracking mode
    static let platformChangedOrange = Color(red: 0xFF/255, green: 0x44/255, blue: 0x00/255)

    // Favourite highlight
    static let favouriteBackground = Color(red: 0x33/255, green: 0x28/255, blue: 0x00/255)
    static let favouriteSeparator = Color(red: 0x99/255, green: 0x88/255, blue: 0x00/255)

    // Tracking bar colors
    static let darkGreen = Color(red: 0.0, green: 1.0, blue: 0.0)
    static let lightGreen = Color(red: 0x55/255, green: 0xFF/255, blue: 0x55/255)
    static let darkRed = Color(red: 1.0, green: 0.0, blue: 0.0)
    static let amber = Color(red: 1.0, green: 0xAA/255, blue: 0.0)
    static let barGray = Color(red: 0x44/255, green: 0x44/255, blue: 0x44/255)

    // Status colors
    static let ahead = Color.green
    static let onTime = Color.yellow
    static let behind = Color.red
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
