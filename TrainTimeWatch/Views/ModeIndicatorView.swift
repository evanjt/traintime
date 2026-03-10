import SwiftUI

struct ModeIndicatorView: View {
    let availableModes: [TransportMode]
    let currentMode: TransportMode
    let onSelect: (TransportMode) -> Void

    var body: some View {
        HStack(spacing: 8) {
            ForEach(availableModes) { mode in
                Button(action: { onSelect(mode) }) {
                    Image(systemName: mode.sfSymbol)
                        .font(.system(size: 12))
                        .foregroundColor(mode == currentMode ? .white : .gray)
                        .padding(4)
                        .background(
                            Circle()
                                .stroke(mode == currentMode ? Color.white : Color.clear, lineWidth: 1)
                        )
                }
                .buttonStyle(.plain)
            }
        }
    }
}
