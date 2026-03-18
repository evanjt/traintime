import SwiftUI

struct WatchFormationView: View {
    let formation: Formation

    var body: some View {
        VStack(spacing: 1) {
            // Wagon bars with direction arrow and sector grouping
            HStack(spacing: 0) {
                // Direction arrow at front of train
                WatchDirectionNose(height: 12)
                    .fill(Color(white: 0.25))
                    .frame(width: 8, height: 12)

                ForEach(Array(sectorGroups.enumerated()), id: \.offset) { i, group in
                    if i > 0 {
                        // Sector divider
                        Rectangle()
                            .fill(Color(white: 0.4))
                            .frame(width: 1, height: 20)
                            .padding(.horizontal, 1)
                    }

                    VStack(spacing: 2) {
                        // Wagon bars for this sector
                        HStack(spacing: 1) {
                            ForEach(Array(group.wagons.enumerated()), id: \.offset) { _, wagon in
                                RoundedRectangle(cornerRadius: 1)
                                    .fill(wagonColor(wagon))
                                    .frame(width: 6, height: 12)
                                    .opacity(wagon.closed ? 0.4 : 1.0)
                            }
                        }

                        // Sector letter
                        Text(group.sector)
                            .font(.system(size: 10, weight: .bold))
                            .foregroundColor(.white)
                    }
                }
            }
        }
    }

    private struct SectorGroup {
        let sector: String
        let wagons: [FormationWagon]
    }

    private var sectorGroups: [SectorGroup] {
        var groups: [SectorGroup] = []
        var currentSector = ""
        var currentWagons: [FormationWagon] = []

        for wagon in formation.wagons {
            if wagon.sector != currentSector && !currentWagons.isEmpty {
                groups.append(SectorGroup(sector: currentSector, wagons: currentWagons))
                currentWagons = []
            }
            currentSector = wagon.sector
            currentWagons.append(wagon)
        }
        if !currentWagons.isEmpty {
            groups.append(SectorGroup(sector: currentSector, wagons: currentWagons))
        }
        return groups
    }

    private func wagonColor(_ wagon: FormationWagon) -> Color {
        if wagon.closed { return .gray.opacity(0.5) }
        return wagon.wagonClass == 1 ? Color(red: 0.95, green: 0.75, blue: 0.0) : Color(red: 0.8, green: 0.1, blue: 0.1)
    }
}

// Pointed nose shape for direction of travel (compact watch version)
private struct WatchDirectionNose: Shape {
    let height: CGFloat

    func path(in rect: CGRect) -> Path {
        var path = Path()
        let tipX: CGFloat = 0
        let baseX = rect.maxX
        let midY = rect.midY
        let r: CGFloat = 1.5

        path.move(to: CGPoint(x: tipX + 2, y: midY))
        path.addLine(to: CGPoint(x: baseX - r, y: rect.minY))
        path.addQuadCurve(
            to: CGPoint(x: baseX, y: rect.minY + r),
            control: CGPoint(x: baseX, y: rect.minY)
        )
        path.addLine(to: CGPoint(x: baseX, y: rect.maxY - r))
        path.addQuadCurve(
            to: CGPoint(x: baseX - r, y: rect.maxY),
            control: CGPoint(x: baseX, y: rect.maxY)
        )
        path.closeSubpath()
        return path
    }
}
