import SwiftUI

struct PhoneModePickerView: View {
    let availableModes: [TransportMode]
    let currentMode: TransportMode
    let onSelect: (TransportMode) -> Void

    var body: some View {
        HStack(spacing: 4) {
            ForEach(TransportMode.allCases) { mode in
                let isAvailable = availableModes.contains(mode)
                Button(action: { onSelect(mode) }) {
                    Image(systemName: mode.sfSymbol)
                        .font(.system(size: 16))
                        .foregroundStyle(
                            mode == currentMode && isAvailable ? .white :
                            isAvailable ? .secondary :
                            .primary.opacity(0.15)
                        )
                        .frame(width: 36, height: 36)
                        .background(
                            mode == currentMode && isAvailable
                                ? Circle().fill(.blue.opacity(0.3))
                                : Circle().fill(.clear)
                        )
                }
                .buttonStyle(.plain)
                .allowsHitTesting(isAvailable)
            }
        }
    }
}
