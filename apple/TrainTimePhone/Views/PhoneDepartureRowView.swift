import SwiftUI

struct PhoneDepartureRowView: View {
    let departure: Departure
    var isFavourite: Bool = false
    var mode: TransportMode = .train
    var isSelected: Bool = false
    var onTap: (() -> Void)? = nil

    var body: some View {
        Button(action: { if departure.isSelectable { onTap?() } }) {
            HStack(spacing: 8) {
                // A cancelled train will never run: the label takes the minutes and
                // delay slots, and the rest of the row is dimmed with the destination struck.
                if departure.cancelled {
                    Text("Cancelled")
                        .font(.system(.caption, design: .rounded, weight: .medium))
                        .foregroundStyle(.white)
                        .lineLimit(1)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(RoundedRectangle(cornerRadius: 6).fill(AppColors.delay))
                        .frame(width: 94, alignment: .trailing)
                } else {
                    // Minutes
                    Text(departure.minutesText)
                        .font(.system(.title3, design: .rounded, weight: .bold))
                        .minimumScaleFactor(0.8)
                        .lineLimit(1)
                        .foregroundStyle(minutesColor)
                        .frame(width: 50, alignment: .trailing)
                }

                // Delay
                if departure.cancelled {
                    EmptyView()
                } else if departure.delay > 0 && !departure.isGone {
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
                lineBadge

                // Destination
                Text(departure.destination)
                    .font(.body.weight(.medium))
                    .foregroundStyle(departure.isSelectable ? .primary : .secondary)
                    .strikethrough(departure.cancelled)
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
                if departure.isSelectable {
                    Image(systemName: "chevron.right")
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                }
            }
            .padding(.vertical, 14)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }

    private var minutesColor: Color {
        if departure.isGone { return .secondary }
        if departure.minutesUntil <= 2 { return AppColors.minutesNow }
        return AppColors.minutesSoon
    }

    // A fixed-width pill, so destinations align down the column; a row with
    // no line keeps the slot empty, a gone or cancelled one drops the fill.
    private var lineBadge: some View {
        let filled = departure.isSelectable && !departure.lineNumber.isEmpty
        return LinePill(
            departure.lineNumber,
            fill: filled ? AppColors.linePill(departure.lineNumber, mode: mode) : .clear,
            fontSize: 12, relativeTo: .caption,
            textColor: departure.isSelectable ? .white : .secondary
        )
    }

}
