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
    static let refreshInterval: TimeInterval = 10
}
