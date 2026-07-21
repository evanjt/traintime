import SwiftUI
import WidgetKit

struct WidgetEntryView: View {
    @Environment(\.widgetFamily) var family
    let entry: DepartureEntry

    var body: some View {
        if isAccessory {
            accessoryView
                .containerBackground(for: .widget) { Color.clear }
        } else {
            systemView
                .containerBackground(.fill.tertiary, for: .widget)
        }
    }

    private var isAccessory: Bool {
        switch family {
        case .accessoryRectangular, .accessoryInline, .accessoryCircular: return true
        default: return false
        }
    }

    @ViewBuilder
    private var systemView: some View {
        if entry.isDormant {
            dormantView
        } else {
            activeView
        }
    }

    @ViewBuilder
    private var accessoryView: some View {
        switch family {
        case .accessoryInline: AccessoryInlineView(entry: entry)
        case .accessoryCircular: AccessoryCircularView(entry: entry)
        default: AccessoryRectangularView(entry: entry)
        }
    }

    // MARK: - Row metrics (scaled per family, medium ≈ the phone's PhoneDepartureRowView)

    private struct RowMetrics {
        var minutesFont: Font
        var clockFont: Font
        var minutesWidth: CGFloat
        var showDelay: Bool
        var delayWidth: CGFloat
        var lineFont: Font
        var lineWidth: CGFloat
        var destFont: Font
        var starSize: CGFloat
        var hSpacing: CGFloat
    }

    private var rowMetrics: RowMetrics {
        switch family {
        case .systemSmall:
            return RowMetrics(
                minutesFont: .system(size: 16, weight: .bold, design: .rounded),
                clockFont: .system(size: 13, weight: .semibold, design: .rounded),
                minutesWidth: 26, showDelay: false, delayWidth: 0,
                lineFont: .system(size: 12, weight: .semibold), lineWidth: 34,
                destFont: .subheadline, starSize: 9, hSpacing: 5)
        case .systemLarge:
            return RowMetrics(
                minutesFont: .system(size: 19, weight: .bold, design: .rounded),
                clockFont: .system(size: 15, weight: .semibold, design: .rounded),
                minutesWidth: 40, showDelay: true, delayWidth: 34,
                lineFont: .system(.subheadline, weight: .semibold), lineWidth: 46,
                destFont: .body, starSize: 12, hSpacing: 8)
        default: // medium
            return RowMetrics(
                minutesFont: .system(size: 20, weight: .bold, design: .rounded),
                clockFont: .system(size: 15, weight: .semibold, design: .rounded),
                minutesWidth: 42, showDelay: true, delayWidth: 34,
                lineFont: .system(.subheadline, weight: .semibold), lineWidth: 46,
                destFont: .body, starSize: 12, hSpacing: 8)
        }
    }

    private var headerFont: Font {
        family == .systemSmall ? .subheadline.weight(.bold) : .headline
    }

    // Header control glyphs sit a step up from .subheadline and carry a square min hit area, so
    // refresh / stop / favourite / mode are comfortable finger targets (Apple's own widgets use
    // similarly chunky controls) without the row feeling crowded.
    private var headerControlFont: Font {
        family == .systemSmall ? .subheadline : .body
    }

    private var controlHitSize: CGFloat {
        family == .systemSmall ? 22 : 28
    }

    // MARK: - Dormant View

    @ViewBuilder
    private var dormantView: some View {
        if entry.departures.isEmpty {
            simpleDormantView
        } else {
            staleDormantView
        }
    }

    private var simpleDormantView: some View {
        VStack(spacing: 8) {
            HStack(spacing: 4) {
                Image(systemName: "tram.fill")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text("TrainTime")
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(.secondary)
            }

            if let name = entry.stationName {
                Text(name)
                    .font(.headline)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            Spacer()
            refreshButton
            Spacer()
        }
        .padding(12)
    }

    private var staleDormantView: some View {
        let limit = max(1, maxDepartureRows - 1)
        let rows = entry.hideFavouritesBlock ? entry.regularRows(limit: limit) : entry.displayDepartures(limit: limit)
        return GeometryReader { geo in
            VStack(spacing: 0) {
                HStack(spacing: 6) {
                    Image(systemName: "tram.fill")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                    Text(entry.stationName ?? "TrainTime")
                        .font(headerFont)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                    Spacer()
                    if let asOf = entry.asOf {
                        // Clock time, not a stale minute count. A dormant widget can sit for hours.
                        Text("as of \(asOf, style: .time)")
                            .font(.caption2)
                            .foregroundStyle(.tertiary)
                    }
                }

                Divider().padding(.vertical, 4)

                ForEach(Array(rows.enumerated()), id: \.offset) { _, dep in
                    staleRow(dep).frame(maxHeight: .infinity)
                }

                refreshButton.padding(.top, 6)
            }
            .frame(width: geo.size.width, height: geo.size.height, alignment: .top)
        }
        .padding(12)
    }

    private func staleRow(_ dep: WidgetDeparture) -> some View {
        let m = rowMetrics
        // Clock column spans minutes + delay so the line/destination columns line up with the active view.
        let clockWidth = m.minutesWidth + (m.showDelay ? m.hSpacing + m.delayWidth : 0)
        return HStack(spacing: m.hSpacing) {
            Text(dep.clockTimeText)
                .font(m.clockFont)
                .foregroundStyle(.secondary)
                .frame(width: clockWidth, alignment: .trailing)
            Text(lineLabel(dep))
                .font(m.lineFont)
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
                .frame(width: m.lineWidth, alignment: .leading)
            Text(dep.destination)
                .font(m.destFont)
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .truncationMode(.tail)
            Spacer(minLength: 0)
            if entry.isFavourite(dep) {
                Image(systemName: "star.fill")
                    .font(.system(size: m.starSize))
                    .foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var refreshButton: some View {
        Button(intent: RefreshIntent()) {
            Label("Refresh", systemImage: "arrow.clockwise")
                .font(.subheadline.weight(.medium))
        }
        .buttonStyle(.bordered)
        .tint(.blue)
    }

    // MARK: - Active View

    private var activeView: some View {
        let maxRows = maxDepartureRows
        // Classic mode: no favourites block, just the next departures in time order
        // (favourites among them stay starred). Otherwise favourites are pulled to the top.
        let favShown = entry.hideFavouritesBlock ? [] : entry.favouriteRows(limit: maxRows)
        let regularShown = entry.regularRows(limit: maxRows - favShown.count)
        return GeometryReader { geo in
            VStack(spacing: 0) {
                headerRow

                Divider().padding(.vertical, 4)

                if favShown.isEmpty && regularShown.isEmpty {
                    Spacer()
                    Text(entry.outsideSwitzerland ? String(localized: "Outside of Switzerland") : String(localized: "No departures"))
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity)
                    Spacer()
                } else {
                    ForEach(Array(favShown.enumerated()), id: \.offset) { _, dep in
                        departureRow(dep, isFavourite: true)
                            .frame(maxHeight: .infinity)
                    }
                    if !favShown.isEmpty && !regularShown.isEmpty {
                        Rectangle()
                            .fill(AppColors.favouriteSeparator)
                            .frame(height: 1.5)
                            .padding(.vertical, 2)
                    }
                    ForEach(Array(regularShown.enumerated()), id: \.offset) { _, dep in
                        departureRow(dep, isFavourite: entry.isFavourite(dep))
                            .frame(maxHeight: .infinity)
                    }
                }
            }
            .frame(width: geo.size.width, height: geo.size.height, alignment: .top)
        }
        .padding(12)
        // systemSmall honours only one tap region, so the whole tile opens the next departure;
        // medium/large get a per-row Link instead (set in departureRow).
        .widgetURL(family == .systemSmall ? entry.displayDepartures(limit: 1).first?.trackURL : nil)
    }

    private var headerRow: some View {
        HStack(spacing: 4) {
            // Mode icon, medium/large only (no room on small)
            if family != .systemSmall, let mode = entry.currentMode {
                if entry.availableModes.count > 1 {
                    Button(intent: SwitchModeIntent()) {
                        Image(systemName: mode.sfSymbol)
                            .font(headerControlFont)
                            .foregroundStyle(.blue)
                            .frame(minWidth: controlHitSize, minHeight: controlHitSize)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                } else {
                    Image(systemName: mode.sfSymbol)
                        .font(headerControlFont)
                        .foregroundStyle(.secondary)
                        .frame(minWidth: controlHitSize, minHeight: controlHitSize)
                }
            }

            // Station name, tappable to cycle stations
            if entry.stationCount > 1 {
                Button(intent: SwitchStationIntent()) {
                    HStack(spacing: 3) {
                        Text(entry.stationName ?? String(localized: "Station"))
                            .font(headerFont)
                            .foregroundStyle(.primary)
                            .lineLimit(1)
                        if family != .systemSmall {
                            Text("\(entry.stationIndex + 1)/\(entry.stationCount)")
                                .font(.caption2.weight(.medium))
                                .foregroundStyle(.secondary)
                            Image(systemName: "chevron.down")
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }
                    }
                    .frame(minHeight: controlHitSize)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            } else {
                Text(entry.stationName ?? String(localized: "Station"))
                    .font(headerFont)
                    .foregroundStyle(.primary)
                    .lineLimit(1)
            }

            Spacer(minLength: 4)

            // Toggle favourites grouping, only useful (and only room) when there are
            // favourites at this station and on the larger families.
            if family != .systemSmall && !entry.favouriteKeys.isEmpty {
                Button(intent: ToggleFavouritesIntent()) {
                    Image(systemName: entry.hideFavouritesBlock ? "star.slash" : "star.fill")
                        .font(headerControlFont)
                        .foregroundStyle(entry.hideFavouritesBlock ? Color.secondary : AppColors.favouriteStar)
                        .frame(minWidth: controlHitSize, minHeight: controlHitSize)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }

            // Stop: drop straight back to dormant (the breaker also opens on its own after the
            // active window). No room on small, which just waits out the timeout.
            if family != .systemSmall {
                Button(intent: StopIntent()) {
                    Image(systemName: "stop.circle")
                        .font(headerControlFont)
                        .foregroundStyle(.secondary)
                        .frame(minWidth: controlHitSize, minHeight: controlHitSize)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }

            Button(intent: RefreshIntent()) {
                Image(systemName: "arrow.clockwise")
                    .font(headerControlFont)
                    .foregroundStyle(.secondary)
                    .frame(minWidth: controlHitSize, minHeight: controlHitSize)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
        }
    }

    @ViewBuilder
    private func departureRow(_ dep: WidgetDeparture, isFavourite: Bool) -> some View {
        let row = departureRowContent(dep, isFavourite: isFavourite)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
            .background {
                if isFavourite {
                    RoundedRectangle(cornerRadius: 6)
                        .fill(AppColors.favouriteBackground)
                }
            }
        if family == .systemSmall {
            row
        } else {
            Link(destination: dep.trackURL) { row }
        }
    }

    private func departureRowContent(_ dep: WidgetDeparture, isFavourite: Bool) -> some View {
        let m = rowMetrics
        return HStack(spacing: m.hSpacing) {
            // Minutes
            Text(dep.minutesText(at: entry.date))
                .font(m.minutesFont)
                .foregroundStyle(minutesColor(dep))
                .lineLimit(1)
                .minimumScaleFactor(0.8)
                .frame(width: m.minutesWidth, alignment: .trailing)

            // Delay capsule, reserved column with an explicit spacer when on time, so the
            // line + destination columns line up whether or not a row has a delay.
            if m.showDelay {
                if dep.delay > 0 {
                    Text("+\(dep.delay)")
                        .font(.system(.caption, design: .rounded, weight: .medium))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 5)
                        .padding(.vertical, 2)
                        .background(Capsule().fill(AppColors.delay))
                        .frame(width: m.delayWidth, alignment: .leading)
                } else {
                    Spacer().frame(width: m.delayWidth)
                }
            }

            // Line, filled pill in a reserved column so destinations line up.
            Group {
                if !dep.lineNumber.isEmpty {
                    Text(dep.lineNumber)
                        .font(m.lineFont)
                        .foregroundStyle(.white)
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
                        .padding(.horizontal, 5)
                        .padding(.vertical, 1)
                        .background(
                            RoundedRectangle(cornerRadius: 5)
                                .fill(AppColors.linePill(dep.lineNumber, mode: entry.currentMode ?? .train))
                        )
                } else if !dep.platform.isEmpty {
                    Text(lineLabel(dep))
                        .font(m.lineFont)
                        .foregroundStyle(lineColor(dep))
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
                }
            }
            .frame(width: m.lineWidth, alignment: .leading)

            // Destination
            Text(dep.destination)
                .font(m.destFont)
                .foregroundStyle(.primary)
                .lineLimit(1)
                .truncationMode(.tail)

            Spacer(minLength: 0)

            if isFavourite {
                Image(systemName: "star.fill")
                    .font(.system(size: m.starSize))
                    .foregroundStyle(AppColors.favouriteStar)
            }
        }
    }

    private func lineLabel(_ dep: WidgetDeparture) -> String {
        if !dep.lineNumber.isEmpty { return dep.lineNumber }
        if !dep.platform.isEmpty { return "P\(dep.platform)" }
        return ""
    }

    private func lineColor(_ dep: WidgetDeparture) -> Color {
        if dep.lineNumber.isEmpty && dep.platformChanged { return .red }
        return AppColors.platform
    }

    private func minutesColor(_ dep: WidgetDeparture) -> Color {
        if dep.isGone(at: entry.date) { return .secondary }
        if dep.minutesUntil(at: entry.date) <= 2 { return AppColors.minutesNow }
        return AppColors.minutesSoon
    }

    private var maxDepartureRows: Int {
        switch family {
        case .systemSmall: return 3
        case .systemMedium: return 3
        case .systemLarge: return 7
        default: return 4
        }
    }
}
