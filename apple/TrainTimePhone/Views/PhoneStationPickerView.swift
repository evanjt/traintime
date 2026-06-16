import SwiftUI

struct PhoneStationPickerView: View {
    @ObservedObject var viewModel: PhoneViewModel
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List {
                ForEach(Array(viewModel.stations.enumerated()), id: \.element.id) { index, station in
                    HStack(spacing: 12) {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(station.name ?? "?")
                                .font(.body)
                                .foregroundStyle(.primary)
                            Text(GeoUtils.formatWalkInfo(distanceMeters: station.dist ?? 0))
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .contentShape(Rectangle())
                        .onTapGesture {
                            viewModel.selectStation(index: index)
                            dismiss()
                        }

                        // Pin (distinct from the gold departure star).
                        let pinned = viewModel.isStationPinned(station.id)
                        Button {
                            viewModel.togglePinnedStation(station)
                        } label: {
                            Image(systemName: pinned ? "pin.fill" : "pin")
                                .foregroundStyle(pinned ? AppColors.platform : .secondary)
                        }
                        .buttonStyle(.plain)

                        if index == viewModel.stationIndex {
                            Image(systemName: "checkmark")
                                .foregroundStyle(.blue)
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
    }
}
