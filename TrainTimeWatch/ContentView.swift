import SwiftUI

struct ContentView: View {
    @StateObject private var viewModel = TrainTimeViewModel()
    @State private var crownAccumulator = 0.0

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
                default:
                    StationView(viewModel: viewModel)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Color.black)
            .focusable()
            .digitalCrownRotation(
                $crownAccumulator,
                from: -100, through: 100,
                sensitivity: .low,
                isContinuous: true,
                isHapticFeedbackEnabled: true
            )
            .onChange(of: crownAccumulator) { _, newValue in
                handleCrown(newValue)
            }
        }
        .onAppear { viewModel.onAppear() }
        .onDisappear { viewModel.onDisappear() }
    }

    private func handleCrown(_ value: Double) {
        guard viewModel.appState == 0, abs(value) > 1.5 else { return }

        if !viewModel.departures.isEmpty {
            viewModel.updateCrownHighlight(value)
        } else {
            if value > 0 {
                viewModel.nextStation()
            } else {
                viewModel.previousStation()
            }
        }
        crownAccumulator = 0
    }
}
