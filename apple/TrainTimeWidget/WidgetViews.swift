import SwiftUI
import WidgetKit

struct WidgetEntryView: View {
    @Environment(\.widgetFamily) private var family
    @Environment(\.widgetContentMargins) private var hostMargins
    let entry: DepartureEntry

    var body: some View {
        WidgetFamilyView(entry: entry, family: family, hostMargin: min(hostMargins.leading, hostMargins.trailing))
    }
}

/// The widget drawn for one family. The family and the host's content margin are parameters
/// because `widgetFamily` and `widgetContentMargins` are read-only environment values that only
/// WidgetKit sets: outside a widget host they read as their defaults, so a view that reads
/// them there draws the medium family with no host margin, whatever is asked for.
struct WidgetFamilyView: View {
    let entry: DepartureEntry
    let family: WidgetFamily
    /// Inset the host already puts around the content, in points.
    var hostMargin: CGFloat = 0

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

    private var inset: CGFloat { WidgetRowMetrics.inset(family, hostMargin: hostMargin) }

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
        .padding(inset)
    }

    private var staleDormantView: some View {
        GeometryReader { geo in
            let m = WidgetRowMetrics.of(family, rowWidth: geo.size.width)
            let limit = max(1, maxDepartureRows(m) - 1)
            let rows = entry.hideFavouritesBlock ? entry.regularRows(limit: limit) : entry.displayDepartures(limit: limit)
            VStack(spacing: 0) {
                HStack(spacing: 6) {
                    // No room for the icon on small, as in the active header.
                    if family != .systemSmall {
                        Image(systemName: "tram.fill")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                    Text(entry.stationName ?? "TrainTime")
                        .font(headerFont)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                    Spacer(minLength: 0)
                    if let asOf = entry.asOf {
                        // Clock time, not a stale minute count. A dormant widget can sit for hours.
                        // It keeps its width, so a long station name truncates instead of it.
                        Text("as of \(asOf, style: .time)")
                            .font(.caption2)
                            .foregroundStyle(.tertiary)
                            .lineLimit(1)
                            .fixedSize()
                    }
                }

                Divider().padding(.vertical, 4)

                ForEach(Array(rows.enumerated()), id: \.offset) { _, dep in
                    staleRow(dep, m).frame(maxHeight: .infinity)
                }

                refreshButton.padding(.top, 6)
            }
            .frame(width: geo.size.width, height: geo.size.height, alignment: .top)
        }
        .padding(inset)
    }

    private func staleRow(_ dep: WidgetDeparture, _ m: WidgetRowMetrics) -> some View {
        // Clock column spans minutes + delay so the line/destination columns line up with the active view.
        let clockWidth = m.minutesWidth + (m.showDelay ? m.hSpacing + m.delayWidth : 0)
        return rowStack(m) {
            Text(dep.clockTimeText(stationId: entry.stationId))
                .font(m.clockFont)
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .minimumScaleFactor(m.minutesMinScale)
                .frame(width: clockWidth, alignment: m.leadAlignment)
            LinePill(lineLabel(dep), fill: .clear, fontSize: m.lineSize, relativeTo: m.lineStyle,
                     textColor: .secondary, cornerRadius: 5, verticalPadding: 1)
        } destination: {
            destinationText(dep, m)
                .foregroundStyle(.secondary)
        } trailing: {
            if m.showStar && entry.isFavourite(dep) {
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
        GeometryReader { geo in
            let m = WidgetRowMetrics.of(family, rowWidth: geo.size.width)
            let maxRows = maxDepartureRows(m)
            // Classic mode: no favourites block, just the next departures in time order
            // (favourites among them stay starred). Otherwise favourites are pulled to the top.
            let favShown = entry.hideFavouritesBlock ? [] : entry.favouriteRows(limit: maxRows)
            let regularShown = entry.regularRows(limit: maxRows - favShown.count)
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
                        departureRow(dep, m, isFavourite: true)
                            .frame(maxHeight: .infinity)
                    }
                    if !favShown.isEmpty && !regularShown.isEmpty {
                        Rectangle()
                            .fill(AppColors.favouriteSeparator)
                            .frame(height: 1.5)
                            .padding(.vertical, 2)
                    }
                    ForEach(Array(regularShown.enumerated()), id: \.offset) { _, dep in
                        departureRow(dep, m, isFavourite: entry.isFavourite(dep))
                            .frame(maxHeight: .infinity)
                    }
                }
            }
            .frame(width: geo.size.width, height: geo.size.height, alignment: .top)
        }
        .padding(inset)
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
    private func departureRow(_ dep: WidgetDeparture, _ m: WidgetRowMetrics, isFavourite: Bool) -> some View {
        let row = departureRowContent(dep, m, isFavourite: isFavourite)
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

    private func departureRowContent(_ dep: WidgetDeparture, _ m: WidgetRowMetrics, isFavourite: Bool) -> some View {
        rowStack(m) {
            // Minutes
            Text(dep.minutesText(at: entry.date))
                .font(m.minutesFont)
                .foregroundStyle(minutesColor(dep))
                .lineLimit(1)
                .minimumScaleFactor(m.minutesMinScale)
                .frame(width: m.minutesWidth, alignment: m.leadAlignment)

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

            // Line as a fixed-width pill so destinations line up; with no line,
            // the platform takes the same slot unfilled.
            LinePill(
                lineLabel(dep),
                fill: dep.lineNumber.isEmpty
                    ? .clear : AppColors.linePill(dep.lineNumber, mode: entry.currentMode ?? .train),
                fontSize: m.lineSize, relativeTo: m.lineStyle,
                textColor: dep.lineNumber.isEmpty ? lineColor(dep) : .white,
                cornerRadius: 5, verticalPadding: 1
            )
        } destination: {
            destinationText(dep, m)
                .foregroundStyle(.primary)
        } trailing: {
            if m.showStar && isFavourite {
                Image(systemName: "star.fill")
                    .font(.system(size: m.starSize))
                    .foregroundStyle(AppColors.favouriteStar)
            }
        }
    }

    // One row: the fixed columns, the destination, then what trails it. A row too narrow to
    // hold a name beside the columns puts the destination on a line of its own under them.
    @ViewBuilder
    private func rowStack<Columns: View, Destination: View, Trailing: View>(
        _ m: WidgetRowMetrics,
        @ViewBuilder columns: () -> Columns,
        @ViewBuilder destination: () -> Destination,
        @ViewBuilder trailing: () -> Trailing
    ) -> some View {
        if m.stacksDestination {
            VStack(alignment: .leading, spacing: 0) {
                HStack(spacing: m.hSpacing) {
                    columns()
                    Spacer(minLength: 0)
                    trailing()
                }
                destination()
            }
        } else {
            HStack(spacing: m.hSpacing) {
                columns()
                destination()
                trailing()
            }
        }
    }

    // The destination takes every point the fixed columns leave, shrinks before it truncates
    // and truncates at the tail, so a narrow row still shows the start of the name.
    private func destinationText(_ dep: WidgetDeparture, _ m: WidgetRowMetrics) -> some View {
        Text(dep.destination)
            .font(m.destFont)
            .lineLimit(1)
            .truncationMode(.tail)
            .minimumScaleFactor(m.destMinScale)
            .frame(maxWidth: .infinity, alignment: .leading)
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

    // A row with the destination on its own line is two lines high, so one row fewer fits.
    private func maxDepartureRows(_ m: WidgetRowMetrics) -> Int {
        switch family {
        case .systemSmall: return m.stacksDestination ? 2 : 3
        case .systemMedium: return 3
        case .systemLarge: return 7
        default: return 4
        }
    }
}

// Row metrics scaled per family, medium matching the phone's PhoneDepartureRowView.
struct WidgetRowMetrics {
    var minutesSize: CGFloat
    var minutesMinScale: CGFloat
    var clockFont: Font
    var minutesWidth: CGFloat
    var showDelay: Bool
    var delayWidth: CGFloat
    /// Line pill chip font, in points at the default text size.
    var lineSize: CGFloat
    /// Text style the chip font scales with; nil keeps it fixed.
    var lineStyle: Font.TextStyle?
    var destFont: Font
    /// Smallest scale the destination shrinks to before it truncates.
    var destMinScale: CGFloat
    /// Whether a favourite row carries a star besides its tinted background.
    var showStar: Bool
    var starSize: CGFloat
    var hSpacing: CGFloat
    /// Whether the destination sits on a line of its own under the other columns.
    var stacksDestination = false

    /// The countdown or clock leads its line when the destination is stacked under it, and is
    /// a right-aligned column otherwise.
    var leadAlignment: Alignment { stacksDestination ? .leading : .trailing }

    var minutesFont: Font { .system(size: minutesSize, weight: .bold, design: .rounded) }

    /// Row width the destination never gets: the fixed columns before it and their gaps.
    var fixedRowWidth: CGFloat {
        minutesWidth + hSpacing + (showDelay ? delayWidth + hSpacing : 0)
            + lineSize * LinePillGeometry.widthEms + hSpacing
    }

    /// Inset the view adds around its content, on top of the host's own content margin.
    /// The small family has no width to spare, so there the host's margin counts towards it.
    static func inset(_ family: WidgetFamily, hostMargin: CGFloat) -> CGFloat {
        let wanted: CGFloat = 12
        return family == .systemSmall ? max(0, wanted - hostMargin) : wanted
    }

    /// Narrowest destination column a single-line row may have, in points: room for a name of
    /// about seven letters at `destMinScale`.
    static let minDestinationWidth: CGFloat = 40

    /// The metrics for a row `rowWidth` wide. A small row that leaves the destination less
    /// than `minDestinationWidth` beside the fixed columns stacks it instead.
    static func of(_ family: WidgetFamily, rowWidth: CGFloat) -> WidgetRowMetrics {
        var m = of(family)
        if family == .systemSmall, rowWidth - m.fixedRowWidth < minDestinationWidth {
            m.stacksDestination = true
            m.minutesSize = 15
            m.destFont = .footnote
        }
        return m
    }

    static func of(_ family: WidgetFamily) -> WidgetRowMetrics {
        switch family {
        case .systemSmall:
            return WidgetRowMetrics(
                minutesSize: 16, minutesMinScale: 0.55,
                clockFont: .system(size: 13, weight: .semibold, design: .rounded),
                minutesWidth: 27, showDelay: false, delayWidth: 0,
                lineSize: 11, lineStyle: nil,
                destFont: .subheadline, destMinScale: 0.7,
                showStar: false, starSize: 9, hSpacing: 4)
        case .systemLarge:
            return WidgetRowMetrics(
                minutesSize: 19, minutesMinScale: 0.7,
                clockFont: .system(size: 15, weight: .semibold, design: .rounded),
                minutesWidth: 40, showDelay: true, delayWidth: 34,
                lineSize: 15, lineStyle: .subheadline,
                destFont: .body, destMinScale: 1,
                showStar: true, starSize: 12, hSpacing: 8)
        default:
            return WidgetRowMetrics(
                minutesSize: 20, minutesMinScale: 0.7,
                clockFont: .system(size: 15, weight: .semibold, design: .rounded),
                minutesWidth: 42, showDelay: true, delayWidth: 34,
                lineSize: 15, lineStyle: .subheadline,
                destFont: .body, destMinScale: 1,
                showStar: true, starSize: 12, hSpacing: 8)
        }
    }
}
