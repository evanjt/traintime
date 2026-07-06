import SwiftUI

struct FormationDiagramView: View {
    let formation: Formation

    private let carriageHeight: CGFloat = 30
    private let gap: CGFloat = 2
    private let locoWidth: CGFloat = 32

    private struct WagonGroup {
        let sector: String
        let wagons: [FormationWagon]
    }

    private func sectorGroups(_ wagons: [FormationWagon]) -> [WagonGroup] {
        var groups: [WagonGroup] = []
        var current = ""
        var batch: [FormationWagon] = []
        for w in wagons {
            if w.sector != current {
                if !batch.isEmpty { groups.append(WagonGroup(sector: current, wagons: batch)) }
                current = w.sector
                batch = [w]
            } else {
                batch.append(w)
            }
        }
        if !batch.isEmpty { groups.append(WagonGroup(sector: current, wagons: batch)) }
        return groups
    }

    var body: some View {
        VStack(spacing: 2) {
            GeometryReader { geo in
                let n = CGFloat(formation.wagons.count)
                let available = geo.size.width - 16 - locoWidth - (n - 1) * gap
                let carriageWidth = min(56, max(available / n, 20))

                VStack(alignment: .leading, spacing: 3) {
                    // Train with sector group boxes
                    HStack(spacing: 0) {
                        // Locomotive
                        LocoView(height: carriageHeight)

                        // Carriages grouped by sector
                        let groups = sectorGroups(formation.wagons)
                        ForEach(Array(groups.enumerated()), id: \.offset) { gi, group in
                            if gi > 0 {
                                Rectangle()
                                    .fill(Color(.systemGray6))
                                    .frame(width: gap, height: carriageHeight * 0.35)
                            }
                            HStack(spacing: 0) {
                                ForEach(Array(group.wagons.enumerated()), id: \.offset) { wi, wagon in
                                    if wi > 0 {
                                        Rectangle()
                                            .fill(Color(.systemGray6))
                                            .frame(width: gap, height: carriageHeight * 0.35)
                                    }
                                    CarriageCell(wagon: wagon, width: carriageWidth, height: carriageHeight, showFeature: carriageWidth >= 30)
                                }
                            }
                            .padding(.vertical, 2)
                            .background(
                                RoundedRectangle(cornerRadius: 5)
                                    .stroke(Color(.systemGray3), lineWidth: 0.5)
                            )
                        }
                    }

                    // Sector labels with bracket lines
                    if !formation.sectors.isEmpty {
                        PhoneSectorLabels(
                            wagons: formation.wagons,
                            carriageWidth: carriageWidth,
                            gap: gap,
                            locoOffset: locoWidth
                        )
                    }
                }
                .padding(.horizontal, 8)
            }
            .frame(height: 54)
        }
    }
}

// MARK: - Locomotive

private struct LocoView: View {
    let height: CGFloat
    private let width: CGFloat = 32

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
    var showFeature: Bool = true

    var body: some View {
        ZStack {
            // Body
            RoundedRectangle(cornerRadius: 3)
                .fill(Color(.systemGray5))
                .frame(width: width, height: height)
                .opacity(wagon.closed ? 0.4 : 1.0)

            // Outline
            RoundedRectangle(cornerRadius: 3)
                .stroke(Color(.systemGray3), lineWidth: 0.5)
                .frame(width: width, height: height)

            // 1st class accent, yellow stripe along top
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
                .fill(Color.primary.opacity(0.06))
                .frame(width: width - 6, height: 6)
                .offset(y: -3)

            // Car number
            Text("\(wagon.number)")
                .font(.system(size: 11, weight: .semibold, design: .rounded))
                .foregroundColor(.secondary)
                .offset(y: 2)

            // Feature icon
            if showFeature, let feature = wagon.features.first {
                Image(systemName: featureIcon(feature))
                    .font(.system(size: 7))
                    .foregroundColor(Color(.systemGray))
                    .offset(x: width / 2 - 8, y: height / 2 - 6)
            }

            // Closed
            if wagon.closed {
                Rectangle()
                    .fill(Color.primary.opacity(0.35))
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

// MARK: - Sector Labels with bracket lines

private struct PhoneSectorLabels: View {
    let wagons: [FormationWagon]
    let carriageWidth: CGFloat
    let gap: CGFloat
    let locoOffset: CGFloat

    private struct SectorGroup {
        let sector: String
        let count: Int
    }

    private var groups: [SectorGroup] {
        var result: [SectorGroup] = []
        var currentSector = ""
        var count = 0
        for wagon in wagons {
            if wagon.sector != currentSector {
                if count > 0 {
                    result.append(SectorGroup(sector: currentSector, count: count))
                }
                currentSector = wagon.sector
                count = 1
            } else {
                count += 1
            }
        }
        if count > 0 {
            result.append(SectorGroup(sector: currentSector, count: count))
        }
        return result
    }

    var body: some View {
        HStack(spacing: 0) {
            Image(systemName: "arrow.left")
                .font(.system(size: 9, weight: .semibold))
                .foregroundColor(.primary)
                .frame(width: locoOffset)

            ForEach(Array(groups.enumerated()), id: \.offset) { i, group in
                let groupWidth = CGFloat(group.count) * carriageWidth + CGFloat(max(0, group.count - 1)) * gap + (i > 0 ? gap : 0)

                ZStack {
                    // Line through the middle of the text
                    Rectangle()
                        .fill(Color(.systemGray3))
                        .frame(width: groupWidth - 4, height: 0.5)

                    // Sector letter with opaque background to "break" the line
                    Text(group.sector)
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundColor(.primary)
                        .padding(.horizontal, 3)
                        .background(Color(uiColor: .systemBackground))
                }
                .frame(width: groupWidth, height: 14)
            }
        }
    }
}
