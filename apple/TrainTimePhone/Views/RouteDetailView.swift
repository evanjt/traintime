import SwiftUI

/// The train connections of a saved route, current one highlighted. Walk legs
/// are omitted: the app tracks trains between stops, not walking. Each trackable
/// connection has a departure-reminder switch and a "Track now". Platforms come
/// from the live board when close to departure. Presented as a sheet from the
/// queued-route chip. Port of android ui/pending/RouteDetailSheet.kt.
struct RouteDetailView: View {
    @ObservedObject var viewModel: PhoneViewModel
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
        NavigationStack {
            Group {
                if let route = routeStore.pending {
                    content(route)
                } else {
                    // Route cleared while open (departed or discarded), so close.
                    Color.clear.onAppear { dismiss() }
                }
            }
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }

    private func content(_ route: PendingRoute) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 4) {
                Text("Route to \(route.finalDestination)")
                    .font(.title2.weight(.semibold))
                Text("Each connection can send a reminder before it departs. Turn one off, or track any now.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .padding(.bottom, 8)
                ForEach(Array(route.legs.enumerated()), id: \.offset) { index, leg in
                    if leg.type == .ride {
                        rideRow(route, leg, index: index)
                    }
                }
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 16)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    @ViewBuilder
    private func rideRow(_ route: PendingRoute, _ leg: RouteLeg, index: Int) -> some View {
        let line = "\(leg.category ?? "")\(leg.lineNumber ?? "")"
        let isCurrent = index == route.cursor
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                if !line.isEmpty {
                    Text(line)
                        .font(.system(size: 13, weight: .bold))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 7)
                        .padding(.vertical, 2)
                        .background(RoundedRectangle(cornerRadius: 6).fill(AppColors.linePill(line, mode: viewModel.currentMode)))
                }
                VStack(alignment: .leading, spacing: 2) {
                    Text("\(leg.originName) to \(leg.destName)")
                        .fontWeight(.medium)
                        .lineLimit(1)
                    let times = "\(Self.hhmm(leg.depTs)) to \(Self.hhmm(leg.arrTs))"
                    Text(viewModel.routeLegPlatforms[index].map { "\(times) · platform \($0)" } ?? times)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                if leg.isTrackable {
                    VStack(spacing: 2) {
                        Text("Remind")
                            .font(.system(size: 10))
                            .foregroundStyle(.secondary)
                        Toggle("", isOn: Binding(
                            get: { !route.isLegMuted(index) },
                            set: { on in viewModel.setLegMuted(index, muted: !on) }
                        ))
                        .labelsHidden()
                    }
                } else {
                    Text("Outside Switzerland")
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                }
            }
            if leg.isTrackable {
                HStack {
                    Text(isCurrent ? "Next connection" : "")
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                    Spacer()
                    Button("Track now") {
                        viewModel.trackLeg(index)
                        dismiss()
                    }
                }
            }
        }
        .padding(8)
        .background(RoundedRectangle(cornerRadius: 10).fill(isCurrent ? Color(uiColor: .secondarySystemBackground) : Color.clear))
    }
}
