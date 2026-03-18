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

                // Destination
                let platChanged = focused?.platformChanged == true
                HStack(spacing: 4) {
                    if let f = focused, !f.lineNumber.isEmpty {
                        Text(f.lineNumber)
                            .font(.system(.headline, weight: .bold))
                            .foregroundStyle(AppColors.platform)
                    }
                    Text(focused?.destination ?? "?")
                        .font(.system(.headline, weight: .bold))
                        .foregroundStyle(platChanged ? AppColors.platformChangedOrange : .primary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.6)
                }

                // Platform
                if let plat = focused?.platform, !plat.isEmpty {
                    Text("Platform \(plat)")
                        .font(.system(.caption2, weight: .medium))
                        .foregroundStyle(platChanged ? AppColors.platformChangedOrange : .secondary)
                }

                // Countdown + delay
                HStack(spacing: 6) {
                    Text(focused?.countdownText ?? "—")
                        .font(.system(.title2, design: .rounded, weight: .bold))
                        .monospacedDigit()
                        .foregroundStyle(countdownColor)

                    if let delay = focused?.delay, delay > 0,
                       let f = focused, f.minutesUntil >= -0.5 {
                        Text("+\(delay)")
                            .font(.system(.caption2, weight: .medium))
                            .foregroundStyle(.white)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
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
                    .font(.system(.subheadline, weight: .semibold))
                    .foregroundStyle(viewModel.trackingStatusColor)

                // Walk info + direction
                HStack(spacing: 6) {
                    DirectionArrowView(degrees: viewModel.directionToStation)

                    Text(GeoUtils.formatWalkInfo(distanceMeters: viewModel.lastWalkDist, walkTimeSeconds: viewModel.lastWalkTime))
                        .font(.footnote)
                        .foregroundStyle(.secondary)

                    Image(systemName: viewModel.useRoutedDistance ? "point.bottomleft.forward.to.point.topright.scurvepath" : "line.diagonal")
                        .font(.system(size: 10))
                        .foregroundStyle(.tertiary)
                }
                .onTapGesture {
                    viewModel.toggleRoutedDistance()
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
