import SwiftUI

struct GPSIndicatorView: View {
    let quality: GPSQuality

    var body: some View {
        Image(systemName: "location.fill")
            .font(.system(size: 14))
            .foregroundStyle(quality.color)
    }
}
