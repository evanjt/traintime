import SwiftUI

struct DepartureRowView: View {
    let departure: Departure
    var onTap: (() -> Void)? = nil

    var body: some View {
        Button(action: { onTap?() }) {
            HStack(spacing: 6) {
                // Minutes
                Text(departure.minutesText)
                    .font(.system(.body, design: .rounded, weight: .bold))
                    .foregroundStyle(minutesColor)
                    .frame(width: 42, alignment: .trailing)

                // Delay
                if departure.delay > 0 && !departure.isGone {
                    Text("+\(departure.delay)")
                        .font(.caption2)
                        .foregroundStyle(AppColors.delay)
                        .frame(width: 22, alignment: .leading)
                } else {
                    Spacer().frame(width: 22)
                }

                // Platform
                if !departure.platform.isEmpty {
                    platformBadge
                        .frame(width: 30, alignment: .leading)
                } else {
                    Spacer().frame(width: 30)
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
            .padding(.horizontal, 6)
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
