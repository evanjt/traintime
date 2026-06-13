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
                    .font(.system(size: 16))
                    .foregroundStyle(viewModel.gpsQuality.color)
                Button { showSettings = true } label: {
                    Image(systemName: "gearshape")
                        .font(.system(size: 18))
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
                    if !viewModel.favouriteDepartures.isEmpty {
                        Section {
                            // IDs namespaced so a favourite that also appears in the regular
                            // section below doesn't collide on identity within the List.
                            ForEach(viewModel.favouriteDepartures.map(FavRow.init)) { row in
                                departureRow(row.departure, isFavourite: true) {
                                    viewModel.selectFavouriteDeparture(row.departure)
                                }
                                .listRowSeparator(.hidden)
                            }
                            if !viewModel.departures.isEmpty {
                                Rectangle()
                                    .fill(AppColors.favouriteSeparator)
                                    .frame(height: 2)
                                    .listRowInsets(EdgeInsets())
                                    .listRowSeparator(.hidden)
                                    .listRowBackground(Color.clear)
                            }
                        }
                    }
                    Section {
                        ForEach(Array(viewModel.departures.enumerated()), id: \.element.stableId) { index, departure in
                            departureRow(departure, isFavourite: viewModel.isDepartureFavourite(departure)) {
                                viewModel.selectDeparture(index: index)
                            }
                        }
                    }
                }
                .listStyle(.plain)
                .scrollContentBackground(.hidden)
                .environment(\.defaultMinListRowHeight, 2)
                .refreshable { await viewModel.forceRefresh() }
            }
        }
        .sheet(isPresented: $viewModel.showStationPicker) {
            PhoneStationPickerView(viewModel: viewModel)
        }
        .sheet(isPresented: $showSettings) {
            PhoneSettingsView(viewModel: viewModel)
        }
    }

    /// Wrapper giving favourite rows a namespaced, fetch-stable List identity.
    private struct FavRow: Identifiable {
        let departure: Departure
        var id: String { "fav-" + departure.stableId }
        init(_ departure: Departure) { self.departure = departure }
    }

    @ViewBuilder
    private func departureRow(_ departure: Departure, isFavourite: Bool, onTap: @escaping () -> Void) -> some View {
        PhoneDepartureRowView(departure: departure, isFavourite: isFavourite, onTap: onTap)
            .listRowInsets(EdgeInsets(top: 0, leading: 16, bottom: 0, trailing: 16))
            .listRowBackground(isFavourite ? AppColors.favouriteBackground : nil)
            .swipeActions(edge: .leading, allowsFullSwipe: true) {
                Button {
                    viewModel.toggleFavourite(departure: departure)
                } label: {
                    Label(isFavourite ? "Unfavourite" : "Favourite",
                          systemImage: isFavourite ? "star.slash.fill" : "star.fill")
                }
                .tint(AppColors.favouriteStar)
            }
            .contextMenu {
                Button {
                    viewModel.toggleFavourite(departure: departure)
                } label: {
                    Label(isFavourite ? "Remove Favourite" : "Add Favourite",
                          systemImage: isFavourite ? "star.slash" : "star")
                }
            }
    }
}
