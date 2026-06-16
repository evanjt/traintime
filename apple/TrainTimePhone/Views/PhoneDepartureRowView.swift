import SwiftUI

struct PhoneDepartureRowView: View {
    let departure: Departure
    var isFavourite: Bool = false
    var mode: TransportMode = .train
    var onTap: (() -> Void)? = nil

    var body: some View {
        Button(action: { if !departure.isGone { onTap?() } }) {
            HStack(spacing: 8) {
                // Minutes
                Text(departure.minutesText)
                    .font(.system(.title3, design: .rounded, weight: .bold))
                    .minimumScaleFactor(0.8)
                    .lineLimit(1)
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
                        .frame(width: 52, alignment: .leading)
                } else {
                    Spacer().frame(width: 52)
                }

                // Destination
                Text(departure.destination)
                    .font(.body.weight(.medium))
                    .foregroundStyle(departure.isGone ? .secondary : .primary)
                    .lineLimit(1)
                    .truncationMode(.tail)

                Spacer(minLength: 0)

                // Favourite marker
                if isFavourite {
                    Image(systemName: "star.fill")
                        .font(.caption)
                        .foregroundStyle(AppColors.favouriteStar)
                }

                // Chevron
                if !departure.isGone {
                    Image(systemName: "chevron.right")
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                }
            }
            .padding(.vertical, 14)
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
        if departure.isGone {
            Text(departure.lineNumber)
                .font(.system(.caption, weight: .medium))
                .foregroundStyle(.secondary)
        } else {
            Text(departure.lineNumber)
                .font(.system(.caption, weight: .bold))
                .foregroundStyle(.white)
                .padding(.horizontal, 6)
                .padding(.vertical, 2)
                .background(
                    RoundedRectangle(cornerRadius: 6)
                        .fill(AppColors.linePill(departure.lineNumber, mode: mode))
                )
        }
    }

}
