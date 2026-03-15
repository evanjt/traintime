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

        // Check if the fetch is stale (>60s old)
        let fetchAge = Date().timeIntervalSince1970 - result.fetchTime
        if fetchAge > 60 {
            // Stale — return to dormant with cached station name
            completion(Timeline(
                entries: [.dormant(stationName: result.stationName)],
                policy: .never
            ))
            return
        }

        let now = Date()
        let dormantDate = Calendar.current.date(byAdding: .second, value: 60, to: now)!

        // Single active entry, then return to dormant after 60s
        let entries: [DepartureEntry] = [
            DepartureEntry(
                date: now,
                stationName: result.stationName,
                departures: result.departures,
                isDormant: false
            ),
            .dormant(date: dormantDate, stationName: result.stationName)
        ]

        completion(Timeline(entries: entries, policy: .after(dormantDate)))
    }
}
