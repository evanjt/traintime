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
            // Container background is applied inside WidgetEntryView so it can vary by family
            // (accessory families need a clear background, not the tinted system fill).
            WidgetEntryView(entry: entry)
        }
        .configurationDisplayName("TrainTime")
        .description("Nearby departures at a glance.")
        .supportedFamilies([
            .systemSmall, .systemMedium, .systemLarge,
            .accessoryRectangular, .accessoryInline, .accessoryCircular
        ])
    }
}

struct TrainTimeTimelineProvider: TimelineProvider {
    typealias Entry = DepartureEntry

    // Tap-to-activate window. Network only ever happens in the user-triggered intents; the
    // provider just replays cached data, ticking the countdown each minute, then goes dormant.
    private let activeWindow: TimeInterval = 300

    func placeholder(in context: Context) -> DepartureEntry {
        DepartureEntry.placeholder
    }

    func getSnapshot(in context: Context, completion: @escaping (DepartureEntry) -> Void) {
        if context.isPreview {
            completion(.placeholder)
            return
        }
        guard let result = WidgetStorage.load() else {
            completion(.dormant())
            return
        }
        FavouritesStore.shared.reload()
        let now = Date()
        let windowEnd = Date(timeIntervalSince1970: result.fetchTime).addingTimeInterval(activeWindow)
        let dormant = now >= windowEnd || WidgetStorage.isStopped(since: result.fetchTime)
        completion(DepartureEntry.make(date: now, result: result, favourites: favourites(for: result), isDormant: dormant, hideFavouritesBlock: WidgetStorage.hideFavouritesBlock, outsideSwitzerland: WidgetStorage.outsideSwitzerland))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<DepartureEntry>) -> Void) {
        guard let result = WidgetStorage.load() else {
            completion(Timeline(entries: [.dormant()], policy: .never))
            return
        }
        FavouritesStore.shared.reload() // fresh favourite flags, no network
        let favs = favourites(for: result)
        let hideFav = WidgetStorage.hideFavouritesBlock
        let outside = WidgetStorage.outsideSwitzerland

        let windowEnd = Date(timeIntervalSince1970: result.fetchTime).addingTimeInterval(activeWindow)
        let now = Date()

        // Past the window, or the user tapped Stop: rich dormant view, breaker open (no refresh
        // until the user taps).
        guard !WidgetStorage.isStopped(since: result.fetchTime), now < windowEnd else {
            completion(Timeline(
                entries: [DepartureEntry.make(date: now, result: result, favourites: favs, isDormant: true, hideFavouritesBlock: hideFav, outsideSwitzerland: outside)],
                policy: .never
            ))
            return
        }

        // One entry per remaining minute so the countdown ticks down; a mid-window reload
        // (favourite toggle, switch intent) re-enters here and emits only what's left.
        var entries: [DepartureEntry] = []
        var t = now
        while t < windowEnd {
            entries.append(DepartureEntry.make(date: t, result: result, favourites: favs, isDormant: false, hideFavouritesBlock: hideFav, outsideSwitzerland: outside))
            t = t.addingTimeInterval(60)
        }
        entries.append(DepartureEntry.make(date: windowEnd, result: result, favourites: favs, isDormant: true, hideFavouritesBlock: hideFav, outsideSwitzerland: outside))
        completion(Timeline(entries: entries, policy: .after(windowEnd)))
    }

    private func favourites(for result: WidgetFetchResult) -> [Favourite] {
        guard let id = result.currentStation?.id else { return [] }
        return FavouritesStore.shared.favouritesForStation(id)
    }
}
