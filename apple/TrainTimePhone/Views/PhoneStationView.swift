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
                // Watch link indicator, tap launches/​re-syncs the primary watch (Garmin
                // launches remotely; Apple Watch re-syncs when reachable, else shows guidance).
                if viewModel.primaryWatchLiveness != .hidden {
                    Button { viewModel.openWatchApp() } label: {
                        WatchLivenessIndicator(
                            liveness: viewModel.primaryWatchLiveness,
                            isChecking: viewModel.watchChecking,
                            isAppleWatch: viewModel.resolvedPrimaryWatch == .appleWatch
                        )
                    }
                    .buttonStyle(.plain)
                    .padding(.trailing, 4)
                }
                // Crossed pin = zero proof of position: no fix at all, or only a
                // cached coordinate that may be from another city.
                Image(systemName: viewModel.gpsQuality == .lastKnown || viewModel.gpsQuality == .unavailable
                    ? "location.slash.fill" : "location.fill")
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

            // Station name, tappable to open picker
            Button {
                viewModel.showStationPicker = true
            } label: {
                HStack(spacing: 6) {
                    Text(viewModel.stationName)
                        .font(.title.weight(.bold))
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
            .padding(.top, 10)

            // Walk info
            Text(viewModel.walkInfo)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .padding(.top, 2)
                .padding(.bottom, 8)

            // The watch is tracking a departure while the phone shows the board:
            // say so, and (when the full payload is known) tap to follow along.
            if let label = viewModel.watchTrackingLabel {
                Button {
                    viewModel.followWatchTracking()
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: "applewatch")
                            .font(.system(size: 13))
                            .foregroundStyle(.green)
                        Text("Tracking on watch · \(label)")
                            .font(.footnote)
                            .foregroundStyle(.primary)
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                    .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 12))
                }
                .buttonStyle(.plain)
                .disabled(!viewModel.watchTrackingFollowable)
                .padding(.bottom, 8)
            }

            // Departure list
            if viewModel.departures.isEmpty {
                Spacer()
                if viewModel.stations.isEmpty {
                    ZStack {
                        if viewModel.status == PhoneViewModel.outOfBoundsStatus {
                            SwissOutlineBackdrop()
                        }
                        Text(viewModel.status)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.center)
                            .padding(.horizontal, 32)
                    }
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
                .listStyle(.insetGrouped)
                .scrollContentBackground(.hidden)
                .environment(\.defaultMinListRowHeight, 2)
                .refreshable { await viewModel.forceRefresh() }
                // A timer or switch refresh dims the list and shows a slim bar,
                // so the board freezes in place rather than vanishing.
                .opacity(viewModel.departuresRefreshing ? 0.5 : 1)
                .overlay(alignment: .top) {
                    if viewModel.departuresRefreshing {
                        ProgressView()
                            .progressViewStyle(.linear)
                    }
                }
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
        PhoneDepartureRowView(departure: departure, isFavourite: isFavourite, mode: viewModel.currentMode, onTap: onTap)
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
            .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                if !departure.isGone {
                    Button {
                        viewModel.saveDepartureAsPending(departure)
                    } label: {
                        Label("Remind me", systemImage: "bell.fill")
                    }
                    .tint(.blue)
                }
            }
            .contextMenu {
                Button {
                    viewModel.toggleFavourite(departure: departure)
                } label: {
                    Label(isFavourite ? "Remove Favourite" : "Add Favourite",
                          systemImage: isFavourite ? "star.slash" : "star")
                }
                if !departure.isGone {
                    Button {
                        viewModel.saveDepartureAsPending(departure)
                    } label: {
                        Label("Remind me before departure", systemImage: "bell")
                    }
                }
            }
    }
}
