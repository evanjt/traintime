import SwiftUI

struct PhoneModePickerView: View {
    let availableModes: [TransportMode]
    let currentMode: TransportMode
    let onSelect: (TransportMode) -> Void

    var body: some View {
        HStack(spacing: 0) {
            ForEach(TransportMode.allCases) { mode in
                let isAvailable = availableModes.contains(mode)
                let isSelected = mode == currentMode && isAvailable
                Button(action: { onSelect(mode) }) {
                    VStack(spacing: 4) {
                        Image(systemName: mode.sfSymbol)
                            .font(.system(size: 18))
                        Text(mode.label)
                            .font(.system(size: 10, weight: .medium))
                    }
                    .foregroundStyle(
                        isSelected ? Color.accentColor :
                        isAvailable ? Color.secondary :
                        Color.primary.opacity(0.15)
                    )
                    .frame(maxWidth: .infinity)
                    .frame(height: 52)
                    .background(
                        isSelected
                            ? RoundedRectangle(cornerRadius: 10).fill(Color.accentColor.opacity(0.15))
                            : RoundedRectangle(cornerRadius: 10).fill(.clear)
                    )
                }
                .buttonStyle(.plain)
                .allowsHitTesting(isAvailable)
            }
        }
    }
}
