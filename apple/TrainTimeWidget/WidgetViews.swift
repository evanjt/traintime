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
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                Text("TrainTime")
                    .font(.caption2.weight(.medium))
                    .foregroundStyle(.secondary)
            }

            if let name = entry.stationName {
                Text(name)
                    .font(.caption.weight(.semibold))
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
        let rows = entry.displayDepartures(limit: max(1, maxDepartureRows - 1))
        return VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 4) {
                Image(systemName: "tram.fill")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                Text(entry.stationName ?? "TrainTime")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                Spacer()
                if let asOf = entry.asOf {
                    // Clock time, not a stale minute count — a dormant widget can sit for hours.
                    Text("as of \(asOf, style: .time)")
                        .font(.system(size: 9))
                        .foregroundStyle(.tertiary)
                }
            }

            Divider()

            ForEach(Array(rows.enumerated()), id: \.offset) { _, dep in
                staleRow(dep)
            }

            Spacer(minLength: 0)
            refreshButton
        }
        .padding(12)
    }

    private func staleRow(_ dep: WidgetDeparture) -> some View {
        HStack(spacing: 4) {
            Text(dep.clockTimeText)
                .font(.system(.caption, design: .rounded, weight: .medium))
                .foregroundStyle(.secondary)
                .frame(width: 36, alignment: .trailing)
            if family != .systemSmall, !dep.lineNumber.isEmpty {
                Text(dep.lineNumber)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .frame(width: 24, alignment: .leading)
            }
            Text(dep.destination)
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .truncationMode(.tail)
            Spacer(minLength: 0)
            if entry.isFavourite(dep) {
                Image(systemName: "star.fill")
                    .font(.system(size: 8))
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 1)
    }

    private var refreshButton: some View {
        Button(intent: RefreshIntent()) {
            Label("Refresh", systemImage: "arrow.clockwise")
                .font(.caption.weight(.medium))
        }
        .buttonStyle(.bordered)
        .tint(.blue)
    }

    // MARK: - Active View

    private var activeView: some View {
        let maxRows = maxDepartureRows
        let favShown = entry.favouriteRows(limit: maxRows)
        let regularShown = entry.regularRows(limit: maxRows - favShown.count)
        return VStack(alignment: .leading, spacing: 4) {
            headerRow

            Divider()

            if favShown.isEmpty && regularShown.isEmpty {
                Spacer()
                Text("No departures")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity)
                Spacer()
            } else {
                ForEach(Array(favShown.enumerated()), id: \.offset) { _, dep in
                    widgetDepartureRow(dep, isFavourite: true)
                }
                if !favShown.isEmpty && !regularShown.isEmpty {
                    Rectangle()
                        .fill(AppColors.favouriteSeparator)
                        .frame(height: 1)
                        .padding(.vertical, 1)
                }
                ForEach(Array(regularShown.enumerated()), id: \.offset) { _, dep in
                    widgetDepartureRow(dep, isFavourite: entry.isFavourite(dep))
                }
                Spacer(minLength: 0)
            }
        }
        .padding(12)
    }

    private var headerRow: some View {
        HStack(spacing: 6) {
            // Mode icon — tappable if multiple modes
            if let mode = entry.currentMode {
                if entry.availableModes.count > 1 {
                    Button(intent: SwitchModeIntent()) {
                        Image(systemName: mode.sfSymbol)
                            .font(.caption2)
                            .foregroundStyle(.blue)
                    }
                    .buttonStyle(.plain)
                } else {
                    Image(systemName: mode.sfSymbol)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }

            // Station name — tappable if multiple stations
            if entry.stationCount > 1 {
                Button(intent: SwitchStationIntent()) {
                    HStack(spacing: 3) {
                        Text(entry.stationName ?? "Station")
                            .font(.caption.weight(.bold))
                            .foregroundStyle(.primary)
                            .lineLimit(1)
                        Text("\(entry.stationIndex + 1)/\(entry.stationCount)")
                            .font(.system(size: 9, weight: .medium))
                            .foregroundStyle(.secondary)
                    }
                }
                .buttonStyle(.plain)
            } else {
                Text(entry.stationName ?? "Station")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(.primary)
                    .lineLimit(1)
            }

            Spacer()

            Button(intent: RefreshIntent()) {
                Image(systemName: "arrow.clockwise")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
        }
    }

    private func widgetDepartureRow(_ dep: WidgetDeparture, isFavourite: Bool) -> some View {
        let deepLink = URL(string: "traintime://track?destination=\(dep.destination.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? "")&timestamp=\(dep.departureTimestamp)")

        return Link(destination: deepLink ?? URL(string: "traintime://")!) {
            HStack(spacing: 4) {
                // Minutes
                Text(dep.minutesText(at: entry.date))
                    .font(.system(.caption, design: .rounded, weight: .bold))
                    .foregroundStyle(minutesColor(dep))
                    .frame(width: 30, alignment: .trailing)

                // Delay
                if dep.delay > 0 {
                    Text("+\(dep.delay)")
                        .font(.system(size: 8, weight: .medium))
                        .foregroundStyle(AppColors.delay)
                }

                // Line or platform (medium/large only)
                if family != .systemSmall {
                    if !dep.lineNumber.isEmpty {
                        Text(dep.lineNumber)
                            .font(.system(.caption2, weight: .medium))
                            .foregroundStyle(AppColors.platform)
                            .frame(width: 24, alignment: .leading)
                    } else if !dep.platform.isEmpty {
                        Text("P\(dep.platform)")
                            .font(.caption2)
                            .foregroundStyle(dep.platformChanged ? .red : AppColors.platform)
                            .frame(width: 24, alignment: .leading)
                    }
                }

                // Destination
                Text(dep.destination)
                    .font(.caption)
                    .foregroundStyle(.primary)
                    .lineLimit(1)
                    .truncationMode(.tail)

                Spacer(minLength: 0)

                if isFavourite {
                    Image(systemName: "star.fill")
                        .font(.system(size: 8))
                        .foregroundStyle(AppColors.favouriteStar)
                }
            }
            .padding(.vertical, 2)
            .background {
                if isFavourite {
                    RoundedRectangle(cornerRadius: 4)
                        .fill(AppColors.favouriteBackground)
                }
            }
        }
    }

    private func minutesColor(_ dep: WidgetDeparture) -> Color {
        if dep.isGone(at: entry.date) { return .secondary }
        if dep.minutesUntil(at: entry.date) <= 2 { return AppColors.minutesNow }
        return AppColors.minutesSoon
    }

    private var maxDepartureRows: Int {
        switch family {
        case .systemSmall: return 2
        case .systemMedium: return 4
        case .systemLarge: return 8
        default: return 4
        }
    }
}
