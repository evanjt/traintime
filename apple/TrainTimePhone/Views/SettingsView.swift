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
    @AppStorage("distanceAwareReminder") private var distanceAwareReminder = true
    @AppStorage("backgroundReminderTracking") private var backgroundReminderTracking = true
    @AppStorage("alertBeforeDeparture") private var alertBeforeDeparture = true
    @State private var notificationsAuthorized: Bool?
    @State private var confirmBackgroundOff = false

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

                    VStack(alignment: .leading, spacing: 2) {
                        Picker("Lead time before departure", selection: $routeLeadMinutes) {
                            ForEach(savedLeadOptions, id: \.self) { Text("\($0) min").tag($0) }
                        }
                        Text("Applies to saved-route reminders and the leave alert while tracking")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }

                    Picker("Before a connection", selection: $connectionLeadMinutes) {
                        ForEach(connectionLeadOptions, id: \.self) { Text("\($0) min").tag($0) }
                    }

                    Toggle("Adjust for distance to station", isOn: $distanceAwareReminder)
                        .onChange(of: distanceAwareReminder) { _, _ in viewModel.syncReminderTracking() }

                    // Governs the whole live session, not just a saved route's
                    // reminder, so it stands on its own. Switching it off takes
                    // tracking away once the app closes, so it is confirmed.
                    Toggle(isOn: $backgroundReminderTracking) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Keep tracking in the background")
                            Text("Tracking keeps running when you leave the app")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                    .onChange(of: backgroundReminderTracking) { _, isOn in
                        if isOn {
                            viewModel.syncReminderTracking()
                        } else {
                            backgroundReminderTracking = true
                            confirmBackgroundOff = true
                        }
                    }

                    Toggle(isOn: $alertBeforeDeparture) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Alert me before departure")
                            Text("A one-off heads-up when it's time to leave while tracking")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }

                    Text(reminderSummary)
                        .font(.footnote)
                        .foregroundStyle(AppColors.platform)

                    if distanceAwareReminder {
                        Button("Test distance reminder") {
                            viewModel.sendDistanceReminderTest()
                        }
                    }
                } header: {
                    Text("Notifications")
                } footer: {
                    Text(distanceAwareReminder
                        ? String(localized: "The lead becomes your walk time to the station plus the minutes above. Background tracking keeps it accurate as you move.")
                        : String(localized: "The connection lead is used once you're already on the way."))
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
                        TrackingHelpView()
                    } label: {
                        HStack {
                            Image(systemName: "info.circle")
                            Text("How tracking works")
                                .foregroundStyle(.primary)
                            Spacer()
                        }
                    }

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
            .alert(
                String(localized: "Tracking will stop when you leave the app"),
                isPresented: $confirmBackgroundOff,
            ) {
                Button(String(localized: "Turn off"), role: .destructive) {
                    backgroundReminderTracking = false
                    viewModel.disableBackgroundTracking()
                }
                Button(String(localized: "Not now"), role: .cancel) {}
            } message: {
                Text("Without background tracking there is no countdown, no leave alert and no Live Activity once TrainTime is closed. Tracking only runs while the app is open. You can turn this back on any time.")
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

// Brief explainer for background tracking, reached from Settings. Mirrors the
// Android TrackingHelpPage. Lives in this file so no new Swift file has to be
// hand-wired into project.pbxproj.
private struct TrackingHelpView: View {
    private struct Point: Identifiable {
        let id = UUID()
        let icon: String
        let title: LocalizedStringKey
        let body: LocalizedStringKey
    }

    private let points: [Point] = [
        Point(icon: "clock", title: "The countdown keeps running",
              body: "It stays live on the Lock Screen and Dynamic Island, even with the app closed."),
        Point(icon: "arrow.triangle.2.circlepath", title: "It checks smartly",
              body: "Updates get more frequent as departure nears, and rare when it's still far away."),
        Point(icon: "battery.75", title: "It saves battery",
              body: "Location only switches on near the station, so a trip hours away costs almost nothing."),
        Point(icon: "figure.walk", title: "It tells you when to leave",
              body: "A one-off alert reminds you to go, based on your walk time to the station."),
    ]

    var body: some View {
        List(points) { point in
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: point.icon)
                    .font(.title3)
                    .foregroundStyle(AppColors.platform)
                    .frame(width: 28)
                VStack(alignment: .leading, spacing: 3) {
                    Text(point.title).font(.headline)
                    Text(point.body).font(.subheadline).foregroundStyle(.secondary)
                }
            }
            .padding(.vertical, 4)
        }
        .navigationTitle("How tracking works")
        .navigationBarTitleDisplayMode(.inline)
    }
}
