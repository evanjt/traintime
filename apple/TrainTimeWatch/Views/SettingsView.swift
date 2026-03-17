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
