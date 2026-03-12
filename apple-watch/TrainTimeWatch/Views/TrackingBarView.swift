import SwiftUI

struct TrackingBarView: View {
    let schedBuf: Double  // scheduled buffer (minutes)
    let effectBuf: Double // effective buffer with delay (minutes)
    let hasGPS: Bool

    private let barHeight: CGFloat = 12
    private let scale = Thresholds.barScale // ±3 minutes maps to half bar

    var body: some View {
        GeometryReader { geo in
            let width = geo.size.width
            let midX = width / 2

            ZStack(alignment: .leading) {
                // Background
                RoundedRectangle(cornerRadius: 3)
                    .fill(Color.black)

                if !hasGPS {
                    // Gray bar when no GPS
                    RoundedRectangle(cornerRadius: 3)
                        .fill(AppColors.barGray)
                } else {
                    drawBar(width: width, midX: midX)
                }

                // Center marker
                Rectangle()
                    .fill(AppColors.barGray.opacity(0.8))
                    .frame(width: 2)
                    .offset(x: midX - 1)
            }
        }
        .frame(height: barHeight)
        .clipShape(RoundedRectangle(cornerRadius: 3))
    }

    @ViewBuilder
    private func drawBar(width: CGFloat, midX: CGFloat) -> some View {
        let schedPos = bufferToPosition(schedBuf, midX: midX, width: width)
        let effectPos = bufferToPosition(effectBuf, midX: midX, width: width)

        if schedBuf >= 0 && effectBuf >= 0 {
            // Both positive: dark green (guaranteed) + light green (delay bonus)
            // Dark green from mid to schedBuf
            Rectangle()
                .fill(AppColors.darkGreen)
                .frame(width: max(0, schedPos - midX))
                .offset(x: midX)
            // Light green from schedBuf to effectBuf (delay bonus)
            if effectPos > schedPos {
                Rectangle()
                    .fill(AppColors.lightGreen)
                    .frame(width: effectPos - schedPos)
                    .offset(x: schedPos)
            }
        } else if schedBuf < 0 && effectBuf < 0 {
            // Both negative: dark red (irrecoverable) + amber (approaching zero)
            Rectangle()
                .fill(AppColors.darkRed)
                .frame(width: max(0, midX - effectPos))
                .offset(x: effectPos)
            if schedPos < effectPos {
                Rectangle()
                    .fill(AppColors.amber)
                    .frame(width: effectPos - schedPos)
                    .offset(x: schedPos)
            }
        } else if schedBuf < 0 && effectBuf >= 0 {
            // Mixed: schedule behind but delay saves it
            // Amber from schedBuf to mid
            Rectangle()
                .fill(AppColors.amber)
                .frame(width: max(0, midX - schedPos))
                .offset(x: schedPos)
            // Light green from mid to effectBuf
            Rectangle()
                .fill(AppColors.lightGreen)
                .frame(width: max(0, effectPos - midX))
                .offset(x: midX)
        }
    }

    private func bufferToPosition(_ buffer: Double, midX: CGFloat, width: CGFloat) -> CGFloat {
        let clamped = max(-scale, min(scale, buffer))
        let fraction = clamped / scale
        return midX + CGFloat(fraction) * midX
    }
}
