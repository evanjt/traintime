import SwiftUI
import WatchConnectivity

struct SettingsView: View {
    @ObservedObject var viewModel: TrainTimeViewModel
    @Environment(\.dismiss) var dismiss

    // Phone link status, the peer of the Garmin and Wear settings rows.
    private var phoneReachable: Bool {
        WCSession.isSupported() && WCSession.default.isReachable
    }

    var body: some View {
        List {
            Section("Default Mode") {
                ForEach(TransportMode.allCases) { mode in
                    Button {
                        viewModel.setDefaultMode(mode)
                    } label: {
                        HStack {
                            Image(systemName: mode.sfSymbol)
                            Text(mode.label)
                            Spacer()
                            if viewModel.defaultMode == mode {
                                Image(systemName: "checkmark")
                                    .foregroundStyle(.blue)
                            }
                        }
                    }
                    .buttonStyle(.plain)
                }
            }

            // Quick launch, the peer of Garmin's settings entry: jump to a pinned
            // station, or straight into tracking a favourite once its departure loads.
            let pinned = MyStationsStore.shared.pinned
            if !pinned.isEmpty || !viewModel.favouritesStore.favourites.isEmpty {
                Section("Quick Launch") {
                    ForEach(pinned) { station in
                        Button {
                            viewModel.launchStation(id: station.id, name: station.name, lat: station.lat, lon: station.lon)
                            dismiss()
                        } label: {
                            HStack {
                                Image(systemName: "pin.fill")
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                                Text(station.name).lineLimit(1)
                            }
                        }
                    }
                    ForEach(viewModel.favouritesStore.favourites) { fav in
                        Button {
                            viewModel.launchFavourite(fav)
                            dismiss()
                        } label: {
                            VStack(alignment: .leading, spacing: 1) {
                                Text("\(fav.lineNumber) → \(fav.destination)")
                                    .font(.caption)
                                    .lineLimit(1)
                                Text(fav.stationName)
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                                    .lineLimit(1)
                            }
                        }
                    }
                }
            }

            if !viewModel.favouritesStore.favourites.isEmpty {
                Section("Favourites (\(viewModel.favouritesStore.favourites.count))") {
                    ForEach(viewModel.favouritesStore.favourites) { fav in
                        Text(fav.displayString)
                            .font(.caption)
                            .foregroundStyle(.primary)
                    }
                    .onDelete { offsets in
                        let toRemove = offsets.map { viewModel.favouritesStore.favourites[$0] }
                        toRemove.forEach { viewModel.favouritesStore.remove($0) }
                    }
                }
            }

            Section {
                HStack {
                    Text("iPhone")
                    Spacer()
                    Text(phoneReachable ? "Connected" : "Not reachable")
                        .foregroundStyle(phoneReachable ? Color.green : Color.secondary)
                }
                HStack {
                    Text("Version")
                    Spacer()
                    Text(Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "?")
                        .foregroundStyle(.secondary)
                }
                Button {
                    viewModel.rateOnPhone()
                } label: {
                    Label("Rate on iPhone", systemImage: "star")
                }
            } footer: {
                Text("Opens the review page on your paired iPhone.\nData: opentransportdata.swiss")
            }
        }
        .navigationTitle("Settings")
    }
}
