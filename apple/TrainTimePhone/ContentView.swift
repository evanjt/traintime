import SwiftUI

struct ContentView: View {
    @StateObject private var viewModel = PhoneViewModel()
    @Environment(\.scenePhase) private var scenePhase

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
    }
}
