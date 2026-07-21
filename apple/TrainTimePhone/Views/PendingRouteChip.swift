import SwiftUI

/// Queued shared route: destination, departure countdown, discard. Tap runs
/// the resume check (prompts when the train is on the board). Port of
/// android ui/pending/PendingRouteChip.kt.
struct PendingRouteChip: View {
    let route: PendingRoute
    let plan: NotifyPlan?
    let onTap: () -> Void
    let onDismiss: () -> Void

    @State private var confirmDiscard = false
    @State private var now = Int(Date().timeIntervalSince1970)

    private let ticker = Timer.publish(every: 30, on: .main, in: .common).autoconnect()

    private static let timeFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm"
        formatter.timeZone = TimeZone(identifier: "Europe/Zurich")
        return formatter
    }()

    private var subtitle: String {
        guard let leg = route.currentLeg else { return "" }
        let line = "\(leg.category ?? "")\(leg.lineNumber ?? "")"
        let depTime = Self.timeFormatter.string(from: Date(timeIntervalSince1970: TimeInterval(leg.depTs)))
        let mins = max(0, (leg.depTs - now) / 60)
        let countdown = mins >= 60 ? String(localized: "in \(mins / 60) h \(mins % 60)") : String(localized: "in \(mins) min")
        return String(localized: "\(line) departs \(depTime) · \(countdown)")
    }

    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text("Route to \(route.finalDestination)")
                    .font(.subheadline.weight(.semibold))
                Text(subtitle)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                if let plan, plan.notifyTs > now {
                    let mins = (plan.notifyTs - now) / 60
                    if let walk = plan.walkMin {
                        // Colour the calculated walk time and the fixed buffer
                        // distinctly, so "in \(mins) min" isn't read as their sum.
                        (Text("Notified in \(mins) min").foregroundColor(AppColors.ahead)
                            + Text("  (~")
                            + Text("\(walk) min walk").foregroundColor(AppColors.platform)
                            + Text(" + ")
                            + Text("\(plan.bufferMin) min buffer").foregroundColor(AppColors.amber)
                            + Text(")"))
                            .font(.caption)
                    } else {
                        Text("You'll be notified in \(mins) min")
                            .font(.caption)
                            .foregroundStyle(AppColors.ahead)
                    }
                }
            }
            Spacer()
            Button {
                confirmDiscard = true
            } label: {
                Image(systemName: "xmark")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .padding(8)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 12))
        .padding(.horizontal, 12)
        .contentShape(Rectangle())
        .onTapGesture(perform: onTap)
        .onReceive(ticker) { _ in now = Int(Date().timeIntervalSince1970) }
        .confirmationDialog(
            "Discard saved route?",
            isPresented: $confirmDiscard,
            titleVisibility: .visible
        ) {
            Button("Discard", role: .destructive, action: onDismiss)
            Button("Keep", role: .cancel) {}
        } message: {
            Text("The route to \(route.finalDestination) will be forgotten.")
        }
    }
}
