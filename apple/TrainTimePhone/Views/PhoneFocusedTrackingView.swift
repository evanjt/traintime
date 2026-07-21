import SwiftUI
import MapKit
import UIKit

struct PhoneFocusedTrackingView: View {
    @ObservedObject var viewModel: PhoneViewModel
    @State private var showMap = false

    var body: some View {
        let focused = viewModel.focusedTrain

        ZStack(alignment: .topLeading) {
            ScrollView {
                VStack(spacing: 16) {
                    // Station name
                    Text(viewModel.stationName)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .padding(.top, 8)

                    // Destination + star
                    let platChanged = focused?.platformChanged == true
                    HStack(spacing: 6) {
                        if let f = focused, !f.lineNumber.isEmpty {
                            Text(f.lineNumber)
                                .font(.headline.weight(.bold))
                                .foregroundStyle(.white)
                                .padding(.horizontal, 8)
                                .padding(.vertical, 3)
                                .background(
                                    RoundedRectangle(cornerRadius: 7)
                                        .fill(AppColors.linePill(f.lineNumber, mode: viewModel.currentMode))
                                )
                        }
                        Text(focused?.destination ?? "?")
                            .font(.title2.weight(.bold))
                            .foregroundStyle(platChanged ? AppColors.platformChangedOrange : .primary)
                            .lineLimit(1)
                            .minimumScaleFactor(0.6)
                        Button {
                            viewModel.toggleFavourite()
                        } label: {
                            Image(systemName: viewModel.isFocusedTrainFavourite ? "star.fill" : "star")
                                .font(.system(size: 20))
                                .foregroundStyle(viewModel.isFocusedTrainFavourite ? AppColors.favouriteStar : Color.secondary)
                        }
                        .buttonStyle(.plain)
                    }

                    // On a saved route the header keeps the train's own terminus;
                    // this line carries where the journey actually ends.
                    if let routeDest = focused?.routeDestination, routeDest != focused?.destination {
                        Text("Tracking route to \(routeDest)")
                            .font(.system(size: 13))
                            .foregroundStyle(.secondary)
                    }

                    // Platform + departure time
                    HStack(spacing: 6) {
                        if let plat = focused?.platform, !plat.isEmpty {
                            Text("Platform \(plat)")
                                .font(.system(.caption, weight: .medium))
                                .foregroundStyle(platChanged ? AppColors.platformChangedOrange : .secondary)
                        }
                        if let f = focused {
                            Text("·")
                                .foregroundStyle(.quaternary)
                            Text(Self.formatDepartureTime(f.departureTimestamp))
                                .font(.system(size: 12, weight: .medium, design: .rounded))
                                .monospacedDigit()
                                .foregroundStyle(.tertiary)
                        }
                    }

                    // Countdown + delay
                    HStack(spacing: 8) {
                        Text(focused?.countdownText ?? "–")
                            .font(.system(size: 56, weight: .bold, design: .rounded))
                            .monospacedDigit()
                            .foregroundStyle(countdownColor)

                        if let delay = focused?.delay, delay > 0,
                           let f = focused, f.minutesUntil >= -0.5 {
                            Text("+\(delay)")
                                .font(.system(.subheadline, weight: .medium))
                                .foregroundStyle(.white)
                                .padding(.horizontal, 10)
                                .padding(.vertical, 4)
                                .background(Capsule().fill(AppColors.delay))
                        }
                    }
                    .padding(.vertical, 4)

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

                        Image(systemName: viewModel.useRoutedDistance ? "point.bottomleft.forward.to.point.topright.scurvepath" : "line.diagonal")
                            .font(.system(size: 14))
                            .foregroundStyle(.tertiary)
                    }
                    .onTapGesture {
                        viewModel.toggleRoutedDistance()
                    }

                    // Onward connection (shared multi-leg route): where you change
                    // and the next train. Tap to jump onto it early.
                    if let onward = viewModel.onwardConnection {
                        OnwardConnectionCard(onward: onward, mode: viewModel.currentMode) {
                            viewModel.trackLeg(onward.legIndex)
                        }
                        .padding(.top, 8)
                    }

                    // Formation diagram
                    if let formation = viewModel.formation {
                        FormationDiagramView(formation: formation)
                            .padding(.top, 8)
                    }

                    // Map button
                    Button {
                        showMap = true
                    } label: {
                        Label("Show on Map", systemImage: "map")
                            .font(.subheadline)
                            .frame(maxWidth: 200)
                    }
                    .buttonStyle(.bordered)
                    .padding(.top, 4)

                    // Save this as a route and keep it going with the app closed
                    // via the distance-aware reminder. Requests Always location
                    // (the system prompt) the first time it's used.
                    Button {
                        viewModel.requestTrackInBackground()
                    } label: {
                        Label("Track in the background", systemImage: "bell")
                            .font(.subheadline)
                            .frame(maxWidth: 200)
                    }
                    .buttonStyle(.bordered)
                    .padding(.top, 4)

                    // Watch button: a live primary watch takes an explicit send of this
                    // train, a closed one the launch/re-sync path. Long-press (or tap
                    // with several watches) opens a per-watch send menu. Colour tracks
                    // liveness; a spinner shows during a Garmin open.
                    if viewModel.primaryWatchLiveness != .hidden {
                        Divider()
                            .padding(.vertical, 4)

                        Menu {
                            ForEach(viewModel.connectedWatches) { watch in
                                Button("Send to \(watch.name)") {
                                    viewModel.sendToWatch(watch)
                                }
                            }
                        } label: {
                            HStack(spacing: 6) {
                                WatchLivenessIndicator(
                                    liveness: viewModel.primaryWatchLiveness,
                                    isChecking: viewModel.watchChecking,
                                    isAppleWatch: viewModel.resolvedPrimaryWatch == .appleWatch,
                                    size: 16
                                )
                                Text(viewModel.watchTrackingFocused ? "Tracking on watch" : "Track on watch")
                                    .font(.subheadline)
                            }
                            .frame(maxWidth: 200)
                        } primaryAction: {
                            // The watch already tracks this departure; a re-send
                            // would only make it re-enter and buzz again.
                            if !viewModel.watchTrackingFocused {
                                viewModel.sendToPrimaryOrOpen()
                            }
                        }
                        .buttonStyle(.bordered)
                        .onAppear { viewModel.refreshConnectedWatches() }

                        if let status = viewModel.watchSendStatus {
                            Text(status)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 24)
                .frame(maxWidth: .infinity)
            }

            // Back button overlay
            Button {
                viewModel.exitToStationView()
            } label: {
                HStack(spacing: 4) {
                    Image(systemName: "chevron.left")
                        .font(.system(size: 16, weight: .medium))
                    Text("Back")
                        .font(.body)
                }
                .foregroundStyle(.blue)
                .padding(.horizontal, 16)
                .padding(.vertical, 12)
            }
            .buttonStyle(.plain)
        }
        .onAppear { viewModel.refreshConnectedWatches() }
        .sheet(isPresented: $showMap) {
            PhoneMapView(viewModel: viewModel)
        }
        // Prominent disclosure before the system Always-location prompt.
        .alert("Track in the background?", isPresented: $viewModel.showBackgroundDisclosure) {
            Button("Continue") { viewModel.confirmTrackInBackground() }
            Button("Not now", role: .cancel) {}
        } message: {
            Text("TrainTime collects your location to time your route reminder, even when the app is closed or not in use. You can decline, and we'll use your last known location instead.")
        }
        // Declined "Always": reassure it still works, offer a one-tap retry.
        .alert("Using your last location", isPresented: $viewModel.showBackgroundDenied) {
            Button("Open Settings") {
                if let url = URL(string: UIApplication.openSettingsURLString) {
                    UIApplication.shared.open(url)
                }
            }
            Button("Keep as is", role: .cancel) {}
        } message: {
            Text("That's fine. Your reminder still works, using your last known location instead of live updates. Allow all-time access any time to make it live.")
        }
    }

    private static func formatDepartureTime(_ timestamp: Int) -> String {
        let date = Date(timeIntervalSince1970: TimeInterval(timestamp))
        let f = DateFormatter()
        f.dateFormat = "HH:mm"
        return f.string(from: date)
    }

    private var countdownColor: Color {
        guard let focused = viewModel.focusedTrain else { return .primary }
        let minutesUntil = focused.minutesUntil
        if minutesUntil < -0.5 { return .secondary }
        if minutesUntil < 2.0 { return AppColors.minutesNow }
        return AppColors.minutesSoon
    }
}

// The next ride leg while tracking a shared route: change station, onward line
// pill + destination, and the connection buffer. Tap to jump onto it early.
struct OnwardConnectionCard: View {
    let onward: OnwardConnection
    let mode: TransportMode
    let onTap: () -> Void

    private static let timeFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm"
        formatter.timeZone = TimeZone(identifier: "Europe/Zurich")
        return formatter
    }()

    var body: some View {
        let leg = onward.leg
        let line = "\(leg.category ?? "")\(leg.lineNumber ?? "")"
        Button(action: onTap) {
            VStack(alignment: .leading, spacing: 4) {
                Text("Change at \(onward.changeStation)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                HStack(spacing: 8) {
                    if !line.isEmpty {
                        Text(line)
                            .font(.system(size: 14, weight: .bold))
                            .foregroundStyle(.white)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 2)
                            .background(RoundedRectangle(cornerRadius: 7).fill(AppColors.linePill(line, mode: mode)))
                    }
                    Text(leg.destName)
                        .fontWeight(.medium)
                        .lineLimit(1)
                }
                Text("\(Self.timeFormatter.string(from: Date(timeIntervalSince1970: TimeInterval(leg.depTs)))) · \(onward.changeMinutes) min to change")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(12)
            .background(RoundedRectangle(cornerRadius: 12).fill(Color(uiColor: .secondarySystemBackground)))
        }
        .buttonStyle(.plain)
        .frame(maxWidth: 320)
    }
}

struct PhoneMapView: View {
    @ObservedObject var viewModel: PhoneViewModel
    @Environment(\.dismiss) var dismiss

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
                    ToolbarItem(placement: .cancellationAction) {
                        Button {
                            dismiss()
                        } label: {
                            Image(systemName: "xmark")
                                .fontWeight(.bold)
                        }
                    }
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
