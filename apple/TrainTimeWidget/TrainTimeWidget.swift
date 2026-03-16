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
        if let result = WidgetStorage.load() {
            completion(buildEntry(from: result, date: .now))
        } else {
            completion(.dormant())
        }
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<DepartureEntry>) -> Void) {
        guard let result = WidgetStorage.load() else {
            completion(Timeline(entries: [.dormant()], policy: .never))
            return
        }

        let fetchAge = Date().timeIntervalSince1970 - result.fetchTime
        if fetchAge > 60 {
            let stationName = result.currentStation?.name
            completion(Timeline(
                entries: [.dormant(stationName: stationName)],
                policy: .never
            ))
            return
        }

        let now = Date()
        let dormantDate = Calendar.current.date(byAdding: .second, value: 60, to: now)!
        let stationName = result.currentStation?.name

        let entries: [DepartureEntry] = [
            buildEntry(from: result, date: now),
            .dormant(date: dormantDate, stationName: stationName)
        ]

        completion(Timeline(entries: entries, policy: .after(dormantDate)))
    }

    private func buildEntry(from result: WidgetFetchResult, date: Date) -> DepartureEntry {
        let station = result.currentStation
        let stns = result.stations(for: result.selectedMode)
        return DepartureEntry(
            date: date,
            stationName: station?.name,
            departures: station?.departures ?? [],
            isDormant: false,
            currentMode: result.selectedMode,
            availableModes: result.availableModes,
            stationIndex: min(result.selectedStationIndex, max(stns.count - 1, 0)),
            stationCount: stns.count
        )
    }
}
