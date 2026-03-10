import SwiftUI

struct GPSIndicatorView: View {
    let quality: GPSQuality

    var body: some View {
        Circle()
            .fill(quality.color)
            .frame(width: 6, height: 6)
    }
}
