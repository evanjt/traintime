import SwiftUI
import MapKit

struct MapView: View {
    @ObservedObject var viewModel: TrainTimeViewModel
    @Environment(\.dismiss) var dismiss

    var body: some View {
        NavigationStack {
            if let station = viewModel.currentStation,
               let stationCoord = station.coordinate {
                Map {
                    // Station annotation
                    Marker(station.name ?? String(localized: "Station"), coordinate: stationCoord)
                        .tint(.red)

                    // User location shown via default Map behavior
                    UserAnnotation()
                }
                .mapStyle(.standard)
                .mapControls {
                    MapUserLocationButton()
                }
                .toolbar {
                    ToolbarItem(placement: .bottomBar) {
                        Button {
                            let destination = MKMapItem(placemark: MKPlacemark(coordinate: stationCoord))
                            destination.name = station.name ?? String(localized: "Station")
                            destination.openInMaps(launchOptions: [
                                MKLaunchOptionsDirectionsModeKey: MKLaunchOptionsDirectionsModeWalking
                            ])
                        } label: {
                            Label("Navigate", systemImage: "figure.walk")
                        }
                    }
                }
            } else {
                Text("No station selected")
                    .foregroundColor(AppColors.bodyStatus)
            }
        }
    }
}
