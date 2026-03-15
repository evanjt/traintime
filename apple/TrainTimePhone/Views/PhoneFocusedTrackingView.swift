import SwiftUI
import MapKit

struct PhoneFocusedTrackingView: View {
    @ObservedObject var viewModel: PhoneViewModel
    @State private var showMap = false

    var body: some View {
        let focused = viewModel.focusedTrain

        ScrollView {
            VStack(spacing: 12) {
                // Station name
                Text(viewModel.stationName)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)

                // Destination + platform
                let platChanged = focused?.platformChanged == true
                HStack(spacing: 6) {
                    Text(focused?.destination ?? "?")
                        .font(.title2.weight(.bold))
                        .foregroundStyle(platChanged ? AppColors.platformChangedOrange : .primary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.6)

                    if let plat = focused?.platform, !plat.isEmpty {
                        Text("P\(plat)")
                            .font(.system(.caption, weight: .medium))
                            .foregroundStyle(platChanged ? .white : AppColors.platform)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 3)
                            .background(
                                platChanged
                                    ? Capsule().fill(AppColors.platformChangedOrange)
                                    : Capsule().fill(.clear)
                            )
                    }
                }

                // Countdown
                Text(focused?.countdownText ?? "—")
                    .font(.system(size: 48, weight: .bold, design: .rounded))
                    .monospacedDigit()
                    .foregroundStyle(countdownColor)

                // Delay badge
                if let delay = focused?.delay, delay > 0,
                   let f = focused, f.minutesUntil >= -0.5 {
                    Text("+\(delay)")
                        .font(.system(.subheadline, weight: .medium))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 4)
                        .background(Capsule().fill(AppColors.delay))
                }

                // Tracking bar
                TrackingBarView(
                    schedBuf: viewModel.trackingScheduledBuffer,
                    effectBuf: viewModel.trackingEffectiveBuffer,
                    hasGPS: viewModel.gpsQuality != .unavailable
                )
                .frame(height: 16)
                .padding(.horizontal, 24)

                // Status
                Text(viewModel.trackingStatusText)
                    .font(.headline)
                    .foregroundStyle(viewModel.trackingStatusColor)

                // Walk info + direction
                HStack(spacing: 8) {
                    DirectionArrowView(degrees: viewModel.directionToStation)

                    Text(GeoUtils.formatWalkInfo(distanceMeters: viewModel.lastWalkDist, walkTimeSeconds: viewModel.lastWalkTime))
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                .padding(.top, 4)

                // Map button
                Button {
                    showMap = true
                } label: {
                    Label("Show on Map", systemImage: "map")
                        .font(.subheadline)
                }
                .buttonStyle(.bordered)
                .padding(.top, 8)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 24)
        }
        .sheet(isPresented: $showMap) {
            PhoneMapView(viewModel: viewModel)
        }
    }

    private var countdownColor: Color {
        guard let focused = viewModel.focusedTrain else { return .primary }
        let minutesUntil = focused.minutesUntil
        if minutesUntil < -0.5 { return .secondary }
        if minutesUntil < 2.0 { return AppColors.minutesNow }
        return AppColors.minutesSoon
    }
}

struct PhoneMapView: View {
    @ObservedObject var viewModel: PhoneViewModel

    var body: some View {
        NavigationStack {
            if let station = viewModel.currentStation,
               let stationCoord = station.coordinate {
                Map {
                    Marker(station.name ?? "Station", coordinate: stationCoord)
                        .tint(.red)
                    UserAnnotation()
                }
                .mapStyle(.standard)
                .mapControls {
                    MapUserLocationButton()
                    MapCompass()
                    MapScaleView()
                }
                .toolbar {
                    ToolbarItem(placement: .bottomBar) {
                        Button {
                            let destination = MKMapItem(placemark: MKPlacemark(coordinate: stationCoord))
                            destination.name = station.name ?? "Station"
                            destination.openInMaps(launchOptions: [
                                MKLaunchOptionsDirectionsModeKey: MKLaunchOptionsDirectionsModeWalking
                            ])
                        } label: {
                            Label("Navigate", systemImage: "figure.walk")
                        }
                    }
                }
                .navigationTitle(station.name ?? "Station")
                .navigationBarTitleDisplayMode(.inline)
            } else {
                Text("No station selected")
                    .foregroundStyle(.secondary)
            }
        }
    }
}
