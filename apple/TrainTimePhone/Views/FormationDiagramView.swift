import SwiftUI

// Car positions for the phone diagram: cars shrink to fit the width with no floor, a wider gap
// marks a car end with no passage, and each run of joined cars is one unit.
struct FormationLayout {
    static let gap: CGFloat = 2
    static let breakGap: CGFloat = 8
    static let maxCarWidth: CGFloat = 56
    static let fullNoseWidth: CGFloat = 32
    static let compactNoseWidth: CGFloat = 20
    static let lanePriority = ["restaurant", "wheelchair", "family", "bike", "business"]

    let noseWidth: CGFloat
    let carWidth: CGFloat
    let carX: [CGFloat]
    let breaks: [CGFloat]
    let units: [Range<Int>]

    init(wagons: [FormationWagon], width: CGFloat) {
        let n = wagons.count
        let breakAfter = wagons.indices.map { $0 < n - 1 && wagons[$0].noPassageAfter }
        let gaps = breakAfter.prefix(max(0, n - 1)).map { $0 ? Self.breakGap : Self.gap }
        let fixed = Self.gap + gaps.reduce(0, +)
        func fit(_ nose: CGFloat) -> CGFloat {
            guard n > 0 else { return Self.maxCarWidth }
            return max(0, min(Self.maxCarWidth, (width - nose - fixed) / CGFloat(n)))
        }
        var nose = Self.fullNoseWidth
        var car = fit(nose)
        if car < 22 {
            nose = Self.compactNoseWidth
            car = fit(nose)
        }

        var xs: [CGFloat] = []
        var bs: [CGFloat] = []
        var us: [Range<Int>] = []
        var x = nose + Self.gap
        var start = 0
        for i in 0..<n {
            xs.append(x)
            x += car
            guard i < n - 1 else { break }
            if breakAfter[i] {
                bs.append(x + gaps[i] / 2)
                us.append(start..<(i + 1))
                start = i + 1
            }
            x += gaps[i]
        }
        if n > 0 { us.append(start..<n) }

        noseWidth = nose
        carWidth = car
        carX = xs
        breaks = bs
        units = us
    }

    // One icon per car. Low floor, pram space and anything unknown draw nothing.
    static func laneFeature(_ wagon: FormationWagon) -> String? {
        guard !wagon.closed else { return nil }
        return lanePriority.first { wagon.features.contains($0) }
    }
}

struct FormationDiagramView: View {
    let formation: Formation

    private let carriageHeight: CGFloat = 30
    private let laneHeight: CGFloat = 14
    private let barOverhang: CGFloat = 3
    private let labelHeight: CGFloat = 14
    private let rowSpacing: CGFloat = 2

    private var trainTop: CGFloat { laneHeight + rowSpacing }
    private var carTop: CGFloat { trainTop + barOverhang }
    private var labelTop: CGFloat { trainTop + carriageHeight + barOverhang * 2 + rowSpacing }
    private var totalHeight: CGFloat {
        formation.sectors.isEmpty ? labelTop - rowSpacing : labelTop + labelHeight
    }

    private struct SectorGroup {
        let sector: String
        let first: Int
        let last: Int
    }

    private var sectorGroups: [SectorGroup] {
        var groups: [SectorGroup] = []
        for (i, w) in formation.wagons.enumerated() {
            if let g = groups.last, g.sector == w.sector {
                groups[groups.count - 1] = SectorGroup(sector: g.sector, first: g.first, last: i)
            } else {
                groups.append(SectorGroup(sector: w.sector, first: i, last: i))
            }
        }
        return groups
    }

    var body: some View {
        GeometryReader { geo in
            let width = max(0, geo.size.width - 16)
            let layout = FormationLayout(wagons: formation.wagons, width: width)
            let carW = layout.carWidth
            let carMidY = carTop + carriageHeight / 2

            ZStack(alignment: .topLeading) {
                LocoView(width: layout.noseWidth, height: carriageHeight)
                    .position(x: layout.noseWidth / 2, y: carMidY)

                ForEach(Array(layout.units.enumerated()), id: \.offset) { _, unit in
                    let x0 = layout.carX[unit.lowerBound] - 1
                    let x1 = layout.carX[unit.upperBound - 1] + carW + 1
                    RoundedRectangle(cornerRadius: 5)
                        .stroke(Color(.systemGray3), lineWidth: 0.5)
                        .frame(width: x1 - x0, height: carriageHeight + 4)
                        .position(x: (x0 + x1) / 2, y: carMidY)
                    ForEach(Array(unit.dropLast()), id: \.self) { i in
                        Rectangle()
                            .fill(Color(.systemGray6))
                            .frame(width: FormationLayout.gap, height: carriageHeight * 0.35)
                            .position(x: layout.carX[i] + carW + FormationLayout.gap / 2, y: carMidY)
                    }
                }

                ForEach(Array(formation.wagons.enumerated()), id: \.offset) { i, wagon in
                    let midX = layout.carX[i] + carW / 2
                    CarriageCell(wagon: wagon, width: carW, height: carriageHeight)
                        .position(x: midX, y: carMidY)
                    if let feature = FormationLayout.laneFeature(wagon) {
                        let size = max(4, min(12, carW - 4))
                        Image(systemName: Self.featureIcon(feature))
                            .resizable()
                            .scaledToFit()
                            .frame(width: size, height: size)
                            .foregroundStyle(feature == "bike" ? Color(.systemGray) : Color.primary)
                            .accessibilityLabel(Text(Self.featureLabel(feature)))
                            .position(x: midX, y: laneHeight / 2)
                    }
                }

                ForEach(Array(layout.breaks.enumerated()), id: \.offset) { _, x in
                    Rectangle()
                        .fill(Color(.systemRed))
                        .frame(width: 3, height: carriageHeight + barOverhang * 2)
                        .accessibilityElement()
                        .accessibilityLabel(Text("No passage between these cars"))
                        .position(x: x, y: carMidY)
                }

                if !formation.sectors.isEmpty {
                    let labelMidY = labelTop + labelHeight / 2
                    Image(systemName: "arrow.left")
                        .font(.system(size: 9, weight: .semibold))
                        .foregroundColor(.primary)
                        .position(x: layout.noseWidth / 2, y: labelMidY)

                    ForEach(Array(sectorGroups.enumerated()), id: \.offset) { _, group in
                        let x0 = layout.carX[group.first]
                        let x1 = layout.carX[group.last] + carW
                        ZStack {
                            Rectangle()
                                .fill(Color(.systemGray3))
                                .frame(width: max(0, x1 - x0 - 4), height: 0.5)
                            Text(group.sector)
                                .font(.system(size: 11, weight: .semibold))
                                .foregroundColor(.primary)
                                .padding(.horizontal, 3)
                                .background(Color(uiColor: .systemBackground))
                        }
                        .position(x: (x0 + x1) / 2, y: labelMidY)
                    }
                }
            }
            .frame(width: width, height: totalHeight, alignment: .topLeading)
            .padding(.horizontal, 8)
        }
        .frame(height: totalHeight)
    }

    static func featureIcon(_ feature: String) -> String {
        switch feature {
        case "restaurant": return "fork.knife"
        case "wheelchair": return "figure.roll"
        case "family": return "figure.2.and.child.holdinghands"
        case "bike": return "bicycle"
        default: return "briefcase"
        }
    }

    static func featureLabel(_ feature: String) -> LocalizedStringKey {
        switch feature {
        case "restaurant": return "Restaurant"
        case "wheelchair": return "Wheelchair space"
        case "family": return "Family zone"
        case "bike": return "Bike space"
        default: return "Business zone"
        }
    }
}

// MARK: - Locomotive

private struct LocoView: View {
    let width: CGFloat
    let height: CGFloat

    var body: some View {
        ZStack {
            // Body
            LocoShape()
                .fill(Color(.systemGray5))
                .frame(width: width, height: height)

            // Outline
            LocoShape()
                .stroke(Color(.systemGray3), lineWidth: 0.5)
                .frame(width: width, height: height)

            // Windshield (in the upper curve area)
            RoundedRectangle(cornerRadius: 2)
                .fill(Color.primary.opacity(0.09))
                .frame(width: 8, height: height * 0.38)
                .offset(x: -width * 0.06, y: -height * 0.12)

            // Headlight at nose tip (bottom-left)
            Circle()
                .fill(Color.primary.opacity(0.20))
                .frame(width: 3, height: 3)
                .offset(x: -width / 2 + 4, y: height / 2 - 5)
        }
    }
}

private struct LocoShape: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        let r: CGFloat = 3
        let h = rect.height
        let w = rect.width

        // ETR 610 Pendolino nose profile:
        // - Nose tip at bottom-left, very low (near rail)
        // - Dramatic upward sweep, steep S-curve to windshield
        // - Windshield high and raked back
        // - Roofline about 70% back from nose tip

        // Start bottom-right
        path.move(to: CGPoint(x: rect.maxX, y: rect.maxY - r))
        path.addQuadCurve(to: CGPoint(x: rect.maxX - r, y: rect.maxY),
                          control: CGPoint(x: rect.maxX, y: rect.maxY))

        // Bottom edge, flat to nose tip
        path.addLine(to: CGPoint(x: rect.minX + 1, y: rect.maxY))

        // Nose tip, sharp rounded point at bottom
        path.addQuadCurve(
            to: CGPoint(x: rect.minX, y: rect.maxY - 2),
            control: CGPoint(x: rect.minX - 0.5, y: rect.maxY)
        )

        // Dramatic S-curve sweep from nose tip up to roofline
        // First: steep upward from the nose (concave section)
        // Then: eases into the roofline (convex section)
        path.addCurve(
            to: CGPoint(x: rect.minX + w * 0.7, y: rect.minY),
            control1: CGPoint(x: rect.minX + w * 0.05, y: h * 0.15),
            control2: CGPoint(x: rect.minX + w * 0.35, y: rect.minY)
        )

        // Roof to top-right
        path.addLine(to: CGPoint(x: rect.maxX - r, y: rect.minY))
        path.addQuadCurve(to: CGPoint(x: rect.maxX, y: rect.minY + r),
                          control: CGPoint(x: rect.maxX, y: rect.minY))

        path.closeSubpath()
        return path
    }
}

// MARK: - Carriage

private struct CarriageCell: View {
    let wagon: FormationWagon
    let width: CGFloat
    let height: CGFloat

    private let firstClassYellow = Color(red: 0.92, green: 0.72, blue: 0.0)

    var body: some View {
        ZStack {
            ZStack(alignment: .topLeading) {
                RoundedRectangle(cornerRadius: 3)
                    .fill(Color(.systemGray5))
                    .frame(width: width, height: height)

                // First class runs the yellow roof stripe the full car, mixed class half of it.
                if wagon.wagonClass == 1 || wagon.mixedClass {
                    let full = max(0, width - 4)
                    RoundedRectangle(cornerRadius: 1)
                        .fill(firstClassYellow)
                        .frame(width: wagon.mixedClass ? full / 2 : full, height: 2.5)
                        .offset(x: 2, y: 1.5)
                }
            }
            .frame(width: width, height: height)
            .clipShape(RoundedRectangle(cornerRadius: 3))
            .opacity(wagon.closed ? 0.4 : 1.0)

            RoundedRectangle(cornerRadius: 3)
                .stroke(Color(.systemGray3), lineWidth: 0.5)
                .frame(width: width, height: height)

            if !wagon.closed, let number = wagon.number {
                Text(verbatim: "\(number)")
                    .font(.system(size: 11, weight: .semibold, design: .rounded))
                    .foregroundColor(.secondary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.5)
                    .frame(width: max(0, width - 2))
                    .offset(y: 1)
            }
        }
    }
}
