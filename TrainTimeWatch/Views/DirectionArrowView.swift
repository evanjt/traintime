import SwiftUI

struct DirectionArrowView: View {
    let degrees: Double? // relative bearing in degrees

    var body: some View {
        if let deg = degrees {
            Image(systemName: "location.north.fill")
                .font(.system(size: 16))
                .foregroundColor(.white)
                .rotationEffect(.degrees(deg))
        }
    }
}
