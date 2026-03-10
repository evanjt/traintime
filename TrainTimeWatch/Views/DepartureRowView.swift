import SwiftUI

struct DepartureRowView: View {
    let departure: Departure
    var isHighlighted: Bool = false
    var onTap: (() -> Void)? = nil

    var body: some View {
        Button(action: { onTap?() }) {
            HStack(spacing: 0) {
                // Left accent bar when highlighted
                if isHighlighted {
                    AppColors.selectionAccent
                        .frame(width: 3)
                        .padding(.vertical, 1)
                }

                // Minutes column — fixed width, right-aligned
                Text(departure.minutesText)
                    .font(.system(.body, design: .default, weight: .bold))
                    .foregroundColor(minutesColor)
                    .frame(width: 48, alignment: .trailing)

                // Delay column
                if departure.delay > 0 && !departure.isGone {
                    Text("+\(departure.delay)")
                        .font(.caption2)
                        .foregroundColor(AppColors.delay)
                        .frame(width: 24, alignment: .leading)
                } else {
                    Spacer().frame(width: 24)
                }

                // Platform column
                if !departure.platform.isEmpty {
                    platformView
                        .frame(width: 30, alignment: .leading)
                } else {
                    Spacer().frame(width: 30)
                }

                // Destination
                Text(departure.destination)
                    .font(.caption)
                    .foregroundColor(departure.isGone ? AppColors.minutesGone : .white)
                    .lineLimit(1)
                    .truncationMode(.tail)
            }
            .padding(.vertical, 2)
            .background(isHighlighted ? AppColors.selectionHighlight : Color.clear)
        }
        .buttonStyle(.plain)
    }

    private var minutesColor: Color {
        if departure.isGone { return AppColors.minutesGone }
        if departure.minutesUntil <= 2 { return AppColors.minutesNow }
        return AppColors.minutesSoon
    }

    @ViewBuilder
    private var platformView: some View {
        let text = "P\(departure.platform)"
        if departure.isGone {
            Text(text)
                .font(.caption2)
                .foregroundColor(AppColors.minutesGone)
        } else if departure.platformChanged {
            Text(text)
                .font(.caption2)
                .foregroundColor(AppColors.platformChangedText)
                .padding(.horizontal, 2)
                .background(AppColors.platformChanged)
        } else {
            Text(text)
                .font(.caption2)
                .foregroundColor(AppColors.platform)
        }
    }
}
