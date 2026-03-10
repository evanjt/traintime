import SwiftUI

struct ContentView: View {
    @StateObject private var viewModel = TrainTimeViewModel()

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
        }
        .onAppear { viewModel.onAppear() }
        .onDisappear { viewModel.onDisappear() }
    }
}
