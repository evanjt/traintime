import SwiftUI
import UserNotifications

struct PhoneSettingsView: View {
    @ObservedObject var viewModel: PhoneViewModel
    @ObservedObject private var favouritesStore = FavouritesStore.shared
    @Environment(\.dismiss) var dismiss
    @Environment(\.openURL) private var openURL
    @Environment(\.scenePhase) private var scenePhase
    @AppStorage("appAppearance") private var appAppearance = AppAppearance.system.rawValue
    @AppStorage("hasSeenOnboarding") private var hasSeenOnboarding = false
    @AppStorage("seenOnboardingVersion") private var seenOnboardingVersion = 0
    @AppStorage("routeReminderLeadMinutes") private var routeLeadMinutes = 15
    @AppStorage("connectionReminderLeadMinutes") private var connectionLeadMinutes = 3
    @AppStorage("distanceAwareReminder") private var distanceAwareReminder = false
    @AppStorage("backgroundReminderTracking") private var backgroundReminderTracking = true
    @State private var notificationsAuthorized: Bool?

    private var reminderSummary: String {
        distanceAwareReminder
            ? String(localized: "You'll be notified your walk time + \(routeLeadMinutes) min before departure")
            : String(localized: "You'll be notified \(routeLeadMinutes) min before departure")
    }

    private let savedLeadOptions = [5, 10, 15, 30]
    private let connectionLeadOptions = [2, 3, 4, 5]

    private func refreshNotificationStatus() {
        UNUserNotificationCenter.current().getNotificationSettings { settings in
            let ok = settings.authorizationStatus == .authorized
                || settings.authorizationStatus == .provisional
            DispatchQueue.main.async { notificationsAuthorized = ok }
        }
    }

    private func watchStatusText(_ liveness: WatchLiveness) -> String {
        switch liveness {
        case .green: return String(localized: "Open")
        case .amber: return String(localized: "App closed")
        case .grey: return String(localized: "Not connected")
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

                    Button {
                        if let url = URL(string: UIApplication.openSettingsURLString) {
                            openURL(url)
                        }
                    } label: {
                        HStack {
                            Image(systemName: "globe")
                            Text("Language")
                                .foregroundStyle(.primary)
                            Spacer()
                        }
                    }
                    .buttonStyle(.plain)
                }

                Section {
                    HStack {
                        Text("Notifications")
                        Spacer()
                        switch notificationsAuthorized {
                        case .some(true):
                            Text("Allowed").foregroundStyle(.secondary)
                        case .some(false):
                            Button("Turn on") {
                                if let url = URL(string: UIApplication.openSettingsURLString) {
                                    openURL(url)
                                }
                            }
                        case .none:
                            Text("").foregroundStyle(.secondary)
                        }
                    }

                    Picker("Remind me before departure", selection: $routeLeadMinutes) {
                        ForEach(savedLeadOptions, id: \.self) { Text("\($0) min").tag($0) }
                    }

                    Picker("Before a connection", selection: $connectionLeadMinutes) {
                        ForEach(connectionLeadOptions, id: \.self) { Text("\($0) min").tag($0) }
                    }

                    Toggle("Adjust for distance to station", isOn: $distanceAwareReminder)
                        .onChange(of: distanceAwareReminder) { _, _ in viewModel.syncReminderTracking() }

                    if distanceAwareReminder {
                        Toggle("Update in the background", isOn: $backgroundReminderTracking)
                            .onChange(of: backgroundReminderTracking) { _, _ in viewModel.syncReminderTracking() }
                    }

                    Text(reminderSummary)
                        .font(.footnote)
                        .foregroundStyle(AppColors.platform)

                    Button("Send test notification") {
                        PendingRouteNotifier.sendTest()
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                            refreshNotificationStatus()
                        }
                    }

                    if distanceAwareReminder {
                        Button("Test distance reminder") {
                            viewModel.sendDistanceReminderTest()
                        }
                    }
                } header: {
                    Text("Route reminders")
                } footer: {
                    Text(distanceAwareReminder
                        ? String(localized: "The lead becomes your walk time to the station plus the minutes above. Background updates keep it accurate as you move.")
                        : String(localized: "Reminders for a saved route. The connection lead is used once you're already on the way."))
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
                        // Replay the FULL tour: clear both the flag and the seen
                        // version so every step shows again.
                        hasSeenOnboarding = false
                        seenOnboardingVersion = 0
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
            .onAppear { refreshNotificationStatus() }
            .onChange(of: scenePhase) { _, phase in
                if phase == .active { refreshNotificationStatus() }
            }
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
