import SwiftUI

struct FocusedTrackingView: View {
    @ObservedObject var viewModel: TrainTimeViewModel
    @State private var showMap = false

    var body: some View {
        let focused = viewModel.focusedTrain

        VStack(spacing: 4) {
            // Station name (small, gray)
            Text(viewModel.stationName)
                .font(.system(size: 11))
                .foregroundColor(AppColors.walkInfo)
                .lineLimit(1)

            // Destination + platform
            HStack(spacing: 4) {
                Text(focused?.destination ?? "?")
                    .font(.system(.body, weight: .bold))
                    .foregroundColor(.white)
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)

                if let plat = focused?.platform, !plat.isEmpty {
                    Text("P\(plat)")
                        .font(.caption2)
                        .foregroundColor(
                            focused?.platformChanged == true
                                ? AppColors.platformChangedOrange
                                : AppColors.platform
                        )
                }
            }

            // Countdown
            Text(focused?.countdownText ?? "—")
                .font(.system(.title, design: .monospaced, weight: .bold))
                .foregroundColor(countdownColor)

            // Delay badge
            if let delay = focused?.delay, delay > 0 {
                Text("+\(delay) min")
                    .font(.caption2)
                    .foregroundColor(AppColors.delay)
            }

            // Tracking bar
            TrackingBarView(
                schedBuf: viewModel.trackingScheduledBuffer,
                effectBuf: viewModel.trackingEffectiveBuffer,
                hasGPS: viewModel.gpsQuality != .unavailable
            )
            .padding(.horizontal, 8)

            // Status text
            Text(viewModel.trackingStatusText)
                .font(.caption)
                .foregroundColor(viewModel.trackingStatusColor)

            // Walk info + direction arrow
            HStack(spacing: 6) {
                DirectionArrowView(degrees: viewModel.directionToStation)

                Text(GeoUtils.formatWalkInfo(distanceMeters: viewModel.lastWalkDist))
                    .font(.system(size: 11))
                    .foregroundColor(AppColors.walkInfo)
            }
        }
        .onTapGesture {
            showMap = true
        }
        .sheet(isPresented: $showMap) {
            MapView(viewModel: viewModel)
        }
    }

    private var countdownColor: Color {
        guard let focused = viewModel.focusedTrain else { return .white }
        let secs = focused.secondsUntil
        if secs < -30 { return AppColors.minutesGone }
        if secs < 5 { return AppColors.minutesNow }
        return .white
    }
}
