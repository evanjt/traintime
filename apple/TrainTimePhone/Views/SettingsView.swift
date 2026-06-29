import SwiftUI

struct PhoneSettingsView: View {
    @ObservedObject var viewModel: PhoneViewModel
    @ObservedObject private var favouritesStore = FavouritesStore.shared
    @Environment(\.dismiss) var dismiss
    @Environment(\.openURL) private var openURL
    @AppStorage("appAppearance") private var appAppearance = AppAppearance.system.rawValue

    var body: some View {
        NavigationStack {
            List {
                Section("Default Mode") {
                    ForEach(TransportMode.allCases) { mode in
                        Button {
                            viewModel.setDefaultMode(mode)
                        } label: {
                            HStack {
                                Image(systemName: mode.sfSymbol)
                                Text(mode.label)
                                    .foregroundStyle(.primary)
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

                Section("Appearance") {
                    ForEach(AppAppearance.allCases) { appearance in
                        Button {
                            appAppearance = appearance.rawValue
                        } label: {
                            HStack {
                                Image(systemName: appearance.symbol)
                                Text(appearance.label)
                                    .foregroundStyle(.primary)
                                Spacer()
                                if appAppearance == appearance.rawValue {
                                    Image(systemName: "checkmark")
                                        .foregroundStyle(.blue)
                                }
                            }
                        }
                        .buttonStyle(.plain)
                    }
                }

                if !favouritesStore.favourites.isEmpty {
                    Section("Favourites (\(favouritesStore.favourites.count))") {
                        ForEach(favouritesStore.favourites) { fav in
                            HStack {
                                Image(systemName: "star.fill")
                                    .font(.caption)
                                    .foregroundStyle(AppColors.favouriteStar)
                                Text(fav.displayString)
                                    .font(.body)
                            }
                        }
                        .onDelete { offsets in
                            let toRemove = offsets.map { favouritesStore.favourites[$0] }
                            toRemove.forEach { favouritesStore.remove($0) }
                        }
                    }
                }

                if viewModel.watchService.garminService.isAvailable {
                    Section {
                        Button {
                            viewModel.watchService.garminService.showDeviceSelection()
                        } label: {
                            HStack {
                                Image(systemName: "watch.analog")
                                Text("Pair a Garmin watch")
                                    .foregroundStyle(.primary)
                                Spacer()
                            }
                        }
                        .buttonStyle(.plain)

                        if viewModel.watchService.garminService.hasKnownDevices {
                            Toggle(isOn: Binding(
                                get: { viewModel.mirrorToWatch },
                                set: { viewModel.setMirrorToWatch($0) }
                            )) {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text("Mirror to watch")
                                    Text("Send your tracked train, mode, station and location to the watch")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                            }
                        }
                    } footer: {
                        Text("Send departures to a Garmin watch. Requires the Garmin Connect app.")
                    }
                }

                Section {
                    Button {
                        if let url = URL(string: "https://apps.apple.com/app/id6760388620?action=write-review") {
                            openURL(url)
                        }
                    } label: {
                        HStack {
                            Image(systemName: "star.fill")
                                .foregroundStyle(AppColors.favouriteStar)
                            Text("Rate TrainTime")
                                .foregroundStyle(.primary)
                            Spacer()
                        }
                    }
                    .buttonStyle(.plain)
                }

                Section {
                    HStack {
                        Text("Version")
                        Spacer()
                        Text(Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "?")
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .navigationTitle("Settings")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }
}
