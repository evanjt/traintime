import SwiftUI
import StoreKit

struct ContentView: View {
    @StateObject private var viewModel = PhoneViewModel()
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.requestReview) private var requestReview
    @AppStorage("hasSeenOnboarding") private var hasSeenOnboarding = false
    @AppStorage("appAppearance") private var appAppearance = AppAppearance.system.rawValue

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
            viewModel.handleDeepLink(url)
        }
        .preferredColorScheme(AppAppearance(rawValue: appAppearance)?.colorScheme)
        .onChange(of: viewModel.reviewRequestTick) { _, _ in
            requestReview()
        }
        .fullScreenCover(isPresented: Binding(
            get: { !hasSeenOnboarding },
            set: { presented in if !presented { hasSeenOnboarding = true } }
        )) {
            OnboardingView(onFinish: { hasSeenOnboarding = true })
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

private struct OnboardingPage: Identifiable {
    let id = UUID()
    let symbol: String
    let title: String
    let detail: String
}

struct OnboardingView: View {
    let onFinish: () -> Void
    @State private var index = 0

    private let pages: [OnboardingPage] = [
        OnboardingPage(
            symbol: "location.fill",
            title: "Departures around you",
            detail: "We use your location to show the nearest stations and their live departures. Tap the mode chips to switch between train, bus and tram."),
        OnboardingPage(
            symbol: "timer",
            title: "Track a train",
            detail: "Tap any departure to track it. You get a live countdown, a haptic nudge when it is time to leave, and the walking distance to the platform."),
        OnboardingPage(
            symbol: "mappin.and.ellipse",
            title: "Pin your station",
            detail: "Press and hold a station to pin it. Pinned stations lead the list, so if you usually catch the train at Bern Bhf it shows first even when you are standing closer to a smaller stop."),
        OnboardingPage(
            symbol: "star.fill",
            title: "Star your favourites",
            detail: "Tap the star on a line to save it. Favourites sit at the top of the list. Add the home screen widget to see your next departures at a glance.")
    ]

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Spacer()
                Button("Skip", action: onFinish)
                    .padding()
            }
            TabView(selection: $index) {
                ForEach(Array(pages.enumerated()), id: \.element.id) { i, page in
                    VStack(spacing: 20) {
                        Spacer()
                        Image(systemName: page.symbol)
                            .font(.system(size: 64))
                            .foregroundStyle(.tint)
                        Text(page.title)
                            .font(.title.weight(.bold))
                            .multilineTextAlignment(.center)
                        Text(page.detail)
                            .font(.body)
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.center)
                            .padding(.horizontal, 32)
                        Spacer()
                    }
                    .tag(i)
                }
            }
            .tabViewStyle(.page)
            .indexViewStyle(.page(backgroundDisplayMode: .always))
            Button {
                if index < pages.count - 1 {
                    withAnimation { index += 1 }
                } else {
                    onFinish()
                }
            } label: {
                Text(index < pages.count - 1 ? "Next" : "Get Started")
                    .font(.headline)
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .padding()
        }
    }
}
