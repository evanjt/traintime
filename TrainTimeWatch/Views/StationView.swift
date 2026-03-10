import SwiftUI

struct StationView: View {
    @ObservedObject var viewModel: TrainTimeViewModel

    var body: some View {
        VStack(spacing: 2) {
            // Mode indicators + GPS dot
            HStack {
                if viewModel.availableModes.count > 1 {
                    ModeIndicatorView(
                        availableModes: viewModel.availableModes,
                        currentMode: viewModel.currentMode,
                        onSelect: { viewModel.selectMode($0) }
                    )
                }
                Spacer()
                GPSIndicatorView(quality: viewModel.gpsQuality)
            }
            .padding(.horizontal, 4)

            // Walk info
            Text(viewModel.walkInfo)
                .font(.system(size: 12))
                .foregroundColor(AppColors.walkInfo)
                .lineLimit(1)

            // Station name
            Text(viewModel.stationName.uppercased())
                .font(.system(.title3, design: .default, weight: .bold))
                .foregroundColor(.white)
                .minimumScaleFactor(0.5)
                .lineLimit(1)

            // Separator
            AppColors.separator
                .frame(height: 1)
                .padding(.horizontal, 8)
                .padding(.vertical, 2)

            // Departures list
            if viewModel.departures.isEmpty {
                Spacer()
                Text(viewModel.stations.isEmpty ? viewModel.status : "Loading...")
                    .font(.callout)
                    .foregroundColor(AppColors.bodyStatus)
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
