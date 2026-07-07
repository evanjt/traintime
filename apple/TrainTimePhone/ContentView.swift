import SwiftUI

struct ContentView: View {
    @StateObject private var viewModel = PhoneViewModel()
    @ObservedObject private var pendingRouteStore = PendingRouteStore.shared
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.openURL) private var openURL
    @AppStorage("hasSeenOnboarding") private var hasSeenOnboarding = false
    @AppStorage("seenOnboardingVersion") private var seenOnboardingVersion = 0
    @AppStorage("appAppearance") private var appAppearance = AppAppearance.system.rawValue
    @State private var showTourHint = false
    @State private var showRouteDetail = false

    // New install → full tour; updater → only steps added since they last
    // finished; up-to-date → nothing.
    private var tourSlice: [TourStep] {
        stepsToShow(
            tourSteps,
            effectiveSeen: effectiveSeenVersion(hasSeen: hasSeenOnboarding, seenVersion: seenOnboardingVersion),
            current: currentTourVersion)
    }

    private func markTourSeen() {
        hasSeenOnboarding = true
        seenOnboardingVersion = currentTourVersion
    }

    var body: some View {
        ZStack {
            Color(uiColor: .systemBackground).ignoresSafeArea()

            switch viewModel.appState {
            case 2:
                PhoneFocusedTrackingView(viewModel: viewModel)
            case 3:
                VStack(spacing: 12) {
                    Spacer()
                    Image(systemName: "train.side.front.car")
                        .font(.system(size: 52))
                        .foregroundStyle(.secondary)
                    Text("Paused")
                        .font(.title2.weight(.semibold))
                        .foregroundStyle(.primary)
                    Text("Updates paused to save battery")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 32)
                    Button {
                        viewModel.resumeToStationView()
                    } label: {
                        Label("Resume", systemImage: "arrow.clockwise")
                            .font(.subheadline.weight(.medium))
                    }
                    .buttonStyle(.borderedProminent)
                    .padding(.top, 4)
                    Spacer()
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            default:
                PhoneStationView(viewModel: viewModel)
            }
        }
        // Queued shared route rides above the station/inactive screens and
        // hides during tracking.
        .safeAreaInset(edge: .top) {
            if let route = pendingRouteStore.pending, viewModel.appState != 2 {
                PendingRouteChip(
                    route: route,
                    notifyTs: viewModel.reminderNotifyTs,
                    onTap: { showRouteDetail = true },
                    onDismiss: { viewModel.dismissPendingRoute() }
                )
            }
        }
        .sheet(isPresented: $showRouteDetail) {
            RouteDetailView(viewModel: viewModel)
                .onAppear {
                    if let route = viewModel.pendingRouteStore.pending {
                        viewModel.loadRoutePlatforms(route)
                    }
                }
        }
        .onAppear {
            viewModel.onAppear()
            viewModel.consumeSharePayload()
            Task { await viewModel.refreshPendingRoute() }
        }
        .onDisappear { viewModel.onDisappear() }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active {
                viewModel.onAppear()
                // openURL from the share extension is flaky, pick up a fresh
                // handoff even when the deep link never fired.
                viewModel.consumeSharePayload()
                Task { await viewModel.refreshPendingRoute() }
            } else {
                viewModel.onDisappear()
            }
        }
        .onOpenURL { url in
            // Garmin Connect returns the device-selection result through our custom scheme.
            if viewModel.watchService.garminService.handleOpenURL(url) { return }
            viewModel.handleDeepLink(url)
        }
        .preferredColorScheme(AppAppearance(rawValue: appAppearance)?.colorScheme)
        .alert("Enjoying TrainTime?", isPresented: $viewModel.showReviewPrompt) {
            // Deliberately the write-review page, not requestReview(): after an
            // explicit yes the system sheet may silently no-op (rate limited).
            Button("Yes, rate it") { openURL(PhoneViewModel.writeReviewURL) }
            Button("Not now") { viewModel.snoozeReview() }
            Button("Don't ask again", role: .destructive) { viewModel.optOutReview() }
        } message: {
            Text("A quick rating helps other commuters find the app.")
        }
        .onChange(of: viewModel.openWriteReviewTick) { _, _ in
            openURL(PhoneViewModel.writeReviewURL)
        }
        // Shared-route intake feedback + replace confirmation + resume prompt.
        .alert("Replace queued route?", isPresented: Binding(
            get: { viewModel.shareReplaceOffer != nil },
            set: { if !$0 { viewModel.dismissReplaceSharedRoute() } }
        )) {
            Button("Replace") { viewModel.confirmReplaceSharedRoute() }
            Button("Keep existing", role: .cancel) { viewModel.dismissReplaceSharedRoute() }
        } message: {
            Text("You already have a route saved. Replace it with the trip to \(viewModel.shareReplaceOffer?.route.finalDestinationName ?? "")?")
        }
        .alert("Resume route to \(pendingRouteStore.pending?.finalDestination ?? "")?", isPresented: Binding(
            get: { viewModel.resumeOffer != nil },
            set: { if !$0 { viewModel.deferResume() } }
        )) {
            Button("Track") { viewModel.resumePendingRoute() }
            Button("Later", role: .cancel) { viewModel.deferResume() }
        } message: {
            if let dep = viewModel.resumeOffer {
                Text("\(dep.lineNumber) to \(dep.destination) departs in \(max(0, dep.minutesUntil)) min"
                    + (dep.platform.isEmpty ? "" : " from platform \(dep.platform)"))
            }
        }
        .overlay(alignment: .bottom) {
            if let status = viewModel.shareStatus {
                Text(status)
                    .font(.footnote)
                    .padding(.horizontal, 16).padding(.vertical, 10)
                    .background(Capsule().fill(Color(uiColor: .secondarySystemBackground)).shadow(radius: 4))
                    .padding(.bottom, 32)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
                    .task {
                        try? await Task.sleep(nanoseconds: 4_000_000_000)
                        withAnimation { viewModel.shareStatus = nil }
                    }
            }
        }
        .fullScreenCover(isPresented: Binding(
            get: { !tourSlice.isEmpty },
            set: { presented in if !presented { markTourSeen() } }
        )) {
            OnboardingTour(steps: tourSlice, onFinish: {
                markTourSeen()
                withAnimation { showTourHint = true }
                DispatchQueue.main.asyncAfter(deadline: .now() + 3) {
                    withAnimation { showTourHint = false }
                }
            })
        }
        .overlay(alignment: .bottom) {
            if showTourHint {
                Text("Replay the tour anytime in Settings.")
                    .font(.footnote)
                    .padding(.horizontal, 16).padding(.vertical, 10)
                    .background(Capsule().fill(Color(uiColor: .secondarySystemBackground)).shadow(radius: 4))
                    .padding(.bottom, 32)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
    }
}

enum AppAppearance: String, CaseIterable, Identifiable {
    case system, light, dark

    var id: String { rawValue }

    var label: String {
        switch self {
        case .system: return "System"
        case .light: return "Light"
        case .dark: return "Dark"
        }
    }

    var symbol: String {
        switch self {
        case .system: return "circle.lefthalf.filled"
        case .light: return "sun.max"
        case .dark: return "moon"
        }
    }

    var colorScheme: ColorScheme? {
        switch self {
        case .system: return nil
        case .light: return .light
        case .dark: return .dark
        }
    }
}
