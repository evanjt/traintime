import SwiftUI
import CoreLocation

struct StatusView: View {
    let status: String
    let coordinate: CLLocationCoordinate2D?

    var body: some View {
        VStack(spacing: 8) {
            Text(status)
                .font(.callout)
                .foregroundColor(.white)
                .multilineTextAlignment(.center)

            if let coord = coordinate {
                Text(String(format: "%.4f, %.4f", coord.latitude, coord.longitude))
                    .font(.system(size: 12))
                    .foregroundColor(AppColors.bodyStatus)
            }
        }
    }
}
