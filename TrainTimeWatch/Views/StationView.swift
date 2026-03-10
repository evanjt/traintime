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

            // Station name
            Text(viewModel.stationName.uppercased())
                .font(.system(.headline, weight: .bold))
                .foregroundStyle(.primary)
                .minimumScaleFactor(0.5)
                .lineLimit(1)

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
                let visible = Array(viewModel.departures.prefix(viewModel.maxVisibleDepartures))
                ForEach(Array(visible.enumerated()), id: \.element.id) { index, departure in
                    DepartureRowView(
                        departure: departure,
                        isHighlighted: viewModel.crownHighlightIndex == index,
                        onTap: { viewModel.selectDeparture(index: index) }
                    )
                }
                Spacer(minLength: 0)
            }
        }
    }
}
