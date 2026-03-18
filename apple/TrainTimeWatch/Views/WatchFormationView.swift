import SwiftUI

struct WatchFormationView: View {
    let formation: Formation

    private let carriageWidth: CGFloat = 16
    private let carriageHeight: CGFloat = 14
    private let gap: CGFloat = 1

    var body: some View {
        VStack(spacing: 1) {
            // Train
            HStack(spacing: 0) {
                // Direction nose
                WatchNoseShape()
                    .fill(Color(white: 0.22))
                    .frame(width: 6, height: carriageHeight)

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
                            .font(.system(size: 7, weight: .medium, design: .rounded))
                            .foregroundColor(Color(white: 0.55))
                            .offset(y: 1)
                    }
                }
            }

            // Sector labels with bracket lines
            if !sectorGroups.isEmpty {
                WatchSectorLabels(
                    groups: sectorGroups,
                    carriageWidth: carriageWidth,
                    gap: gap,
                    noseWidth: 6
                )
            }
        }
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
            Color.clear.frame(width: noseWidth)

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

private struct WatchNoseShape: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        let r: CGFloat = 2
        path.move(to: CGPoint(x: 1, y: rect.midY))
        path.addLine(to: CGPoint(x: rect.maxX - r, y: rect.minY))
        path.addQuadCurve(to: CGPoint(x: rect.maxX, y: rect.minY + r),
                          control: CGPoint(x: rect.maxX, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY - r))
        path.addQuadCurve(to: CGPoint(x: rect.maxX - r, y: rect.maxY),
                          control: CGPoint(x: rect.maxX, y: rect.maxY))
        path.closeSubpath()
        return path
    }
}
