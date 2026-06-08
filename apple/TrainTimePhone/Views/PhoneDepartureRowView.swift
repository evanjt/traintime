import SwiftUI

struct PhoneDepartureRowView: View {
    let departure: Departure
    var isFavourite: Bool = false
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
                if departure.delay > 0 && !departure.isGone {
                    Text("+\(departure.delay)")
                        .font(.system(.caption, design: .rounded, weight: .medium))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 5)
                        .padding(.vertical, 2)
                        .background(Capsule().fill(AppColors.delay))
                        .frame(width: 36, alignment: .leading)
                } else {
                    Spacer().frame(width: 36)
                }

                // Connection ID
                if !departure.lineNumber.isEmpty {
                    lineBadge
                        .frame(width: 36, alignment: .leading)
                } else {
                    Spacer().frame(width: 36)
                }

                // Destination
                Text(departure.destination)
                    .font(.body.weight(.medium))
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
            .padding(.vertical, 14)
            .background(isFavourite ? AppColors.favouriteBackground : Color.clear)
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

}
