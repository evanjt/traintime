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
                case 3:
                    VStack(spacing: 12) {
                        Spacer()
                        Text("Inactive")
                            .font(.system(.title3, weight: .semibold))
                            .foregroundStyle(.secondary)
                        Text("Tap to resume")
                            .font(.footnote)
                            .foregroundStyle(.tertiary)
                        Spacer()
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .contentShape(Rectangle())
                    .onTapGesture {
                        viewModel.resumeFromInactive()
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
