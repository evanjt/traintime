import SwiftUI

struct ModeIndicatorView: View {
    let availableModes: [TransportMode]
    let currentMode: TransportMode
    let onSelect: (TransportMode) -> Void

    var body: some View {
        HStack(spacing: 12) {
            ForEach(TransportMode.allCases) { mode in
                let isAvailable = availableModes.contains(mode)
                Button(action: { onSelect(mode) }) {
                    Image(systemName: mode.sfSymbol)
                        .font(.system(size: 14))
                        .foregroundStyle(
                            mode == currentMode && isAvailable ? .white :
                            isAvailable ? .secondary :
                            .white.opacity(0.15)
                        )
                        .frame(width: 28, height: 28)
                        .background(
                            mode == currentMode && isAvailable
                                ? Circle().fill(.white.opacity(0.15))
                                : Circle().fill(.clear)
                        )
                }
                .buttonStyle(.plain)
                .allowsHitTesting(isAvailable)
            }
        }
    }
}
