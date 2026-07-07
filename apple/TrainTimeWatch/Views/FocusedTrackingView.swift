import SwiftUI

struct FocusedTrackingView: View {
    @ObservedObject var viewModel: TrainTimeViewModel
    @State private var showMap = false

    var body: some View {
        let focused = viewModel.focusedTrain

        VStack(spacing: 2) {
            // Station name
            Text(viewModel.stationName)
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
                .lineLimit(1)

            // Destination + star
            let platChanged = focused?.platformChanged == true
            HStack(spacing: 4) {
                if let f = focused, !f.lineNumber.isEmpty {
                    Text(f.lineNumber)
                        .font(.system(.subheadline, weight: .bold))
                        .foregroundStyle(AppColors.platform)
                }
                Text(focused?.destination ?? "?")
                    .font(.system(.subheadline, weight: .bold))
                    .foregroundStyle(platChanged ? AppColors.platformChangedOrange : .primary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.5)
                Button {
                    viewModel.toggleFavourite()
                } label: {
                    Image(systemName: viewModel.isFocusedTrainFavourite ? "star.fill" : "star")
                        .font(.system(size: 12))
                        .foregroundStyle(viewModel.isFocusedTrainFavourite ? .yellow : .secondary)
                }
                .buttonStyle(.plain)
            }

            // Platform + departure time
            HStack(spacing: 3) {
                if let plat = focused?.platform, !plat.isEmpty {
                    Text("Pl. \(plat)")
                        .font(.system(size: 10, weight: .medium))
                        .foregroundStyle(platChanged ? AppColors.platformChangedOrange : .secondary)
                }
                if let f = focused {
                    Text("·")
                        .font(.system(size: 10))
                        .foregroundStyle(.quaternary)
                    Text(Self.formatDepartureTime(f.departureTimestamp))
                        .font(.system(size: 10, weight: .medium, design: .rounded))
                        .monospacedDigit()
                        .foregroundStyle(.tertiary)
                }
            }

            // Countdown + delay
            HStack(spacing: 4) {
                Text(focused?.countdownText ?? "–")
                    .font(.system(.title3, design: .rounded, weight: .bold))
                    .monospacedDigit()
                    .foregroundStyle(countdownColor)

                if let delay = focused?.delay, delay > 0,
                   let f = focused, f.minutesUntil >= -0.5 {
                    Text("+\(delay)")
                        .font(.system(.caption2, weight: .medium))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 5)
                        .padding(.vertical, 1)
                        .background(Capsule().fill(AppColors.delay))
                }
            }

            // Tracking bar
            TrackingBarView(
                schedBuf: viewModel.trackingScheduledBuffer,
                effectBuf: viewModel.trackingEffectiveBuffer,
                hasGPS: viewModel.gpsQuality != .unavailable
            )
            .padding(.horizontal, 4)

            // Status
            Text(viewModel.trackingStatusText)
                .font(.system(.caption, weight: .semibold))
                .foregroundStyle(viewModel.trackingStatusColor)

            // Walk info + direction
            HStack(spacing: 4) {
                DirectionArrowView(degrees: viewModel.directionToStation)

                Text(GeoUtils.formatWalkInfo(distanceMeters: viewModel.lastWalkDist, walkTimeSeconds: viewModel.lastWalkTime))
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)

                Image(systemName: viewModel.useRoutedDistance ? "point.bottomleft.forward.to.point.topright.scurvepath" : "line.diagonal")
                    .font(.system(size: 9))
                    .foregroundStyle(.tertiary)
            }
            .onTapGesture {
                viewModel.toggleRoutedDistance()
            }

            // Onward connection (shared multi-leg route): where you change and
            // the next train. Tap to jump onto it early.
            if let onward = viewModel.onwardConnection {
                WatchOnwardConnectionCard(onward: onward, mode: viewModel.currentMode) {
                    viewModel.trackLeg(onward.legIndex)
                }
                .padding(.top, 2)
            }

            // Formation strip
            if let formation = viewModel.formation {
                WatchFormationView(formation: formation)
                    .padding(.top, 1)
            }

            // Save this departure as a reminder on the phone.
            Button {
                viewModel.remindOnPhone()
            } label: {
                Label("Remind on phone", systemImage: "bell")
                    .font(.system(size: 11))
            }
            .buttonStyle(.plain)
            .foregroundStyle(AppColors.platform)
            .padding(.top, 3)

            if let status = viewModel.reminderStatus {
                Text(status)
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.horizontal, 2)
        .onTapGesture {
            showMap = true
        }
        .sheet(isPresented: $showMap) {
            MapView(viewModel: viewModel)
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

// The next ride leg while tracking a shared route on the watch: change station,
// onward line + destination, and the connection buffer. Tap to jump onto it.
struct WatchOnwardConnectionCard: View {
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
            VStack(alignment: .leading, spacing: 2) {
                Text("Change at \(onward.changeStation)")
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                HStack(spacing: 4) {
                    if !line.isEmpty {
                        Text(line)
                            .font(.system(size: 12, weight: .bold))
                            .foregroundStyle(AppColors.linePill(line, mode: mode))
                    }
                    Text(leg.destName)
                        .font(.system(size: 12, weight: .medium))
                        .lineLimit(1)
                }
                Text("\(Self.timeFormatter.string(from: Date(timeIntervalSince1970: TimeInterval(leg.depTs)))) · \(onward.changeMinutes) min")
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .buttonStyle(.bordered)
    }
}
