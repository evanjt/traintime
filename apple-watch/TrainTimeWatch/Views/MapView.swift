import SwiftUI
import MapKit

struct MapView: View {
    @ObservedObject var viewModel: TrainTimeViewModel

    var body: some View {
        if let station = viewModel.currentStation,
           let stationCoord = station.coordinate {
            Map {
                // Station annotation
                Marker(station.name ?? "Station", coordinate: stationCoord)
                    .tint(.red)

                // User location shown via default Map behavior
                UserAnnotation()
            }
            .mapStyle(.standard)
            .mapControls {
                MapUserLocationButton()
            }
        } else {
            Text("No station selected")
                .foregroundColor(AppColors.bodyStatus)
        }
    }
}
