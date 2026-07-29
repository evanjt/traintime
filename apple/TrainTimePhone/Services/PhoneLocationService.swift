import CoreLocation
import Combine

class PhoneLocationService: NSObject, ObservableObject, CLLocationManagerDelegate {
    private let manager = CLLocationManager()

    @Published var coordinate: CLLocationCoordinate2D?
    @Published var heading: Double? // radians, only when moving
    @Published var speed: Double?
    @Published var horizontalAccuracy: Double?
    @Published var authorizationDenied = false

    /// Seeds older than this are marked cached rather than live.
    private static let seedMaxAge: TimeInterval = 120

    /// The held coordinate is a cached one (persisted, or an old OS fix), not a live fix.
    var loadedFromCache: Bool {
        coordinate != nil && horizontalAccuracy == -1
    }

    var gpsQuality: GPSQuality {
        loadedFromCache ? .lastKnown : GPSQuality.from(accuracy: horizontalAccuracy)
    }

    var isInSwitzerland: Bool {
        guard let coord = coordinate else { return false }
        return SwissBounds.contains(lat: coord.latitude, lon: coord.longitude)
    }

    override init() {
        super.init()
        manager.delegate = self
        // Coarse accuracy returns a fix for station discovery without waiting for
        // GPS convergence; raised to a finer fix while tracking (setTrackingAccuracy).
        manager.desiredAccuracy = kCLLocationAccuracyHundredMeters
        manager.allowsBackgroundLocationUpdates = false
        manager.pausesLocationUpdatesAutomatically = true
    }

    func start() {
        manager.requestWhenInUseAuthorization()
        // Seed from the OS last-known fix so stations can show immediately, before the
        // first live update arrives (analog of Garmin's Position.getInfo()). An old fix
        // keeps its original (often good) accuracy while being from wherever the phone
        // last resolved — possibly another city — so past the age gate it's marked
        // cached and nothing downstream treats it as proof of position.
        if coordinate == nil, let cached = manager.location {
            coordinate = cached.coordinate
            if Date().timeIntervalSince(cached.timestamp) <= Self.seedMaxAge {
                horizontalAccuracy = cached.horizontalAccuracy
                speed = cached.speed
            } else {
                horizontalAccuracy = -1
            }
        }
        manager.startUpdatingLocation()
    }

    func stop() {
        manager.stopUpdatingLocation()
    }

    /// True while a tracking session holds continuous background location. Gated
    /// on the Info.plist actually declaring the mode: setting
    /// `allowsBackgroundLocationUpdates` without it throws at runtime, and the
    /// gate keeps a build without the key (0.6.1) behaving exactly as before.
    private(set) var backgroundTrackingActive = false
    private static let hasLocationBackgroundMode: Bool =
        (Bundle.main.object(forInfoDictionaryKey: "UIBackgroundModes") as? [String])?.contains("location") ?? false

    /// Coarse accuracy while finding stations; finer accuracy while actively tracking
    /// a departure (more precise walk distance/direction). While tracking, also
    /// keep updates flowing in the background so the session (and its Live
    /// Activity) survives the app leaving the foreground — with the location
    /// indicator visible, and everything reverted on exit.
    func setTrackingAccuracy(_ tracking: Bool) {
        manager.desiredAccuracy = tracking ? kCLLocationAccuracyNearestTenMeters : kCLLocationAccuracyHundredMeters
        guard Self.hasLocationBackgroundMode else { return }
        backgroundTrackingActive = tracking
        manager.allowsBackgroundLocationUpdates = tracking
        manager.pausesLocationUpdatesAutomatically = !tracking
        manager.showsBackgroundLocationIndicator = tracking
    }

    func hasMovedSignificantly(from coord: CLLocationCoordinate2D) -> Bool {
        guard let current = coordinate else { return false }
        let dLat = abs(current.latitude - coord.latitude)
        let dLon = abs(current.longitude - coord.longitude)
        return dLat > 0.0045 || dLon > 0.006
    }

    func saveLastKnownCoordinate() {
        guard let coord = coordinate else { return }
        UserDefaults.standard.set(coord.latitude, forKey: "lastLat")
        UserDefaults.standard.set(coord.longitude, forKey: "lastLon")
    }

    private func loadLastKnownCoordinate() {
        let lat = UserDefaults.standard.double(forKey: "lastLat")
        let lon = UserDefaults.standard.double(forKey: "lastLon")
        if lat != 0 && lon != 0 {
            coordinate = CLLocationCoordinate2D(latitude: lat, longitude: lon)
            horizontalAccuracy = -1
        }
    }

    // MARK: - CLLocationManagerDelegate

    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard let location = locations.last else { return }
        let coord = location.coordinate
        guard abs(coord.latitude) <= 90, abs(coord.longitude) <= 180 else { return }

        coordinate = coord
        horizontalAccuracy = location.horizontalAccuracy
        speed = location.speed

        if location.speed > 0.5, location.course >= 0 {
            heading = location.course * .pi / 180.0
        }
    }

    func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        switch manager.authorizationStatus {
        case .authorizedWhenInUse, .authorizedAlways:
            manager.startUpdatingLocation()
            authorizationDenied = false
        case .denied, .restricted:
            authorizationDenied = true
        default:
            break
        }
    }

    func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        // Location errors are transient; keep trying
    }
}
