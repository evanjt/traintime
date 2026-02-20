import SwiftUI

struct StationView: View {
    let stationName: String
    let walkInfo: String
    let departures: [Departure]?
    let isLoading: Bool

    var body: some View {
        VStack(spacing: 2) {
            // Walk info
            Text(walkInfo)
                .font(.system(size: 12))
                .foregroundColor(AppColors.walkInfo)
                .lineLimit(1)

            // Station name — bold, uppercase, auto-shrinks
            Text(stationName.uppercased())
                .font(.system(.title3, design: .default, weight: .bold))
                .foregroundColor(.white)
                .minimumScaleFactor(0.5)
                .lineLimit(1)

            // Separator
            AppColors.separator
                .frame(height: 1)
                .padding(.horizontal, 8)
                .padding(.vertical, 2)

            if let departures = departures {
                if departures.isEmpty {
                    Spacer()
                    Text("No departures")
                        .font(.callout)
                        .foregroundColor(AppColors.bodyStatus)
                    Spacer()
                } else {
                    ForEach(departures) { departure in
                        DepartureRowView(departure: departure)
                    }
                    Spacer(minLength: 0)
                }
            } else if isLoading {
                Spacer()
                Text("Loading...")
                    .font(.callout)
                    .foregroundColor(AppColors.bodyStatus)
                Spacer()
            }
        }
    }
}
