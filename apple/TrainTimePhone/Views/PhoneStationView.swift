import SwiftUI

struct PhoneStationView: View {
    @ObservedObject var viewModel: PhoneViewModel
    @State private var showSettings = false

    var body: some View {
        VStack(spacing: 0) {
            // Header: Mode picker + GPS + Settings
            HStack {
                PhoneModePickerView(
                    availableModes: viewModel.availableModes,
                    currentMode: viewModel.currentMode,
                    onSelect: { viewModel.selectMode($0) }
                )
                Spacer()
                Image(systemName: "location.fill")
                    .font(.system(size: 12))
                    .foregroundStyle(viewModel.gpsQuality.color)
                Button { showSettings = true } label: {
                    Image(systemName: "gearshape")
                        .font(.system(size: 16))
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
                .padding(.leading, 8)
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
                    Text(viewModel.stationName)
                        .font(.title2.weight(.bold))
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
                .overlay(Color.gray.opacity(0.3))
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
                ScrollView {
                    LazyVStack(spacing: 0) {
                        ForEach(Array(viewModel.departures.enumerated()), id: \.element.id) { index, departure in
                            PhoneDepartureRowView(
                                departure: departure,
                                onTap: { viewModel.selectDeparture(index: index) }
                            )
                            .padding(.horizontal, 16)

                            if index < viewModel.departures.count - 1 {
                                Divider()
                                    .overlay(Color.gray.opacity(0.2))
                                    .padding(.horizontal, 16)
                            }
                        }
                    }
                }
            }
        }
        .background(Color.black)
        .sheet(isPresented: $viewModel.showStationPicker) {
            PhoneStationPickerView(viewModel: viewModel)
        }
        .sheet(isPresented: $showSettings) {
            PhoneSettingsView(viewModel: viewModel)
        }
    }
}
