import SwiftUI

struct ContentView: View {
    @StateObject private var viewModel = TrainTimeViewModel()
    @Environment(\.scenePhase) private var scenePhase
    @State private var showRateHandoffHint = false

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
                            viewModel.resumeFromInactive()
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
