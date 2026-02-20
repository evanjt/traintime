import SwiftUI
import Combine

struct ContentView: View {
    @StateObject private var location = LocationService()

    @State private var stations: [Station] = []
    @State private var stationIndex = 0
    @State private var departures: [Departure]?
    @State private var status = "GPS: Searching..."
    @State private var requestInFlight = false

    @State private var crownAccumulator = 0.0
    @State private var timer: Publishers.Autoconnect<Timer.TimerPublisher>?
    @State private var timerCancellable: AnyCancellable?

    var body: some View {
        Group {
            if let station = currentStation {
                StationView(
                    stationName: station.label ?? "Station",
                    walkInfo: station.walkInfoWithCounter(index: stationIndex, total: stations.count),
                    departures: departures,
                    isLoading: requestInFlight
                )
            } else {
                StatusView(status: status, coordinate: location.coordinate)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(AppColors.background)
        .focusable()
        .digitalCrownRotation(
            $crownAccumulator,
            from: -100, through: 100,
            sensitivity: .low,
            isContinuous: true,
            isHapticFeedbackEnabled: true
        )
        .onChange(of: crownAccumulator) { _, newValue in
            handleCrownRotation(newValue)
        }
        .gesture(
            DragGesture(minimumDistance: 20)
                .onEnded { value in
                    if value.translation.width < -20 {
                        nextStation()
                    } else if value.translation.width > 20 {
                        previousStation()
                    }
                }
        )
        .onAppear {
            location.start()
            startTimer()
        }
        .onDisappear {
            location.stop()
            stopTimer()
        }
        .onChange(of: location.coordinate) { _, coord in
            onLocationUpdate(coord)
        }
    }

    private var currentStation: Station? {
        guard !stations.isEmpty, stationIndex < stations.count else { return nil }
        return stations[stationIndex]
    }

    // MARK: - Timer

    private func startTimer() {
        timerCancellable = Timer.publish(every: Timing.refreshInterval, on: .main, in: .common)
            .autoconnect()
            .sink { _ in onTimerTick() }
    }

    private func stopTimer() {
        timerCancellable?.cancel()
        timerCancellable = nil
    }

    // MARK: - Location

    private func onLocationUpdate(_ coord: CLLocationCoordinate2D?) {
        guard let coord = coord else {
            status = "GPS: Searching..."
            return
        }

        guard SwissBounds.contains(lat: coord.latitude, lon: coord.longitude) else {
            stations = []
            stationIndex = 0
            departures = nil
            status = "Not in Switzerland"
            return
        }

        if stations.isEmpty && !requestInFlight {
            status = "Finding stations..."
            fetchStations(lat: coord.latitude, lon: coord.longitude)
        }
    }

    // MARK: - Timer Tick

    private func onTimerTick() {
        // Check Switzerland bounds on every tick
        if let coord = location.coordinate {
            guard SwissBounds.contains(lat: coord.latitude, lon: coord.longitude) else {
                stations = []
                stationIndex = 0
                departures = nil
                status = "Not in Switzerland"
                return
            }
        }

        guard !requestInFlight else { return }

        if let station = currentStation, let id = station.id {
            fetchDepartures(stationId: id)
        } else if let coord = location.coordinate {
            fetchStations(lat: coord.latitude, lon: coord.longitude)
        }
    }

    // MARK: - API Calls

    private func fetchStations(lat: Double, lon: Double) {
        requestInFlight = true
        Task {
            do {
                let result = try await TrainAPIService.fetchNearbyStations(lat: lat, lon: lon)
                await MainActor.run {
                    requestInFlight = false
                    if result.isEmpty {
                        status = "No stations nearby"
                        departures = nil
                    } else {
                        stations = result
                        stationIndex = 0
                        selectStation(0)
                    }
                }
            } catch let error as TrainAPIError {
                await MainActor.run {
                    requestInFlight = false
                    handleAPIError(error, prefix: "Station error")
                }
            } catch {
                await MainActor.run {
                    requestInFlight = false
                    status = "Station error"
                    departures = nil
                }
            }
        }
    }

    private func fetchDepartures(stationId: String) {
        requestInFlight = true
        Task {
            do {
                let result = try await TrainAPIService.fetchDepartures(stationId: stationId)
                await MainActor.run {
                    requestInFlight = false
                    departures = result
                }
            } catch let error as TrainAPIError {
                await MainActor.run {
                    requestInFlight = false
                    handleAPIError(error, prefix: "Error")
                }
            } catch {
                await MainActor.run {
                    requestInFlight = false
                    status = "Error"
                    departures = nil
                }
            }
        }
    }

    private func handleAPIError(_ error: TrainAPIError, prefix: String) {
        switch error {
        case .rateLimited:
            status = "Rate limited"
        case .httpError(let code):
            status = "\(prefix): \(code)"
        case .noData:
            status = "\(prefix)"
        }
        departures = nil
    }

    // MARK: - Station Cycling

    private func nextStation() {
        guard stations.count > 1 else { return }
        stationIndex = (stationIndex + 1) % stations.count
        selectStation(stationIndex)
    }

    private func previousStation() {
        guard stations.count > 1 else { return }
        stationIndex = stationIndex - 1
        if stationIndex < 0 { stationIndex = stations.count - 1 }
        selectStation(stationIndex)
    }

    private func selectStation(_ index: Int) {
        departures = nil
        if let id = stations[index].id {
            fetchDepartures(stationId: id)
        }
    }

    // MARK: - Digital Crown

    private func handleCrownRotation(_ value: Double) {
        if value > 1.5 {
            crownAccumulator = 0
            nextStation()
        } else if value < -1.5 {
            crownAccumulator = 0
            previousStation()
        }
    }
}
