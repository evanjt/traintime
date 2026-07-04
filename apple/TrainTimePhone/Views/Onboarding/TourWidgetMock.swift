import SwiftUI

// A static look-alike of the home-screen widget's active view, shown inside the tour (WidgetKit
// can't render into the app). Colours reuse AppColors so it tracks the app's theme. Peer of the
// Android TourWidgetMock.kt.
struct TourWidgetMock: View {
    private struct MockRow {
        let minutes: String
        let delay: Int
        let line: String
        let destination: String
        let soon: Bool
        let favourite: Bool
    }

    private let rows: [MockRow] = [
        MockRow(minutes: "4'", delay: 0, line: "IC1", destination: "Zürich HB", soon: true, favourite: true),
        MockRow(minutes: "6'", delay: 3, line: "IC8", destination: "Brig", soon: false, favourite: false),
        MockRow(minutes: "9'", delay: 0, line: "IR15", destination: "Luzern", soon: false, favourite: false),
    ]

    var body: some View {
        VStack(spacing: 4) {
            HStack(spacing: 6) {
                Text("Train").font(.system(size: 13, weight: .medium)).foregroundStyle(AppColors.platform)
                Text("Bern Bahnhof").font(.system(size: 14, weight: .bold)).lineLimit(1)
                    .frame(maxWidth: .infinity, alignment: .leading)
                Image(systemName: "star.fill").font(.system(size: 11)).foregroundStyle(AppColors.favouriteStar)
                Image(systemName: "arrow.clockwise").font(.system(size: 12)).foregroundStyle(.secondary)
            }
            Divider()
            ForEach(Array(rows.enumerated()), id: \.offset) { index, row in
                widgetRow(row)
                if row.favourite {
                    Rectangle().fill(AppColors.favouriteSeparator).frame(height: 2)
                }
            }
        }
        .padding(12)
        .frame(width: 260)
        .background(RoundedRectangle(cornerRadius: 16).fill(Color(uiColor: .systemBackground)))
    }

    private func widgetRow(_ row: MockRow) -> some View {
        HStack(spacing: 6) {
            Text(row.minutes)
                .font(.system(size: 18, weight: .bold))
                .foregroundStyle(row.soon ? AppColors.minutesNow : AppColors.minutesSoon)
                .frame(width: 34, alignment: .leading)
            if row.delay > 0 {
                Text("+\(row.delay)")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 5).padding(.vertical, 1)
                    .background(Capsule().fill(AppColors.delay))
            }
            Text(row.line)
                .font(.system(size: 12, weight: .bold))
                .foregroundStyle(.white)
                .padding(.horizontal, 5).padding(.vertical, 1)
                .background(RoundedRectangle(cornerRadius: 5).fill(AppColors.linePill(row.line, mode: .train)))
            Text(row.destination)
                .font(.system(size: 14)).lineLimit(1)
                .frame(maxWidth: .infinity, alignment: .leading)
            if row.favourite {
                Image(systemName: "star.fill").font(.system(size: 11)).foregroundStyle(AppColors.favouriteStar)
            }
        }
        .padding(.horizontal, 4).padding(.vertical, 4)
        .background(
            row.favourite
                ? RoundedRectangle(cornerRadius: 6).fill(AppColors.favouriteBackground)
                : RoundedRectangle(cornerRadius: 6).fill(.clear)
        )
    }
}

// iOS can't add a widget programmatically (no WidgetKit API). Guide the user instead.
struct AddWidgetHint: View {
    var body: some View {
        Text("Add the TrainTime widget from your home screen.")
            .font(.footnote)
            .foregroundStyle(.secondary)
            .multilineTextAlignment(.center)
    }
}
