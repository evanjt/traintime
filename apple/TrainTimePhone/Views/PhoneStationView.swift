import SwiftUI

struct PhoneStationView: View {
    @ObservedObject var viewModel: PhoneViewModel

    var body: some View {
        VStack(spacing: 0) {
            // Header: Mode picker + GPS
            HStack {
                PhoneModePickerView(
                    availableModes: viewModel.availableModes,
                    currentMode: viewModel.currentMode,
                    onSelect: { viewModel.selectMode($0) }
                )
                Spacer()
                GPSIndicatorView(quality: viewModel.gpsQuality)
            }
            .padding(.horizontal, 16)
            .padding(.top, 8)

            // Walk info
            Text(viewModel.walkInfo)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .padding(.top, 4)

            // Station name — tappable to open picker
            Button {
                viewModel.showStationPicker = true
            } label: {
                HStack(spacing: 6) {
                    Text(viewModel.stationName.uppercased())
                        .font(.title3.weight(.bold))
                        .foregroundStyle(.primary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.6)
                    if viewModel.stations.count > 1 {
                        Image(systemName: "chevron.down")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .buttonStyle(.plain)
            .padding(.top, 4)

            Divider()
                .padding(.horizontal, 16)
                .padding(.vertical, 8)

            // Departure list
            if viewModel.departures.isEmpty {
                Spacer()
                if viewModel.stations.isEmpty {
                    Text(viewModel.status)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 32)
                } else {
                    ProgressView()
                        .tint(.secondary)
                }
                Spacer()
            } else {
                List {
                    ForEach(Array(viewModel.departures.enumerated()), id: \.element.id) { index, departure in
                        PhoneDepartureRowView(
                            departure: departure,
                            onTap: { viewModel.selectDeparture(index: index) }
                        )
                        .listRowInsets(EdgeInsets(top: 4, leading: 16, bottom: 4, trailing: 16))
                    }
                }
                .listStyle(.plain)
            }
        }
        .sheet(isPresented: $viewModel.showStationPicker) {
            PhoneStationPickerView(viewModel: viewModel)
        }
    }
}
