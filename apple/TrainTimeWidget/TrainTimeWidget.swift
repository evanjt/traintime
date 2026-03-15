import WidgetKit
import SwiftUI

@main
struct TrainTimeWidgetBundle: WidgetBundle {
    var body: some Widget {
        TrainTimeWidget()
    }
}

struct TrainTimeWidget: Widget {
    let kind: String = "TrainTimeWidget"

    var body: some WidgetConfiguration {
        StaticConfiguration(
            kind: kind,
            provider: TrainTimeTimelineProvider()
        ) { entry in
            WidgetEntryView(entry: entry)
                .containerBackground(.fill.tertiary, for: .widget)
        }
        .configurationDisplayName("TrainTime")
        .description("Nearby departures at a glance.")
        .supportedFamilies([.systemSmall, .systemMedium, .systemLarge])
    }
}

struct TrainTimeTimelineProvider: TimelineProvider {
    typealias Entry = DepartureEntry

    func placeholder(in context: Context) -> DepartureEntry {
        DepartureEntry.placeholder
    }

    func getSnapshot(in context: Context, completion: @escaping (DepartureEntry) -> Void) {
        if context.isPreview {
            completion(.placeholder)
            return
        }
        // Show current state from storage
        if let result = WidgetStorage.load() {
            completion(DepartureEntry(
                date: .now,
                stationName: result.stationName,
                departures: result.departures,
                isDormant: false
            ))
        } else {
            completion(.dormant())
        }
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<DepartureEntry>) -> Void) {
        guard let result = WidgetStorage.load() else {
            // No data — stay dormant, never auto-refresh
            completion(Timeline(entries: [.dormant()], policy: .never))
            return
        }

        // Check if the fetch is stale (>5 min old)
        let fetchAge = Date().timeIntervalSince1970 - result.fetchTime
        if fetchAge > 300 {
            // Stale — return to dormant with cached station name
            completion(Timeline(
                entries: [.dormant(stationName: result.stationName)],
                policy: .never
            ))
            return
        }

        let now = Date()
        var entries: [DepartureEntry] = []

        // Pre-compute 5 timeline entries at 1-minute intervals
        // Departures use absolute timestamps, so minutesUntil recomputes correctly at each entry date
        for minuteOffset in 0..<5 {
            let entryDate = Calendar.current.date(byAdding: .minute, value: minuteOffset, to: now)!
            entries.append(DepartureEntry(
                date: entryDate,
                stationName: result.stationName,
                departures: result.departures,
                isDormant: false
            ))
        }

        // Final entry at T+5min returns to dormant
        let dormantDate = Calendar.current.date(byAdding: .minute, value: 5, to: now)!
        entries.append(.dormant(date: dormantDate, stationName: result.stationName))

        completion(Timeline(entries: entries, policy: .after(dormantDate)))
    }
}
