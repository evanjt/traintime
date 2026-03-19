import SwiftUI
import MapKit

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

                    // Destination
                    let platChanged = focused?.platformChanged == true
                    HStack(spacing: 6) {
                        if let f = focused, !f.lineNumber.isEmpty {
                            Text(f.lineNumber)
                                .font(.title2.weight(.bold))
                                .foregroundStyle(AppColors.platform)
                        }
                        Text(focused?.destination ?? "?")
                            .font(.title2.weight(.bold))
                            .foregroundStyle(platChanged ? AppColors.platformChangedOrange : .primary)
                            .lineLimit(1)
                            .minimumScaleFactor(0.6)
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
                        Text(focused?.countdownText ?? "—")
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

                    // Send to Watch (only when watches are connected)
                    let watches = viewModel.connectedWatches
                    if !watches.isEmpty {
                        Divider()
                            .overlay(Color.gray.opacity(0.3))
                            .padding(.vertical, 4)

                        if watches.count == 1 {
                            Button {
                                viewModel.sendToWatch()
                            } label: {
                                Label("Send to Watch", systemImage: "applewatch")
                                    .font(.subheadline)
                                    .frame(maxWidth: 200)
                            }
                            .buttonStyle(.bordered)
                        } else {
                            ForEach(watches) { watch in
                                Button {
                                    viewModel.sendToWatch(watch)
                                } label: {
                                    Label(watch.name, systemImage: watch.type == .appleWatch ? "applewatch" : "watch.analog")
                                        .font(.subheadline)
                                        .frame(maxWidth: 200)
                                }
                                .buttonStyle(.bordered)
                            }
                        }

                        if let status = viewModel.watchSendStatus {
                            Text(status)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }

                        Text("Watch app must be open")
                            .font(.caption2)
                            .foregroundStyle(.tertiary)
                    }
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 24)
                .frame(maxWidth: .infinity)
            }
            .background(Color.black)

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
