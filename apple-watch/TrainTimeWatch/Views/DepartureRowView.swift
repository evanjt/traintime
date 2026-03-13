import SwiftUI

struct DepartureRowView: View {
    let departure: Departure
    var onTap: (() -> Void)? = nil

    var body: some View {
        Button(action: { onTap?() }) {
            HStack(spacing: 4) {
                // Minutes with delay as superscript
                minutesWithDelay
                    .frame(width: 40, alignment: .trailing)

                // Line number (bus/tram) or Platform
                if !departure.lineNumber.isEmpty {
                    lineBadge
                        .frame(width: 28, alignment: .leading)
                } else if !departure.platform.isEmpty {
                    platformBadge
                        .frame(width: 28, alignment: .leading)
                } else {
                    Spacer().frame(width: 28)
                }

                // Destination
                Text(departure.destination)
                    .font(.caption)
                    .foregroundStyle(departure.isGone ? .secondary : .primary)
                    .lineLimit(1)
                    .truncationMode(.tail)

                Spacer(minLength: 0)
            }
            .padding(.vertical, 4)
            .padding(.horizontal, 4)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    @ViewBuilder
    private var minutesWithDelay: some View {
        HStack(alignment: .firstTextBaseline, spacing: 0) {
            Text(departure.minutesText)
                .font(.system(.callout, design: .rounded, weight: .bold))
                .foregroundStyle(minutesColor)
            if departure.delay > 0 && !departure.isGone {
                Text("+\(departure.delay)")
                    .font(.system(size: 9, weight: .medium, design: .rounded))
                    .foregroundStyle(AppColors.delay)
                    .baselineOffset(6)
            }
        }
    }

    private var minutesColor: Color {
        if departure.isGone { return .secondary }
        if departure.minutesUntil <= 2 { return AppColors.minutesNow }
        return AppColors.minutesSoon
    }

    @ViewBuilder
    private var lineBadge: some View {
        Text(departure.lineNumber)
            .font(.system(.caption2, weight: .medium))
            .foregroundStyle(departure.isGone ? .secondary : AppColors.platform)
    }

    @ViewBuilder
    private var platformBadge: some View {
        let text = "P\(departure.platform)"
        if departure.isGone {
            Text(text)
                .font(.caption2)
                .foregroundStyle(.secondary)
        } else if departure.platformChanged {
            Text(text)
                .font(.system(.caption2, weight: .medium))
                .foregroundStyle(.white)
                .padding(.horizontal, 3)
                .padding(.vertical, 1)
                .background(Capsule().fill(AppColors.platformChanged))
        } else {
            Text(text)
                .font(.caption2)
                .foregroundStyle(AppColors.platform)
        }
    }
}
