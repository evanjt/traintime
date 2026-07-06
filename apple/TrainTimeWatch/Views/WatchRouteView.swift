import SwiftUI

/// The train connections of a saved route on the watch, current one highlighted.
/// Walk legs are omitted: the app tracks trains between stops, not walking. Each
/// trackable ride leg has a track/remind toggle and a "Track now". Platforms come
/// from the live board when close to departure. Presented from the queued-route
/// chip. Compact peer of the phone RouteDetailView / android RouteDetailSheet.kt.
struct WatchRouteView: View {
    @ObservedObject var viewModel: TrainTimeViewModel
    @ObservedObject private var routeStore = PendingRouteStore.shared
    @Environment(\.dismiss) private var dismiss

    private static let timeFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm"
        formatter.timeZone = TimeZone(identifier: "Europe/Zurich")
        return formatter
    }()

    private static func hhmm(_ ts: Int) -> String {
        timeFormatter.string(from: Date(timeIntervalSince1970: TimeInterval(ts)))
    }

    var body: some View {
        ScrollView {
            if let route = routeStore.pending {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Route to \(route.finalDestination)")
                        .font(.headline)
                        .lineLimit(2)
                    ForEach(Array(route.legs.enumerated()), id: \.offset) { index, leg in
                        if leg.type == .ride {
                            rideRow(route, leg, index: index)
                        }
                    }
                }
                .padding(.horizontal, 4)
            } else {
                Color.clear.onAppear { dismiss() }
            }
        }
    }

    @ViewBuilder
    private func rideRow(_ route: PendingRoute, _ leg: RouteLeg, index: Int) -> some View {
        let line = "\(leg.category ?? "")\(leg.lineNumber ?? "")"
        let isCurrent = index == route.cursor
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 6) {
                if !line.isEmpty {
                    Text(line)
                        .font(.system(size: 12, weight: .bold))
                        .foregroundStyle(AppColors.linePill(line, mode: viewModel.currentMode))
                }
                VStack(alignment: .leading, spacing: 1) {
                    Text("\(leg.originName) to \(leg.destName)")
                        .font(.system(size: 13, weight: .medium))
                        .lineLimit(1)
                    let times = "\(Self.hhmm(leg.depTs)) to \(Self.hhmm(leg.arrTs))"
                    Text(viewModel.routeLegPlatforms[index].map { "\(times) · platform \($0)" } ?? times)
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                }
                Spacer()
            }
            if leg.isTrackable {
                Toggle(isOn: Binding(
                    get: { !route.isLegMuted(index) },
                    set: { on in viewModel.setLegMuted(index, muted: !on) }
                )) {
                    Text(isCurrent ? "Track · remind" : "Remind")
                        .font(.system(size: 11))
                }
                Button {
                    viewModel.trackLeg(index)
                    dismiss()
                } label: {
                    Text("Track now").font(.system(size: 12))
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
            } else {
                Text("Outside Switzerland")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
            }
        }
        .padding(6)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(isCurrent ? Color.white.opacity(0.12) : Color.clear)
        )
    }
}
