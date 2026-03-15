import SwiftUI
import WidgetKit

struct WidgetEntryView: View {
    @Environment(\.widgetFamily) var family
    let entry: DepartureEntry

    var body: some View {
        if entry.isDormant {
            dormantView
        } else {
            activeView
        }
    }

    // MARK: - Dormant View

    @ViewBuilder
    private var dormantView: some View {
        VStack(spacing: 8) {
            if let name = entry.stationName {
                Text(name)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            Spacer()

            Button(intent: RefreshIntent()) {
                Label("Load departures", systemImage: "arrow.clockwise")
                    .font(.caption.weight(.medium))
            }
            .buttonStyle(.bordered)
            .tint(.blue)

            Spacer()
        }
        .padding(12)
    }

    // MARK: - Active View

    @ViewBuilder
    private var activeView: some View {
        VStack(alignment: .leading, spacing: 4) {
            // Station header
            HStack {
                Text(entry.stationName ?? "Station")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(.primary)
                    .lineLimit(1)

                Spacer()

                Button(intent: RefreshIntent()) {
                    Image(systemName: "arrow.clockwise")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
            }

            Divider()

            // Departures
            let maxRows = maxDepartureRows
            let activeDeps = entry.departures.filter { !$0.isGone }.prefix(maxRows)

            if activeDeps.isEmpty {
                Spacer()
                Text("No departures")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity)
                Spacer()
            } else {
                ForEach(Array(activeDeps.enumerated()), id: \.offset) { _, dep in
                    widgetDepartureRow(dep)
                }
                Spacer(minLength: 0)
            }
        }
        .padding(12)
    }

    @ViewBuilder
    private func widgetDepartureRow(_ dep: WidgetDeparture) -> some View {
        let deepLink = URL(string: "traintime://track?destination=\(dep.destination.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? "")&timestamp=\(dep.departureTimestamp)")

        Link(destination: deepLink ?? URL(string: "traintime://")!) {
            HStack(spacing: 4) {
                // Minutes
                Text(dep.minutesText)
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
            }
            .padding(.vertical, 2)
        }
    }

    private func minutesColor(_ dep: WidgetDeparture) -> Color {
        if dep.isGone { return .secondary }
        if dep.minutesUntil <= 2 { return AppColors.minutesNow }
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
