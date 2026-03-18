import SwiftUI

struct WatchFormationView: View {
    let formation: Formation

    private let carriageHeight: CGFloat = 14
    private let gap: CGFloat = 1
    private let noseWidth: CGFloat = 14

    var body: some View {
        GeometryReader { geo in
            let n = CGFloat(formation.wagons.count)
            let available = geo.size.width - noseWidth - (n - 1) * gap
            let carriageWidth = min(16, max(available / n, 8))

            VStack(spacing: 1) {
                // Train
                HStack(spacing: 0) {
                    // Locomotive
                    WatchLocoView(height: carriageHeight)

                    // Carriages
                    ForEach(Array(formation.wagons.enumerated()), id: \.offset) { i, wagon in
                        if i > 0 {
                            Rectangle()
                                .fill(Color(white: 0.12))
                                .frame(width: gap, height: carriageHeight * 0.35)
                        }
                        ZStack {
                            RoundedRectangle(cornerRadius: 2)
                                .fill(Color(white: 0.18))
                                .frame(width: carriageWidth, height: carriageHeight)
                                .opacity(wagon.closed ? 0.4 : 1.0)

                            RoundedRectangle(cornerRadius: 2)
                                .stroke(Color(white: 0.30), lineWidth: 0.5)
                                .frame(width: carriageWidth, height: carriageHeight)

                            // 1st class yellow stripe
                            if wagon.wagonClass == 1 {
                                VStack {
                                    RoundedRectangle(cornerRadius: 0.5)
                                        .fill(Color(red: 0.92, green: 0.72, blue: 0.0))
                                        .frame(width: carriageWidth - 2, height: 1.5)
                                        .offset(y: 1)
                                    Spacer()
                                }
                                .frame(height: carriageHeight)
                                .clipShape(RoundedRectangle(cornerRadius: 2))
                            }

                            // Car number
                            Text("\(wagon.number)")
                                .font(.system(size: 9, weight: .semibold, design: .rounded))
                                .foregroundColor(Color(white: 0.55))
                                .minimumScaleFactor(0.6)
                                .lineLimit(1)
                        }
                    }
                }

                // Sector labels with bracket lines
                if !sectorGroups.isEmpty {
                    WatchSectorLabels(
                        groups: sectorGroups,
                        carriageWidth: carriageWidth,
                        gap: gap,
                        noseWidth: noseWidth
                    )
                }
            }
            .frame(width: geo.size.width)
        }
        .frame(height: 28)
    }

    struct SectorGroup {
        let sector: String
        let count: Int
    }

    private var sectorGroups: [SectorGroup] {
        var groups: [SectorGroup] = []
        var currentSector = ""
        var count = 0

        for wagon in formation.wagons {
            if wagon.sector != currentSector {
                if count > 0 {
                    groups.append(SectorGroup(sector: currentSector, count: count))
                }
                currentSector = wagon.sector
                count = 1
            } else {
                count += 1
            }
        }
        if count > 0 {
            groups.append(SectorGroup(sector: currentSector, count: count))
        }
        return groups
    }
}

private struct WatchSectorLabels: View {
    let groups: [WatchFormationView.SectorGroup]
    let carriageWidth: CGFloat
    let gap: CGFloat
    let noseWidth: CGFloat

    var body: some View {
        HStack(spacing: 0) {
            Image(systemName: "arrow.left")
                .font(.system(size: 7, weight: .medium))
                .foregroundColor(.white)
                .frame(width: noseWidth)

            ForEach(Array(groups.enumerated()), id: \.offset) { i, group in
                let groupWidth = CGFloat(group.count) * carriageWidth + CGFloat(max(0, group.count - 1)) * gap + (i > 0 ? gap : 0)

                ZStack {
                    // Line through the middle
                    Rectangle()
                        .fill(Color(white: 0.35))
                        .frame(width: groupWidth - 2, height: 0.5)

                    // Sector letter with opaque background
                    Text(group.sector)
                        .font(.system(size: 9, weight: .bold))
                        .foregroundColor(.white)
                        .padding(.horizontal, 2)
                        .background(Color.black)
                }
                .frame(width: groupWidth, height: 12)
            }
        }
    }
}

private struct WatchLocoView: View {
    let height: CGFloat
    private let width: CGFloat = 14

    var body: some View {
        ZStack {
            WatchLocoShape()
                .fill(Color(white: 0.18))
                .frame(width: width, height: height)

            WatchLocoShape()
                .stroke(Color(white: 0.32), lineWidth: 0.5)
                .frame(width: width, height: height)

            // Headlight at nose tip
            Circle()
                .fill(Color.white.opacity(0.18))
                .frame(width: 1.5, height: 1.5)
                .offset(x: -width / 2 + 2, y: height / 2 - 2)
        }
    }
}

private struct WatchLocoShape: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        let r: CGFloat = 1.5
        let h = rect.height
        let w = rect.width

        // ETR 610 nose: tip at bottom, dramatic S-curve up

        // Bottom-right
        path.move(to: CGPoint(x: rect.maxX, y: rect.maxY - r))
        path.addQuadCurve(to: CGPoint(x: rect.maxX - r, y: rect.maxY),
                          control: CGPoint(x: rect.maxX, y: rect.maxY))

        // Flat bottom to nose tip
        path.addLine(to: CGPoint(x: rect.minX + 0.5, y: rect.maxY))

        // Nose tip
        path.addQuadCurve(
            to: CGPoint(x: rect.minX, y: rect.maxY - 1.5),
            control: CGPoint(x: rect.minX - 0.3, y: rect.maxY)
        )

        // Dramatic S-curve sweep
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
