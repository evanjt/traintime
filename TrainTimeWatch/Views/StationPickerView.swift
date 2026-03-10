import SwiftUI

struct StationPickerView: View {
    @ObservedObject var viewModel: TrainTimeViewModel

    var body: some View {
        List {
            ForEach(Array(viewModel.stations.enumerated()), id: \.element.id) { index, station in
                Button {
                    viewModel.selectStation(index: index)
                } label: {
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(station.name ?? "?")
                                .font(.body)
                                .foregroundStyle(.primary)
                            Text(GeoUtils.formatWalkInfo(distanceMeters: station.dist ?? 0))
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                        if index == viewModel.stationIndex {
                            Image(systemName: "checkmark")
                                .foregroundStyle(.blue)
                        }
                    }
                }
            }
        }
    }
}
