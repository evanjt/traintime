import SwiftUI

struct ModeIndicatorView: View {
    let availableModes: [TransportMode]
    let currentMode: TransportMode
    let onSelect: (TransportMode) -> Void

    var body: some View {
        if availableModes.count > 1 {
            HStack(spacing: 12) {
                ForEach(availableModes) { mode in
                    Button(action: { onSelect(mode) }) {
                        Image(systemName: mode.sfSymbol)
                            .font(.system(size: 14))
                            .foregroundStyle(mode == currentMode ? .white : .secondary)
                            .frame(width: 28, height: 28)
                            .background(
                                mode == currentMode
                                    ? Circle().fill(.white.opacity(0.15))
                                    : Circle().fill(.clear)
                            )
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }
}
