import SwiftUI

struct PhoneSettingsView: View {
    @ObservedObject var viewModel: PhoneViewModel
    @ObservedObject private var favouritesStore = FavouritesStore.shared
    @Environment(\.dismiss) var dismiss
    @Environment(\.openURL) private var openURL
    @AppStorage("appAppearance") private var appAppearance = AppAppearance.system.rawValue
    @AppStorage("hasSeenOnboarding") private var hasSeenOnboarding = false

    private func watchStatusText(_ liveness: WatchLiveness) -> String {
        switch liveness {
        case .green: return "Open"
        case .amber: return "App closed"
        case .grey: return "Not connected"
        case .hidden: return ""
        }
    }

    var body: some View {
        NavigationStack {
            List {
                Section("Default Mode") {
                    Picker("Default Mode", selection: Binding(
                        get: { viewModel.defaultMode },
                        set: { viewModel.setDefaultMode($0) }
                    )) {
                        ForEach(TransportMode.allCases) { mode in
                            Text(mode.label).tag(mode)
                        }
                    }
                    .pickerStyle(.segmented)
                    .labelsHidden()
                }

                Section("Appearance") {
                    Picker("Appearance", selection: $appAppearance) {
                        ForEach(AppAppearance.allCases) { appearance in
                            Text(appearance.label).tag(appearance.rawValue)
                        }
                    }
                    .pickerStyle(.segmented)
                    .labelsHidden()
                }

                if !favouritesStore.favourites.isEmpty {
                    Section {
                        NavigationLink {
                            FavouritesManagementView(favouritesStore: favouritesStore)
                        } label: {
                            HStack {
                                Image(systemName: "star.fill")
                                    .font(.caption)
                                    .foregroundStyle(AppColors.favouriteStar)
                                Text("Favourites")
                                Spacer()
                                Text("\(favouritesStore.favourites.count)")
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                }

                let garminAvailable = viewModel.watchService.garminService.isAvailable
                let appleKnown = viewModel.watchService.hasKnownAppleWatch
                let garminKnown = viewModel.watchService.hasKnownGarmin
                if garminAvailable || appleKnown {
                    Section {
                        if appleKnown {
                            HStack {
                                WatchLivenessIndicator(liveness: viewModel.appleWatchLiveness, isAppleWatch: true)
                                Text("Apple Watch")
                                Spacer()
                                Text(watchStatusText(viewModel.appleWatchLiveness))
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }

                        if garminAvailable {
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

                            if garminKnown {
                                HStack {
                                    WatchLivenessIndicator(liveness: viewModel.garminLiveness)
                                    Text("Garmin")
                                    Spacer()
                                    Text(watchStatusText(viewModel.garminLiveness))
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                            }
                        }

                        if viewModel.bothWatchesKnown {
                            Picker("Primary watch", selection: Binding(
                                get: { viewModel.primaryWatch },
                                set: { viewModel.setPrimaryWatch($0) }
                            )) {
                                Text("Auto").tag(PrimaryWatchPreference.auto)
                                Text("Apple Watch").tag(PrimaryWatchPreference.appleWatch)
                                Text("Garmin").tag(PrimaryWatchPreference.garmin)
                            }
                        }

                        if appleKnown || garminKnown {
                            Toggle(isOn: Binding(
                                get: { viewModel.mirrorToWatch },
                                set: { viewModel.setMirrorToWatch($0) }
                            )) {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text("Mirror to watch")
                                    Text("Send your tracked train, mode, station and location to your watch")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                            }
                        }
                    } footer: {
                        Text("Mirror your departures to a watch. Garmin requires the Garmin Connect app.")
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

                    Button {
                        dismiss()
                        hasSeenOnboarding = false
                    } label: {
                        HStack {
                            Image(systemName: "questionmark.circle")
                            Text("Replay walkthrough")
                                .foregroundStyle(.primary)
                            Spacer()
                        }
                    }
                    .buttonStyle(.plain)

                    NavigationLink {
                        PhoneAttributionView()
                    } label: {
                        HStack {
                            Image(systemName: "doc.text")
                            Text("Attribution")
                                .foregroundStyle(.primary)
                            Spacer()
                        }
                    }
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

// Lives in this file: adding a Swift file means hand-editing project.pbxproj.
private struct FavouritesManagementView: View {
    @ObservedObject var favouritesStore: FavouritesStore

    var body: some View {
        List {
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
        .navigationTitle("Favourites")
        .toolbar { EditButton() }
        .overlay {
            if favouritesStore.favourites.isEmpty {
                Text("No favourites yet")
                    .foregroundStyle(.secondary)
            }
        }
    }
}
