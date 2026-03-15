import SwiftUI

struct ContentView: View {
    @StateObject private var viewModel = PhoneViewModel()

    var body: some View {
        NavigationStack {
            Group {
                switch viewModel.appState {
                case 2:
                    PhoneFocusedTrackingView(viewModel: viewModel)
                        .navigationBarBackButtonHidden(true)
                        .toolbar {
                            ToolbarItem(placement: .navigationBarLeading) {
                                Button {
                                    viewModel.exitToStationView()
                                } label: {
                                    HStack(spacing: 4) {
                                        Image(systemName: "chevron.left")
                                        Text("Back")
                                    }
                                }
                            }
                        }
                case 3:
                    VStack(spacing: 16) {
                        Spacer()
                        Image(systemName: "checkmark.circle")
                            .font(.system(size: 48))
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
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Color(.systemBackground))
        }
        .onAppear { viewModel.onAppear() }
        .onDisappear { viewModel.onDisappear() }
        .onOpenURL { url in
            viewModel.handleDeepLink(url)
        }
    }
}
