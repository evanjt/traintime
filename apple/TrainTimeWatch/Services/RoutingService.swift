import Foundation
import MapKit
import CoreLocation

class RoutingService {
    static let shared = RoutingService()

    private struct CachedRoute {
        let walkingDistance: Double   // meters
        let walkingTime: Double      // seconds
        let haversineAtFetch: Double // haversine when route was fetched
        let fetchTime: Date
    }

    private var cache: [String: CachedRoute] = [:]
    private var lastFetchCoordinate: [String: CLLocationCoordinate2D] = [:]
    private var lastFetchTime: [String: Date] = [:]
    private var inFlightRequests: Set<String> = []

    private let cacheMaxAge: TimeInterval = 300    // 5 minutes
    private let movementThreshold: Double = 100    // meters
    private let fetchCooldown: TimeInterval = 30   // seconds

    private init() {}

    /// Check if we should refetch route for a station
    func shouldRefetch(stationId: String, currentCoord: CLLocationCoordinate2D, currentHaversine: Double) -> Bool {
        guard !inFlightRequests.contains(stationId) else { return false }

        // Cooldown check
        if let lastTime = lastFetchTime[stationId],
           Date().timeIntervalSince(lastTime) < fetchCooldown {
            return false
        }

        // No cache → should fetch
        guard let cached = cache[stationId] else { return true }

        // Cache expired
        if Date().timeIntervalSince(cached.fetchTime) > cacheMaxAge {
            return true
        }

        // User moved >100m from last fetch position
        if let lastCoord = lastFetchCoordinate[stationId] {
            let moved = GeoUtils.haversineDistance(from: currentCoord, to: lastCoord)
            if moved > movementThreshold {
                return true
            }
        }

        return false
    }

    /// Interpolate cached route data using current haversine ratio
    func interpolate(stationId: String, currentHaversine: Double) -> (distance: Double, time: Double)? {
        guard let cached = cache[stationId],
              cached.haversineAtFetch > 0 else { return nil }

        let ratio = currentHaversine / cached.haversineAtFetch
        return (
            distance: cached.walkingDistance * ratio,
            time: cached.walkingTime * ratio
        )
    }

    /// Fetch walking route via MKDirections
    func fetchRoute(
        from source: CLLocationCoordinate2D,
        to destination: CLLocationCoordinate2D,
        stationId: String,
        currentHaversine: Double
    ) async {
        guard !inFlightRequests.contains(stationId) else { return }
        inFlightRequests.insert(stationId)
        defer { inFlightRequests.remove(stationId) }

        let request = MKDirections.Request()
        request.source = MKMapItem(placemark: MKPlacemark(coordinate: source))
        request.destination = MKMapItem(placemark: MKPlacemark(coordinate: destination))
        request.transportType = .walking

        do {
            let directions = MKDirections(request: request)
            let response = try await directions.calculate()

            if let route = response.routes.first {
                let cached = CachedRoute(
                    walkingDistance: route.distance,
                    walkingTime: route.expectedTravelTime,
                    haversineAtFetch: currentHaversine,
                    fetchTime: Date()
                )
                cache[stationId] = cached
                lastFetchCoordinate[stationId] = source
                lastFetchTime[stationId] = Date()
            }
        } catch {
            // Silently fail — caller falls back to haversine
            lastFetchTime[stationId] = Date()
        }
    }

    /// Clear all cached routes
    func clearCache() {
        cache.removeAll()
        lastFetchCoordinate.removeAll()
        lastFetchTime.removeAll()
        inFlightRequests.removeAll()
    }
}
