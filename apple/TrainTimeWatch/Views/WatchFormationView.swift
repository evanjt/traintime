import SwiftUI

struct WatchFormationView: View {
    let formation: Formation
    // Car highlighted while the readout shows
    var cursor: Int? = nil

    private static let carTop: CGFloat = 1
    private static let carHeight: CGFloat = 14
    private static let lineTop: CGFloat = carTop + carHeight + 1
    private static let lineHeight: CGFloat = 3
    private static let sectorY: CGFloat = lineTop + lineHeight + 6
    static let height: CGFloat = sectorY + 6

    private static let bodyColour = Color(white: 0.30)
    private static let first = Color(red: 0.92, green: 0.72, blue: 0.0)
    private static let breakRed = Color(red: 1, green: 0, blue: 0)

    var body: some View {
        GeometryReader { geo in
            let wagons = formation.wagons
            let breaks = wagons.map(\.noPassageAfter)
            let strip = FormationStrip(width: geo.size.width, breaks: breaks)
            let labels = strip.numberLabels(numbers: wagons.map(\.number), classes: wagons.map(\.wagonClass), breaks: breaks)

            ZStack(alignment: .topLeading) {
                WatchLocoView(width: FormationStrip.noseWidth, height: Self.carHeight)
                    .offset(y: Self.carTop)

                Canvas { ctx, _ in
                    drawCars(ctx, strip: strip, breaks: breaks)
                    drawNumbers(ctx, strip: strip, labels: labels)
                    drawSectors(ctx, strip: strip)
                }
            }
        }
        .frame(height: Self.height)
    }

    private func drawCars(_ ctx: GraphicsContext, strip: FormationStrip, breaks: [Bool]) {
        let w = strip.carWidth
        for (i, wagon) in formation.wagons.enumerated() {
            let x = strip.spans[i].x0
            let car = CGRect(x: x, y: Self.carTop, width: w, height: Self.carHeight)
            if cursor == i {
                ctx.fill(Path(roundedRect: car.insetBy(dx: -1, dy: -1), cornerRadius: 2.5), with: .color(.white))
            }
            var carCtx = ctx
            carCtx.opacity = wagon.closed ? 0.4 : 1
            carCtx.fill(Path(roundedRect: car, cornerRadius: 2), with: .color(Self.bodyColour))
            if wagon.wagonClass == 1 {
                let stripe = wagon.mixedClass ? w / 2 : w
                carCtx.fill(Path(CGRect(x: x, y: Self.carTop, width: stripe, height: 2)), with: .color(Self.first))
            }

            // One colour line on black under the car, a segment per amenity
            let amenities = FormationAmenity.of(wagon)
            if !amenities.isEmpty {
                let seg = (w - 1.5 * CGFloat(amenities.count - 1)) / CGFloat(amenities.count)
                for (q, a) in amenities.enumerated() {
                    let r = CGRect(x: x + CGFloat(q) * (seg + 1.5), y: Self.lineTop, width: seg, height: Self.lineHeight)
                    ctx.fill(Path(r), with: .color(Color(rgb: a.rgb)))
                }
            }

            if breaks[i] && i < formation.wagons.count - 1 {
                let bx = strip.breakX(after: i)
                let bar = CGRect(x: bx - 1, y: 0, width: 2, height: Self.lineTop + Self.lineHeight)
                ctx.fill(Path(bar), with: .color(Self.breakRed))
            }
        }
    }

    private func drawNumbers(_ ctx: GraphicsContext, strip: FormationStrip, labels: [FormationNumberLabel]?) {
        let y = Self.carTop + Self.carHeight / 2 + 0.5
        let runs = labels ?? formation.wagons.indices.map {
            FormationNumberLabel(first: $0, last: $0, text: "\(formation.wagons[$0].number)")
        }
        for label in runs {
            let mid = (strip.spans[label.first].x0 + strip.spans[label.last].x1) / 2
            ctx.draw(
                Text(label.text)
                    .font(.system(size: 9, weight: .semibold, design: .rounded).monospacedDigit())
                    .foregroundColor(Color(white: 0.85)),
                at: CGPoint(x: mid, y: y)
            )
        }
    }

    private func drawSectors(_ ctx: GraphicsContext, strip: FormationStrip) {
        let wagons = formation.wagons
        // Direction of travel under the nose
        ctx.draw(
            Text(Image(systemName: "arrow.left")).font(.system(size: 7, weight: .medium)).foregroundColor(.white),
            at: CGPoint(x: FormationStrip.noseWidth / 2, y: Self.sectorY)
        )
        var i = 0
        while i < wagons.count {
            var j = i + 1
            while j < wagons.count && wagons[j].sector == wagons[i].sector { j += 1 }
            let x0 = strip.spans[i].x0
            let x1 = strip.spans[j - 1].x1
            ctx.fill(Path(CGRect(x: x0 + 1, y: Self.sectorY, width: x1 - x0 - 2, height: 0.5)),
                     with: .color(Color(white: 0.35)))
            let letter = ctx.resolve(Text(wagons[i].sector).font(.system(size: 9, weight: .bold)).foregroundColor(.white))
            let size = letter.measure(in: CGSize(width: 40, height: 20))
            let mid = (x0 + x1) / 2
            ctx.fill(Path(CGRect(x: mid - size.width / 2 - 2, y: Self.sectorY - size.height / 2,
                                 width: size.width + 4, height: size.height)), with: .color(.black))
            ctx.draw(letter, at: CGPoint(x: mid, y: Self.sectorY + 0.25))
            i = j
        }
    }
}

// One line in the walk line's place: car number, sector, each amenity's colour beside its
// icon, and a ring that drains until the readout clears by itself.
struct WatchCarReadout: View {
    let wagon: FormationWagon
    let stepAt: Date

    var body: some View {
        TimelineView(.periodic(from: stepAt, by: 0.2)) { context in
            WatchCarReadoutRow(wagon: wagon, left: FormationReadout.left(elapsed: context.date.timeIntervalSince(stepAt)))
        }
    }
}

struct WatchCarReadoutRow: View {
    let wagon: FormationWagon
    let left: Double

    var body: some View {
        HStack(spacing: 5) {
            Text("\(wagon.number)")
                .font(.system(size: 12, weight: .bold, design: .rounded))
                .foregroundStyle(.white)
            if !wagon.sector.isEmpty {
                Text(wagon.sector)
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.secondary)
            }
            ForEach(FormationAmenity.of(wagon), id: \.self) { a in
                HStack(spacing: 2) {
                    RoundedRectangle(cornerRadius: 1)
                        .fill(Color(rgb: a.rgb))
                        .frame(width: 7, height: 3)
                    Image(systemName: a.symbol)
                        .font(.system(size: 9))
                        .foregroundStyle(.white)
                }
            }
            ReadoutRing(left: left)
        }
    }
}

private struct ReadoutRing: View {
    let left: Double

    var body: some View {
        ZStack {
            Circle().stroke(Color(white: 0.30), lineWidth: 1.5)
            Circle()
                .trim(from: 0, to: left)
                .stroke(Color.white, lineWidth: 1.5)
                .rotationEffect(.degrees(-90))
        }
        .frame(width: 9, height: 9)
    }
}

private extension Color {
    init(rgb: UInt32) {
        self.init(red: Double((rgb >> 16) & 0xFF) / 255, green: Double((rgb >> 8) & 0xFF) / 255, blue: Double(rgb & 0xFF) / 255)
    }
}

private struct WatchLocoView: View {
    let width: CGFloat
    let height: CGFloat

    var body: some View {
        ZStack {
            WatchLocoShape()
                .fill(Color(white: 0.30))
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
