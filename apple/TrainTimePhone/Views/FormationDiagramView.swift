import SwiftUI

struct FormationDiagramView: View {
    let formation: Formation

    private let carriageWidth: CGFloat = 56
    private let carriageHeight: CGFloat = 26
    private let gap: CGFloat = 2

    var body: some View {
        VStack(spacing: 2) {
            ScrollView(.horizontal, showsIndicators: false) {
                VStack(alignment: .leading, spacing: 3) {
                    // Train
                    HStack(spacing: 0) {
                        // Locomotive
                        LocoView(height: carriageHeight)

                        // Carriages
                        ForEach(Array(formation.wagons.enumerated()), id: \.offset) { i, wagon in
                            if i > 0 {
                                Rectangle()
                                    .fill(Color(white: 0.12))
                                    .frame(width: gap, height: carriageHeight * 0.35)
                            }
                            CarriageCell(wagon: wagon, width: carriageWidth, height: carriageHeight)
                        }
                    }

                    // Sector labels
                    if !formation.sectors.isEmpty {
                        HStack(spacing: 0) {
                            Color.clear.frame(width: 30) // loco offset
                            ForEach(Array(formation.wagons.enumerated()), id: \.offset) { i, wagon in
                                let w = carriageWidth + (i > 0 ? gap : 0)
                                let isFirst = i == 0 || formation.wagons[i - 1].sector != wagon.sector
                                Text(isFirst && !wagon.sector.isEmpty ? wagon.sector : "")
                                    .font(.system(size: 11, weight: .semibold))
                                    .foregroundColor(.secondary)
                                    .frame(width: w)
                            }
                        }
                    }
                }
                .padding(.horizontal, 8)
            }
        }
    }
}

// MARK: - Locomotive

private struct LocoView: View {
    let height: CGFloat
    private let width: CGFloat = 30

    var body: some View {
        ZStack {
            // Body
            LocoShape()
                .fill(Color(white: 0.18))
                .frame(width: width, height: height)

            // Outline
            LocoShape()
                .stroke(Color(white: 0.30), lineWidth: 0.5)
                .frame(width: width, height: height)

            // Windshield
            RoundedRectangle(cornerRadius: 2)
                .fill(Color.white.opacity(0.08))
                .frame(width: 6, height: height * 0.45)
                .offset(x: -width / 2 + 10)

            // Direction chevron
            Image(systemName: "chevron.left")
                .font(.system(size: 7, weight: .semibold))
                .foregroundColor(Color(white: 0.45))
                .offset(x: -width / 2 + 5)
        }
    }
}

private struct LocoShape: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        let r: CGFloat = 3
        let noseR: CGFloat = 8

        // Start top-right
        path.move(to: CGPoint(x: rect.maxX, y: rect.minY + r))
        path.addQuadCurve(to: CGPoint(x: rect.maxX - r, y: rect.minY),
                          control: CGPoint(x: rect.maxX, y: rect.minY))

        // Top edge to nose taper
        path.addLine(to: CGPoint(x: rect.minX + noseR, y: rect.minY))

        // Smooth nose curve (top to tip to bottom)
        path.addCurve(
            to: CGPoint(x: rect.minX + noseR, y: rect.maxY),
            control1: CGPoint(x: rect.minX - 2, y: rect.minY + 2),
            control2: CGPoint(x: rect.minX - 2, y: rect.maxY - 2)
        )

        // Bottom edge
        path.addLine(to: CGPoint(x: rect.maxX - r, y: rect.maxY))
        path.addQuadCurve(to: CGPoint(x: rect.maxX, y: rect.maxY - r),
                          control: CGPoint(x: rect.maxX, y: rect.maxY))

        path.closeSubpath()
        return path
    }
}

// MARK: - Carriage

private struct CarriageCell: View {
    let wagon: FormationWagon
    let width: CGFloat
    let height: CGFloat

    var body: some View {
        ZStack {
            // Body
            RoundedRectangle(cornerRadius: 3)
                .fill(Color(white: 0.18))
                .frame(width: width, height: height)
                .opacity(wagon.closed ? 0.4 : 1.0)

            // Outline
            RoundedRectangle(cornerRadius: 3)
                .stroke(Color(white: 0.30), lineWidth: 0.5)
                .frame(width: width, height: height)

            // 1st class accent — yellow stripe along top
            if wagon.wagonClass == 1 {
                VStack {
                    RoundedRectangle(cornerRadius: 1)
                        .fill(Color(red: 0.92, green: 0.72, blue: 0.0))
                        .frame(width: width - 4, height: 2.5)
                        .offset(y: 1.5)
                    Spacer()
                }
                .frame(height: height)
                .clipShape(RoundedRectangle(cornerRadius: 3))
            }

            // Subtle window band
            RoundedRectangle(cornerRadius: 1)
                .fill(Color.white.opacity(0.06))
                .frame(width: width - 6, height: 6)
                .offset(y: -3)

            // Car number + class
            HStack(spacing: 3) {
                Text("\(wagon.number)")
                    .font(.system(size: 11, weight: .semibold, design: .rounded))
                    .foregroundColor(Color(white: 0.65))
                if wagon.wagonClass == 1 {
                    Text("1")
                        .font(.system(size: 8, weight: .bold, design: .rounded))
                        .foregroundColor(Color(red: 0.92, green: 0.72, blue: 0.0).opacity(0.9))
                }
            }
            .offset(y: 2)

            // Feature icon
            if let feature = wagon.features.first {
                Image(systemName: featureIcon(feature))
                    .font(.system(size: 7))
                    .foregroundColor(Color(white: 0.45))
                    .offset(x: width / 2 - 8, y: height / 2 - 6)
            }

            // Closed
            if wagon.closed {
                Rectangle()
                    .fill(Color.white.opacity(0.3))
                    .frame(width: width * 0.7, height: 1)
                    .rotationEffect(.degrees(-8))
            }
        }
    }

    private func featureIcon(_ feature: String) -> String {
        switch feature {
        case "wheelchair": return "figure.roll"
        case "restaurant": return "fork.knife"
        case "family": return "figure.2.and.child.holdinghands"
        case "business": return "briefcase"
        case "low_floor": return "arrow.down.to.line"
        default: return "questionmark"
        }
    }
}
