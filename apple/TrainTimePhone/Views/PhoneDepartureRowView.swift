import SwiftUI

struct PhoneDepartureRowView: View {
    let departure: Departure
    var onTap: (() -> Void)? = nil

    var body: some View {
        Button(action: { onTap?() }) {
            HStack(spacing: 8) {
                // Minutes
                Text(departure.minutesText)
                    .font(departure.minutesUntil <= 0
                        ? .system(.subheadline, design: .rounded, weight: .bold)
                        : .system(.title3, design: .rounded, weight: .bold))
                    .foregroundStyle(minutesColor)
                    .frame(width: 50, alignment: .trailing)

                // Delay
                Text(departure.delay > 0 && !departure.isGone ? "+\(departure.delay)" : "")
                    .font(.system(.caption, design: .rounded, weight: .medium))
                    .foregroundStyle(AppColors.delay)
                    .frame(width: 24, alignment: .leading)

                // Line number or platform
                if !departure.lineNumber.isEmpty {
                    lineBadge
                        .frame(width: 36, alignment: .leading)
                } else if !departure.platform.isEmpty {
                    platformBadge
                        .frame(width: 36, alignment: .leading)
                } else {
                    Spacer().frame(width: 36)
                }

                // Destination
                Text(departure.destination)
                    .font(.body)
                    .foregroundStyle(departure.isGone ? .secondary : .primary)
                    .lineLimit(1)
                    .truncationMode(.tail)

                Spacer(minLength: 0)

                // Chevron
                if !departure.isGone {
                    Image(systemName: "chevron.right")
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                }
            }
            .padding(.vertical, 6)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(departure.isGone)
    }

    private var minutesColor: Color {
        if departure.isGone { return .secondary }
        if departure.minutesUntil <= 2 { return AppColors.minutesNow }
        return AppColors.minutesSoon
    }

    @ViewBuilder
    private var lineBadge: some View {
        Text(departure.lineNumber)
            .font(.system(.caption, weight: .medium))
            .foregroundStyle(departure.isGone ? .secondary : AppColors.platform)
    }

    @ViewBuilder
    private var platformBadge: some View {
        let text = "P\(departure.platform)"
        if departure.isGone {
            Text(text)
                .font(.caption)
                .foregroundStyle(.secondary)
        } else if departure.platformChanged {
            Text(text)
                .font(.system(.caption, weight: .medium))
                .foregroundStyle(.white)
                .padding(.horizontal, 4)
                .padding(.vertical, 2)
                .background(Capsule().fill(AppColors.platformChanged))
        } else {
            Text(text)
                .font(.caption)
                .foregroundStyle(AppColors.platform)
        }
    }
}
