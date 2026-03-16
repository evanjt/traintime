import SwiftUI

struct PhoneStationPickerView: View {
    @ObservedObject var viewModel: PhoneViewModel
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List {
                ForEach(Array(viewModel.stations.enumerated()), id: \.element.id) { index, station in
                    Button {
                        viewModel.selectStation(index: index)
                        dismiss()
                    } label: {
                        HStack {
                            VStack(alignment: .leading, spacing: 4) {
                                Text(station.name ?? "?")
                                    .font(.body)
                                    .foregroundStyle(.primary)
                                Text(GeoUtils.formatWalkInfo(distanceMeters: station.dist ?? 0))
                                    .font(.caption)
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
            .navigationTitle("Stations")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
        .preferredColorScheme(.dark)
    }
}
