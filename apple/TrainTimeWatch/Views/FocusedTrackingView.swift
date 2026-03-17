import SwiftUI

struct FocusedTrackingView: View {
    @ObservedObject var viewModel: TrainTimeViewModel
    @State private var showMap = false

    var body: some View {
        let focused = viewModel.focusedTrain

        ScrollView {
            VStack(spacing: 4) {
                // Station name
                Text(viewModel.stationName)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)

                // Destination + platform
                let platChanged = focused?.platformChanged == true
                HStack(spacing: 4) {
                    Text(focused.map { $0.lineNumber.isEmpty ? $0.destination : "\($0.lineNumber) \($0.destination)" } ?? "?")
                        .font(.system(.headline, weight: .bold))
                        .foregroundStyle(platChanged ? AppColors.platformChangedOrange : .primary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.6)

                    if let plat = focused?.platform, !plat.isEmpty {
                        Text("P\(plat)")
                            .font(.system(.caption2, weight: .medium))
                            .foregroundStyle(platChanged ? .white : AppColors.platform)
                            .padding(.horizontal, 4)
                            .padding(.vertical, 2)
                            .background(
                                platChanged
                                    ? Capsule().fill(AppColors.platformChangedOrange)
                                    : Capsule().fill(.clear)
                            )
                    }
                }

                // Countdown
                Text(focused?.countdownText ?? "—")
                    .font(.system(.title2, design: .rounded, weight: .bold))
                    .monospacedDigit()
                    .foregroundStyle(countdownColor)

                // Delay badge
                if let delay = focused?.delay, delay > 0,
                   let f = focused, f.minutesUntil >= -0.5 {
                    Text("+\(delay)")
                        .font(.system(.caption2, weight: .medium))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(Capsule().fill(AppColors.delay))
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
                    .font(.system(.subheadline, weight: .semibold))
                    .foregroundStyle(viewModel.trackingStatusColor)

                // Walk info + direction
                HStack(spacing: 6) {
                    DirectionArrowView(degrees: viewModel.directionToStation)

                    Text(GeoUtils.formatWalkInfo(distanceMeters: viewModel.lastWalkDist, walkTimeSeconds: viewModel.lastWalkTime))
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }
            .padding(.horizontal, 2)
        }
        .onTapGesture {
            showMap = true
        }
        .sheet(isPresented: $showMap) {
            MapView(viewModel: viewModel)
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
