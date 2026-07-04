import SwiftUI

/// Watch link indicator shared by the station header and the tracking screen. Colour tracks
/// the three-state liveness (green = open and synced, amber = connected but app closed, grey =
/// paired but off/away). A spinner overlays during a Garmin open attempt. Centralises the
/// colour mapping so both call sites agree, matching the Android header.
struct WatchLivenessIndicator: View {
    let liveness: WatchLiveness
    var isChecking: Bool = false
    var isAppleWatch: Bool = false
    var size: CGFloat = 18

    static let green = Color(red: 0.20, green: 0.78, blue: 0.35) // 0xFF34C759
    static let amber = Color(red: 1.0, green: 0.70, blue: 0.0)   // 0xFFFFB300
    static let grey = Color(red: 0.56, green: 0.56, blue: 0.58)  // 0xFF8E8E93

    var body: some View {
        ZStack {
            Image(systemName: isAppleWatch ? "applewatch" : "watch.analog")
                .font(.system(size: size))
                .foregroundStyle(tint)
            if isChecking {
                ProgressView()
                    .controlSize(.mini)
            }
        }
        .frame(width: size + 6, height: size + 6)
    }

    private var tint: Color {
        switch liveness {
        case .green: return Self.green
        case .amber: return Self.amber
        case .grey: return Self.grey
        case .hidden: return .clear
        }
    }
}
