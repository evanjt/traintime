import SwiftUI

struct ContentView: View {
    @StateObject private var viewModel = PhoneViewModel()
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.openURL) private var openURL
    @AppStorage("hasSeenOnboarding") private var hasSeenOnboarding = false
    @AppStorage("appAppearance") private var appAppearance = AppAppearance.system.rawValue
    @State private var showTourHint = false

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
                        viewModel.resumeFromInactive()
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
        .onAppear { viewModel.onAppear() }
        .onDisappear { viewModel.onDisappear() }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active {
                viewModel.onAppear()
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
        .fullScreenCover(isPresented: Binding(
            get: { !hasSeenOnboarding },
            set: { presented in if !presented { hasSeenOnboarding = true } }
        )) {
            OnboardingTour(onFinish: {
                hasSeenOnboarding = true
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
