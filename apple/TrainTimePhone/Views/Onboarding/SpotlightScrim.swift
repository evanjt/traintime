import SwiftUI

// Lightly dims everything except the taught element: a translucent scrim with a rounded
// transparent cut-out punched over the target's bounds, ringed with a dashed accent border so
// the spotlighted feature reads clearly against the dim (especially in dark mode). destinationOut
// needs an owned compositing group to subtract, the SwiftUI peer of Android's BlendMode.Clear.
struct SpotlightScrim: View {
    let hole: CGRect?
    var accent: Color = .accentColor

    var body: some View {
        ZStack {
            ZStack {
                Color.black.opacity(0.32)
                if let hole {
                    RoundedRectangle(cornerRadius: 14)
                        .frame(width: hole.width + 12, height: hole.height + 12)
                        .position(x: hole.midX, y: hole.midY)
                        .blendMode(.destinationOut)
                }
            }
            .compositingGroup()

            if let hole {
                RoundedRectangle(cornerRadius: 14)
                    .stroke(accent, style: StrokeStyle(lineWidth: 2, dash: [11, 7]))
                    .frame(width: hole.width + 12, height: hole.height + 12)
                    .position(x: hole.midX, y: hole.midY)
            }
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}
