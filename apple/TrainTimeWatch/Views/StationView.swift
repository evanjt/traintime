import SwiftUI

struct StationView: View {
    @ObservedObject var viewModel: TrainTimeViewModel

    var body: some View {
        VStack(spacing: 4) {
            // Mode selector + GPS indicator
            HStack {
                ModeIndicatorView(
                    availableModes: viewModel.availableModes,
                    currentMode: viewModel.currentMode,
                    onSelect: { viewModel.selectMode($0) }
                )
                Spacer()
                GPSIndicatorView(quality: viewModel.gpsQuality)
            }
            .padding(.horizontal, 2)

            // Walk info
            Text(viewModel.walkInfo)
                .font(.footnote)
                .foregroundStyle(.secondary)
                .lineLimit(1)

            // Station name — tappable to open picker
            Button {
                viewModel.showStationPicker = true
            } label: {
                HStack(spacing: 4) {
                    Text(viewModel.stationName.uppercased())
                        .font(.system(.headline, weight: .bold))
                        .foregroundStyle(.primary)
                        .minimumScaleFactor(0.5)
                        .lineLimit(1)
                    if viewModel.stations.count > 1 {
                        Image(systemName: "chevron.down")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .buttonStyle(.plain)

            Divider()
                .padding(.horizontal, 4)

            // Departure list
            if viewModel.departures.isEmpty {
                Spacer()
                if viewModel.stations.isEmpty {
                    Text(viewModel.status)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                } else {
                    ProgressView()
                        .tint(.secondary)
                }
                Spacer()
            } else {
                ScrollView {
                    VStack(spacing: 0) {
                        ForEach(Array(viewModel.departures.enumerated()), id: \.element.id) { index, departure in
                            DepartureRowView(
                                departure: departure,
                                onTap: { viewModel.selectDeparture(index: index) }
                            )
                        }
                    }
                }
            }
        }
        .sheet(isPresented: $viewModel.showStationPicker) {
            StationPickerView(viewModel: viewModel)
        }
    }
}
