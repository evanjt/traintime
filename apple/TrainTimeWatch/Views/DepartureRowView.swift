import SwiftUI

struct DepartureRowView: View {
    let departure: Departure
    var onTap: (() -> Void)? = nil

    var body: some View {
        Button(action: { onTap?() }) {
            HStack(spacing: 2) {
                // Minutes (fixed width, right-aligned)
                Text(departure.minutesText)
                    .font(departure.minutesUntil <= 0
                        ? .system(.caption, design: .rounded, weight: .bold)
                        : .system(.callout, design: .rounded, weight: .bold))
                    .foregroundStyle(minutesColor)
                    .lineLimit(1)
                    .frame(width: 34, alignment: .trailing)

                // Delay (fixed width, always reserved)
                Text(departure.delay > 0 && !departure.isGone ? "+\(departure.delay)" : "")
                    .font(.system(size: 8, weight: .medium, design: .rounded))
                    .foregroundStyle(AppColors.delay)
                    .baselineOffset(4)
                    .frame(width: 14, alignment: .leading)

                // Connection ID
                if !departure.lineNumber.isEmpty {
                    lineBadge
                        .frame(width: 34, alignment: .leading)
                } else {
                    Spacer().frame(width: 34)
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
            .lineLimit(1)
            .minimumScaleFactor(0.7)
    }

}
