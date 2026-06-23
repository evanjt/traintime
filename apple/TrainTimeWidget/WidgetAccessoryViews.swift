import SwiftUI
import WidgetKit

// Lock Screen / StandBy families. Same breaker pattern: no network here, just cached data.
// Colour washes out in vibrant rendering, so the star glyph (not a gold tint) marks favourites.

private let appURL = URL(string: "traintime://")!

extension WidgetDeparture {
    var trackURL: URL {
        let dest = destination.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? ""
        return URL(string: "traintime://track?destination=\(dest)&timestamp=\(departureTimestamp)") ?? appURL
    }
}

struct AccessoryRectangularView: View {
    let entry: DepartureEntry

    var body: some View {
        VStack(alignment: .leading, spacing: 1) {
            if entry.isDormant {
                dormant
            } else {
                active
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
        .widgetURL(entry.isDormant ? appURL : firstURL)
    }

    private var firstURL: URL {
        entry.displayDepartures(limit: 1).first?.trackURL ?? appURL
    }

    @ViewBuilder
    private var active: some View {
        Text(entry.stationName ?? "TrainTime")
            .font(.caption2.weight(.semibold))
            .lineLimit(1)
            .widgetAccentable()

        let rows = entry.displayDepartures(limit: 2)
        if rows.isEmpty {
            Text(entry.outsideSwitzerland ? "Outside of Switzerland" : "No departures").font(.caption2).foregroundStyle(.secondary)
        } else {
            ForEach(Array(rows.enumerated()), id: \.offset) { _, dep in
                HStack(spacing: 4) {
                    Text(dep.minutesText(at: entry.date))
                        .font(.caption2.weight(.bold))
                        .monospacedDigit()
                    if !dep.lineNumber.isEmpty {
                        Text(dep.lineNumber).font(.caption2)
                    }
                    Text(dep.destination).font(.caption2).lineLimit(1).truncationMode(.tail)
                    if entry.isFavourite(dep) {
                        Image(systemName: "star.fill").font(.system(size: 7))
                    }
                    Spacer(minLength: 0)
                }
            }
        }
    }

    @ViewBuilder
    private var dormant: some View {
        Text(entry.stationName ?? "TrainTime")
            .font(.caption2.weight(.semibold))
            .lineLimit(1)
            .widgetAccentable()
        if let asOf = entry.asOf {
            Text("as of \(asOf, style: .time)").font(.caption2).foregroundStyle(.secondary)
        } else {
            Text("Tap to refresh").font(.caption2).foregroundStyle(.secondary)
        }
        Button(intent: RefreshIntent()) {
            Label("Refresh", systemImage: "arrow.clockwise").font(.caption2)
        }
        .buttonStyle(.bordered)
    }
}

struct AccessoryInlineView: View {
    let entry: DepartureEntry

    var body: some View {
        label.widgetURL(entry.isDormant ? appURL : (entry.displayDepartures(limit: 1).first?.trackURL ?? appURL))
    }

    @ViewBuilder
    private var label: some View {
        if entry.isDormant {
            if let asOf = entry.asOf {
                Text("TrainTime · as of \(asOf, style: .time)")
            } else {
                Text("TrainTime · tap to refresh")
            }
        } else if let dep = entry.displayDepartures(limit: 1).first {
            let prefix = dep.lineNumber.isEmpty ? "" : "\(dep.lineNumber) "
            Text("\(prefix)\(dep.destination) · \(dep.minutesText(at: entry.date))")
        } else {
            Text(entry.outsideSwitzerland ? "Outside of Switzerland" : "No departures")
        }
    }
}

struct AccessoryCircularView: View {
    let entry: DepartureEntry

    var body: some View {
        ZStack {
            AccessoryWidgetBackground()
            content
        }
        .widgetURL(entry.isDormant ? nil : entry.displayDepartures(limit: 1).first?.trackURL)
    }

    @ViewBuilder
    private var content: some View {
        if entry.isDormant {
            Button(intent: RefreshIntent()) {
                Image(systemName: "arrow.clockwise").font(.title3)
            }
            .buttonStyle(.plain)
        } else if let dep = entry.displayDepartures(limit: 1).first {
            VStack(spacing: 0) {
                Text(dep.minutesText(at: entry.date))
                    .font(.system(size: 18, weight: .bold, design: .rounded))
                    .minimumScaleFactor(0.5)
                    .lineLimit(1)
                if !dep.lineNumber.isEmpty {
                    Text(dep.lineNumber)
                        .font(.system(size: 9))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }
            .padding(2)
        } else {
            Image(systemName: "tram.fill").font(.title3)
        }
    }
}
