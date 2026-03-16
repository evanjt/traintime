import SwiftUI

struct ContentView: View {
    @StateObject private var viewModel = PhoneViewModel()

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

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
                    Text("Tap to resume")
                        .font(.subheadline)
                        .foregroundStyle(.tertiary)
                    Spacer()
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .contentShape(Rectangle())
                .onTapGesture {
                    viewModel.resumeFromInactive()
                }
            default:
                PhoneStationView(viewModel: viewModel)
            }
        }
        .preferredColorScheme(.dark)
        .onAppear { viewModel.onAppear() }
        .onDisappear { viewModel.onDisappear() }
        .onOpenURL { url in
            viewModel.handleDeepLink(url)
        }
    }
}
