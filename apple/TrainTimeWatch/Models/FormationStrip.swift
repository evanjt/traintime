import Foundation

// Amenities drawn as a colour line under each car. Order is the order of the segments.
enum FormationAmenity: CaseIterable {
    case restaurant, wheelchair, family, bike

    var feature: String {
        switch self {
        case .restaurant: return "restaurant"
        case .wheelchair: return "wheelchair"
        case .family: return "family"
        case .bike: return "bike"
        }
    }

    // Four hues distinct for normal, deutan and protan vision, shared with the other watches
    var rgb: UInt32 {
        switch self {
        case .restaurant: return 0xFF5555
        case .wheelchair: return 0x00AAFF
        case .family: return 0xFFFFFF
        case .bike: return 0x55FF00
        }
    }

    var symbol: String {
        switch self {
        case .restaurant: return "fork.knife"
        case .wheelchair: return "figure.roll"
        case .family: return "figure.2.and.child.holdinghands"
        case .bike: return "bicycle"
        }
    }

    static func of(_ wagon: FormationWagon) -> [FormationAmenity] {
        allCases.filter { wagon.features.contains($0.feature) }
    }
}

struct FormationNumberLabel: Equatable {
    let first: Int
    let last: Int
    let text: String
}

// Straight formation strip: nose on the left, cars front first, a wider slot at each
// no-passage break. Owns the car geometry and which number labels fit over it.
struct FormationStrip {
    static let noseWidth: CGFloat = 12
    static let gap: CGFloat = 1.5
    static let slot: CGFloat = 6
    static let maxCarWidth: CGFloat = 16
    // Advance of one character in the 9 pt rounded semibold number font, digits monospaced
    static let charWidth: CGFloat = 5.5

    let carWidth: CGFloat
    let spans: [(x0: CGFloat, x1: CGFloat)]

    init(width: CGFloat, breaks: [Bool]) {
        let n = breaks.count
        let slots = breaks.dropLast().filter { $0 }.count
        let gaps = max(0, n - 1 - slots)
        let room = width - Self.noseWidth - Self.gap - CGFloat(gaps) * Self.gap - CGFloat(slots) * Self.slot
        carWidth = n > 0 ? min(Self.maxCarWidth, room / CGFloat(n)) : 0
        var x = Self.noseWidth + Self.gap
        var out: [(x0: CGFloat, x1: CGFloat)] = []
        for i in 0..<n {
            out.append((x, x + carWidth))
            x += carWidth + (breaks[i] ? Self.slot : Self.gap)
        }
        spans = out
    }

    // Centre of the break slot after car i
    func breakX(after i: Int) -> CGFloat {
        spans[i].x1 + Self.slot / 2
    }

    func labelFits(_ label: String, _ a: Int, _ b: Int) -> Bool {
        CGFloat(label.count) * Self.charWidth <= spans[b].x1 - spans[a].x0 - 1
    }

    static func rangeLabel(_ numbers: [Int], _ a: Int, _ b: Int) -> String {
        b > a ? "\(numbers[a])–\(numbers[b])" : "\(numbers[a])"
    }

    // Every car's own number when all fit, otherwise a range per run of same-class cars,
    // extended over the next run in the unit until it fits, so every car is covered.
    // Returns nil for per-car numbers.
    func numberLabels(numbers: [Int], classes: [Int], breaks: [Bool]) -> [FormationNumberLabel]? {
        let n = numbers.count
        if (0..<n).allSatisfy({ labelFits("\(numbers[$0])", $0, $0) }) { return nil }
        var out: [FormationNumberLabel] = []
        var i = 0
        while i < n {
            var u = i
            while u < n - 1 && !breaks[u] { u += 1 }
            var a = i
            while a <= u {
                var b = a
                while b < u && classes[b + 1] == classes[a] { b += 1 }
                var label = Self.rangeLabel(numbers, a, b)
                while !labelFits(label, a, b) && b < u {
                    b += 1
                    while b < u && classes[b + 1] == classes[b] { b += 1 }
                    label = Self.rangeLabel(numbers, a, b)
                }
                // A tail that still does not fit joins the label before it in the same unit
                if !labelFits(label, a, b), let prev = out.last, prev.last == a - 1, prev.first >= i {
                    a = prev.first
                    label = Self.rangeLabel(numbers, a, b)
                    out.removeLast()
                }
                if !labelFits(label, a, b) { label = "\(numbers[a])" }
                out.append(FormationNumberLabel(first: a, last: b, text: label))
                a = b + 1
            }
            i = u + 1
        }
        return out
    }
}

// The car readout stays this long after the last Crown step
enum FormationReadout {
    static let seconds: TimeInterval = 5

    // Share of the readout time left, 1 just after a step, 0 once it has gone
    static func left(elapsed: TimeInterval) -> Double {
        min(1, max(0, 1 - elapsed / seconds))
    }
}
