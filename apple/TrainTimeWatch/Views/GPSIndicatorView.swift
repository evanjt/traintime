import SwiftUI

struct GPSIndicatorView: View {
    let quality: GPSQuality

    var body: some View {
        // Crossed pin = zero proof of position (no fix, or a cached coordinate).
        Image(systemName: quality == .lastKnown || quality == .unavailable
            ? "location.slash.fill" : "location.fill")
            .font(.system(size: 14))
            .foregroundStyle(quality.color)
    }
}
