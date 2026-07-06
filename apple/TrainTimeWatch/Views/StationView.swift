import SwiftUI

struct StationView: View {
    @ObservedObject var viewModel: TrainTimeViewModel
    @State private var showSettings = false

    var body: some View {
        VStack(spacing: 4) {
            // Mode selector + GPS + Settings
            HStack {
                ModeIndicatorView(
                    availableModes: viewModel.availableModes,
                    currentMode: viewModel.currentMode,
                    onSelect: { viewModel.selectMode($0) }
                )
                Spacer()
                GPSIndicatorView(quality: viewModel.gpsQuality)
                Button { showSettings = true } label: {
                    Image(systemName: "gearshape")
                        .font(.system(size: 14))
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 2)

            // Walk info
            Text(viewModel.walkInfo)
                .font(.footnote)
                .foregroundStyle(.secondary)
                .lineLimit(1)

            // Station name, tappable to open picker
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
                        // Favourite departures at top
                        ForEach(Array(viewModel.favouriteDepartures.enumerated()), id: \.offset) { _, departure in
                            DepartureRowView(
                                departure: departure,
                                isFavourite: true,
                                onTap: {
                                    viewModel.selectFavouriteDeparture(departure)
                                }
                            )
                        }
                        // Separator line under favourites
                        if !viewModel.favouriteDepartures.isEmpty && !viewModel.departures.isEmpty {
                            Rectangle()
                                .fill(AppColors.favouriteSeparator)
                                .frame(height: 2)
                                .padding(.horizontal, 4)
                        }
                        // Regular departures
                        ForEach(Array(viewModel.departures.enumerated()), id: \.element.id) { index, departure in
                            DepartureRowView(
                                departure: departure,
                                isFavourite: viewModel.isDepartureFavourite(departure),
                                onTap: { viewModel.selectDeparture(index: index) }
                            )
                        }
                    }
                }
                // A refresh dims the list rather than blanking the board.
                .opacity(viewModel.departuresRefreshing ? 0.5 : 1)
            }
        }
        .sheet(isPresented: $viewModel.showStationPicker) {
            StationPickerView(viewModel: viewModel)
        }
        .sheet(isPresented: $showSettings) {
            SettingsView(viewModel: viewModel)
        }
    }
}
