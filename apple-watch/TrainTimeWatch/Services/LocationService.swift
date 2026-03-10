import CoreLocation
import Combine

class LocationService: NSObject, ObservableObject, CLLocationManagerDelegate {
    private let manager = CLLocationManager()

    @Published var coordinate: CLLocationCoordinate2D?
    @Published var heading: Double? // radians, only when moving
    @Published var speed: Double?
    @Published var horizontalAccuracy: Double?
    @Published var authorizationDenied = false

    var gpsQuality: GPSQuality {
        GPSQuality.from(accuracy: horizontalAccuracy)
    }

    var isInSwitzerland: Bool {
        guard let coord = coordinate else { return false }
        return SwissBounds.contains(lat: coord.latitude, lon: coord.longitude)
    }

    override init() {
        super.init()
        manager.delegate = self
        manager.desiredAccuracy = kCLLocationAccuracyBest
        manager.allowsBackgroundLocationUpdates = false
        loadLastKnownCoordinate()
    }

    func start() {
        manager.requestWhenInUseAuthorization()
        manager.startUpdatingLocation()
    }

    func stop() {
        manager.stopUpdatingLocation()
    }

    /// Check if user has moved significantly from a reference point
    /// Uses degree-based thresholds matching Garmin: dLat > 0.0045 || dLon > 0.006
    func hasMovedSignificantly(from coord: CLLocationCoordinate2D) -> Bool {
        guard let current = coordinate else { return false }
        let dLat = abs(current.latitude - coord.latitude)
        let dLon = abs(current.longitude - coord.longitude)
        return dLat > 0.0045 || dLon > 0.006
    }

    /// Save current coordinate to UserDefaults for next launch
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
            horizontalAccuracy = -1 // mark as cached, not live
        }
    }

    // MARK: - CLLocationManagerDelegate

    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard let location = locations.last else { return }
        let coord = location.coordinate

        // Validate coordinates
        guard abs(coord.latitude) <= 90, abs(coord.longitude) <= 180 else { return }

        coordinate = coord
        horizontalAccuracy = location.horizontalAccuracy
        speed = location.speed

        // Only update heading when moving (>0.5 m/s) to avoid jitter
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
