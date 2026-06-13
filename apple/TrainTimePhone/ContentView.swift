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
                VStack(spacing: 16) {
                    Spacer()
                    Image(systemName: "tram.fill")
                        .font(.system(size: 56))
                        .foregroundStyle(.secondary)
                    Text("Inactive")
                        .font(.title2.weight(.semibold))
                        .foregroundStyle(.secondary)
                    Button {
                        viewModel.resumeFromInactive()
                    } label: {
                        Label("Resume", systemImage: "arrow.clockwise")
                            .font(.subheadline.weight(.medium))
                    }
                    .buttonStyle(.bordered)
                    .tint(.blue)
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
