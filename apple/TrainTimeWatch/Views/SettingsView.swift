import SwiftUI

struct SettingsView: View {
    @ObservedObject var viewModel: TrainTimeViewModel
    @Environment(\.dismiss) var dismiss

    var body: some View {
        List {
            Section("Default Mode") {
                ForEach(TransportMode.allCases) { mode in
                    Button {
                        viewModel.setDefaultMode(mode)
                    } label: {
                        HStack {
                            Image(systemName: mode.sfSymbol)
                            Text(mode.label)
                            Spacer()
                            if viewModel.defaultMode == mode {
                                Image(systemName: "checkmark")
                                    .foregroundStyle(.blue)
                            }
                        }
                    }
                    .buttonStyle(.plain)
                }
            }

            if !viewModel.favouritesStore.favourites.isEmpty {
                Section("Favourites (\(viewModel.favouritesStore.favourites.count))") {
                    ForEach(viewModel.favouritesStore.favourites) { fav in
                        Text(fav.displayString)
                            .font(.caption)
                            .foregroundStyle(.primary)
                    }
                    .onDelete { offsets in
                        let toRemove = offsets.map { viewModel.favouritesStore.favourites[$0] }
                        toRemove.forEach { viewModel.favouritesStore.remove($0) }
                    }
                }
            }

            Section {
                HStack {
                    Text("Version")
                    Spacer()
                    Text(Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "?")
                        .foregroundStyle(.secondary)
                }
            }
        }
        .navigationTitle("Settings")
    }
}
