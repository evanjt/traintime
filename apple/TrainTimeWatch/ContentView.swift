import SwiftUI

struct ContentView: View {
    @StateObject private var viewModel = TrainTimeViewModel()
    @ObservedObject private var pendingRouteStore = PendingRouteStore.shared
    @Environment(\.scenePhase) private var scenePhase
    @State private var showRateHandoffHint = false
    @State private var showRouteDetail = false

    private static let chipTimeFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm"
        formatter.timeZone = TimeZone(identifier: "Europe/Zurich")
        return formatter
    }()

    var body: some View {
        NavigationStack {
            Group {
                switch viewModel.appState {
                case 2:
                    FocusedTrackingView(viewModel: viewModel)
                        .toolbar {
                            ToolbarItem(placement: .cancellationAction) {
                                Button("Back") {
                                    viewModel.exitToStationView()
                                }
                            }
                        }
                case 3:
                    VStack(spacing: 12) {
                        Spacer()
                        Text("Inactive")
                            .font(.system(.title3, weight: .semibold))
                            .foregroundStyle(.secondary)
                        Button {
                            viewModel.resumeToStationView()
                        } label: {
                            Label("Resume", systemImage: "arrow.clockwise")
                                .font(.caption.weight(.medium))
                        }
                        .buttonStyle(.bordered)
                        .tint(.blue)
                        Spacer()
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                default:
                    StationView(viewModel: viewModel)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Color.black)
            // Queued shared route (phone-owned, read-only mirror). Tap starts
            // tracking once the departure is close enough to be on the board.
            .safeAreaInset(edge: .top) {
                if let route = pendingRouteStore.pending, let leg = route.currentLeg,
                   viewModel.appState != 2 {
                    Button {
                        showRouteDetail = true
                    } label: {
                        Text("▶ \(route.finalDestination) · \(Self.chipTimeFormatter.string(from: Date(timeIntervalSince1970: TimeInterval(leg.depTs))))")
                            .font(.caption2)
                            .lineLimit(1)
                    }
                    .buttonStyle(.bordered)
                    .tint(Color(red: 0.6, green: 0.53, blue: 0))
                }
            }
        }
        .sheet(isPresented: $showRouteDetail) {
            WatchRouteView(viewModel: viewModel)
                .onAppear {
                    if let route = PendingRouteStore.shared.pending {
                        viewModel.loadRoutePlatforms(route)
                    }
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
        .alert("Enjoying TrainTime?", isPresented: $viewModel.showReviewPrompt) {
            Button("Yes, rate it") {
                viewModel.rateOnPhone()
                withAnimation { showRateHandoffHint = true }
                DispatchQueue.main.asyncAfter(deadline: .now() + 3) {
                    withAnimation { showRateHandoffHint = false }
                }
            }
            Button("Not now") { viewModel.snoozeReview() }
            Button("Don't ask again", role: .destructive) { viewModel.optOutReview() }
        } message: {
            Text("A quick rating helps other commuters find the app.")
        }
        .overlay(alignment: .bottom) {
            if showRateHandoffHint {
                Text("The review page will open on your iPhone.")
                    .font(.caption2)
                    .multilineTextAlignment(.center)
                    .padding(8)
                    .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 8))
                    .transition(.opacity)
            }
        }
    }
}
