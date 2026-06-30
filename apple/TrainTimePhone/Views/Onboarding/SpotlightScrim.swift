import SwiftUI

// Lightly dims everything except the taught element: a translucent scrim with a rounded
// transparent cut-out punched over the target's bounds. The feature shows through fully bright
// (the tour must never obscure what it explains). destinationOut needs an owned compositing
// group to subtract, the SwiftUI peer of Android's BlendMode.Clear + offscreen layer.
struct SpotlightScrim: View {
    let hole: CGRect?

    var body: some View {
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
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}
