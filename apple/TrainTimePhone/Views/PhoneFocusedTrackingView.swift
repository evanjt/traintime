import SwiftUI
import MapKit
import UIKit

struct PhoneFocusedTrackingView: View {
    @ObservedObject var viewModel: PhoneViewModel
    // A wide window draws its own x beside the board, so Back and Stop are
    // only drawn when tracking takes the whole window.
    var showsNavigation = true
    @State private var showMap = false
    @State private var tripHint: String?

    var body: some View {
        let focused = viewModel.focusedTrain

        ZStack(alignment: .topLeading) {
            ScrollView {
                VStack(spacing: 16) {
                    // Station name
                    Text(viewModel.stationName)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .padding(.top, 8)

                    // Destination + star
                    let platChanged = focused?.platformChanged == true
                    HStack(spacing: 6) {
                        if let f = focused, !f.lineNumber.isEmpty {
                            Text(f.lineNumber)
                                .font(.headline.weight(.bold))
                                .foregroundStyle(.white)
                                .padding(.horizontal, 8)
                                .padding(.vertical, 3)
                                .background(
                                    RoundedRectangle(cornerRadius: 7)
                                        .fill(AppColors.linePill(f.lineNumber, mode: viewModel.currentMode))
                                )
                        }
                        Text(focused?.destination ?? "?")
                            .font(.title2.weight(.bold))
                            .foregroundStyle(platChanged ? AppColors.platformChangedOrange : .primary)
                            .lineLimit(1)
                            .minimumScaleFactor(0.6)
                        Button {
                            viewModel.toggleFavourite()
                        } label: {
                            Image(systemName: viewModel.isFocusedTrainFavourite ? "star.fill" : "star")
                                .font(.system(size: 20))
                                .foregroundStyle(viewModel.isFocusedTrainFavourite ? AppColors.favouriteStar : Color.secondary)
                        }
                        .buttonStyle(.plain)
                    }

                    // On a saved route the header keeps the train's own terminus;
                    // this line carries where the journey actually ends.
                    if let routeDest = focused?.routeDestination, routeDest != focused?.destination {
                        Text("Tracking route to \(routeDest)")
                            .font(.system(size: 13))
                            .foregroundStyle(.secondary)
                    }

                    // Platform + departure time
                    HStack(spacing: 6) {
                        if let plat = focused?.platform, !plat.isEmpty {
                            Text("Platform \(plat)")
                                .font(.system(.caption, weight: .medium))
                                .foregroundStyle(platChanged ? AppColors.platformChangedOrange : .secondary)
                        }
                        if let f = focused {
                            Text("·")
                                .foregroundStyle(.quaternary)
                            Text(Self.formatDepartureTime(f.departureTimestamp))
                                .font(.system(size: 12, weight: .medium, design: .rounded))
                                .monospacedDigit()
                                .foregroundStyle(.tertiary)
                        }
                    }

                    // Countdown + delay
                    HStack(spacing: 8) {
                        Text(focused?.countdownText ?? "–")
                            .font(.system(size: 56, weight: .bold, design: .rounded))
                            .monospacedDigit()
                            .foregroundStyle(countdownColor)

                        if let delay = focused?.delay, delay > 0,
                           let f = focused, f.effectiveMinutesUntil >= -0.5 {
                            Text("+\(delay)")
                                .font(.system(.subheadline, weight: .medium))
                                .foregroundStyle(.white)
                                .padding(.horizontal, 10)
                                .padding(.vertical, 4)
                                .background(Capsule().fill(AppColors.delay))
                        }
                    }
                    .padding(.vertical, 4)

                    // Tracking bar
                    TrackingBarView(
                        schedBuf: viewModel.trackingScheduledBuffer,
                        effectBuf: viewModel.trackingEffectiveBuffer,
                        hasGPS: viewModel.gpsQuality != .unavailable
                    )
                    .frame(height: 16)
                    .padding(.horizontal, 24)

                    // Status
                    Text(viewModel.trackingStatusText)
                        .font(.headline)
                        .foregroundStyle(viewModel.trackingStatusColor)

                    // Walk info + direction
                    HStack(spacing: 8) {
                        DirectionArrowView(degrees: viewModel.directionToStation)

                        Text(GeoUtils.formatWalkInfo(distanceMeters: viewModel.lastWalkDist, walkTimeSeconds: viewModel.lastWalkTime))
                            .font(.subheadline)
                            .foregroundStyle(.secondary)

                        Image(systemName: viewModel.useRoutedDistance ? "point.bottomleft.forward.to.point.topright.scurvepath" : "line.diagonal")
                            .font(.system(size: 14))
                            .foregroundStyle(.tertiary)
                    }
                    .onTapGesture {
                        viewModel.toggleRoutedDistance()
                    }

                    // Onward journey (shared multi-leg route): every remaining leg,
                    // where you change and the next train. Tap any to jump on early.
                    ForEach(viewModel.onwardLegs, id: \.legIndex) { onward in
                        OnwardConnectionCard(onward: onward, mode: viewModel.currentMode) {
                            viewModel.trackLeg(onward.legIndex)
                        }
                        .padding(.top, 8)
                    }

                    // Formation diagram
                    if let formation = viewModel.formation {
                        FormationDiagramView(formation: formation)
                            .padding(.top, 8)
                    }

                    TrackingActionRow(
                        watch: watchAction,
                        sound: viewModel.tripSoundState,
                        buzz: viewModel.tripBuzzState,
                        onMap: { showMap = true },
                        onWatch: {
                            // The watch already tracks this departure; a re-send
                            // would only make it re-enter and buzz again.
                            if !viewModel.watchTrackingFocused {
                                viewModel.sendToPrimaryOrOpen()
                            }
                        },
                        onSound: { showTripHint(viewModel.tapTripSound()) },
                        onSoundHold: { viewModel.holdTripSound() },
                        onBuzz: { showTripHint(viewModel.tapTripBuzz()) },
                        onBuzzHold: { viewModel.holdTripBuzz() }
                    ) {
                        ForEach(viewModel.connectedWatches) { watch in
                            Button("Send to \(watch.name)") {
                                viewModel.sendToWatch(watch)
                            }
                        }
                    }
                    .padding(.top, 8)

                    if watchAction != nil, let status = viewModel.watchSendStatus {
                        Text(status)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 24)
                .frame(maxWidth: .infinity)
            }

            // Back leaves with the session still running (when background
            // tracking is on), Stop ends it. Stop is labelled because an icon
            // opposite Back would read as "close", which Back already does.
            if showsNavigation {
                HStack {
                    Button {
                        viewModel.leaveTracking()
                    } label: {
                        HStack(spacing: 4) {
                            Image(systemName: "chevron.left")
                                .font(.system(size: 16, weight: .medium))
                            Text("Back")
                                .font(.body)
                        }
                        .foregroundStyle(.blue)
                        .padding(.horizontal, 16)
                        .padding(.vertical, 12)
                    }
                    .buttonStyle(.plain)

                    Spacer()

                    Button {
                        viewModel.stopTracking()
                    } label: {
                        Text("Stop")
                            .font(.body)
                            .foregroundStyle(.red)
                            .padding(.horizontal, 16)
                            .padding(.vertical, 12)
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .overlay(alignment: .bottom) {
            if let tripHint {
                Text(tripHint)
                    .font(.subheadline)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 10)
                    .background(Capsule().fill(.regularMaterial))
                    .padding(.horizontal, 24)
                    .padding(.bottom, 16)
                    .transition(.opacity)
            }
        }
        .animation(.easeInOut(duration: 0.2), value: tripHint)
        .onAppear { viewModel.refreshConnectedWatches() }
        .sheet(isPresented: $showMap) {
            PhoneMapView(viewModel: viewModel)
        }
        // Prominent disclosure before the system Always-location prompt.
    }

    private var watchAction: TrackingWatchAction? {
        guard viewModel.primaryWatchLiveness != .hidden else { return nil }
        return TrackingWatchAction(
            trackingHere: viewModel.watchTrackingFocused,
            checking: viewModel.watchChecking,
            liveness: viewModel.primaryWatchLiveness,
            isAppleWatch: viewModel.resolvedPrimaryWatch == .appleWatch)
    }

    private func showTripHint(_ override: Bool?) {
        guard let text = TripMute.tripHint(override) else { tripHint = nil; return }
        tripHint = text
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 2_500_000_000)
            if tripHint == text { tripHint = nil }
        }
    }

    private static func formatDepartureTime(_ timestamp: Int) -> String {
        let date = Date(timeIntervalSince1970: TimeInterval(timestamp))
        let f = DateFormatter()
        f.dateFormat = "HH:mm"
        return f.string(from: date)
    }

    private var countdownColor: Color {
        viewModel.focusedTrain.map(trackingCountdownColour) ?? .primary
    }
}

// Shared by the tracking screen and the card's Peek summary.
func trackingCountdownColour(_ focused: FocusedDeparture) -> Color {
    if focused.effectiveMinutesUntil < -0.5 { return .secondary }
    if focused.minutesUntil < 2.0 { return AppColors.minutesNow }
    return AppColors.minutesSoon
}

/// What the Watch button shows. nil hides it (no watch paired).
struct TrackingWatchAction {
    let trackingHere: Bool
    let checking: Bool
    let liveness: WatchLiveness
    let isAppleWatch: Bool
}

/// The tracking screen's one row of actions: Map, Watch, Sound and Buzz. Tap
/// acts, hold does the longer form: the per-watch menu, or the setting for
/// every trip.
struct TrackingActionRow<WatchMenu: View>: View {
    let watch: TrackingWatchAction?
    let sound: TripMuteState
    let buzz: TripMuteState
    var onMap: () -> Void = {}
    var onWatch: () -> Void = {}
    var onSound: () -> Void = {}
    var onSoundHold: () -> Void = {}
    var onBuzz: () -> Void = {}
    var onBuzzHold: () -> Void = {}
    @ViewBuilder var watchMenu: () -> WatchMenu

    var body: some View {
        // Equal slots, so Sound and Buzz take two together and their hint the width of both.
        TrackingSlots {
            Button(action: onMap) {
                TrackingActionLabel(caption: String(localized: "Map"), colour: AppColors.actionMap) { tint in
                    Image(systemName: "map").foregroundStyle(tint)
                }
            }
            .buttonStyle(.plain)
            .accessibilityLabel(Text("Show on Map"))
            .frame(maxWidth: .infinity)

            if let watch {
                Menu {
                    watchMenu()
                } label: {
                    TrackingActionLabel(
                        caption: watch.trackingHere ? String(localized: "On watch") : String(localized: "Send"),
                        colour: AppColors.lineRegional
                    ) { tint in
                        if watch.checking {
                            ProgressView().controlSize(.small).tint(tint)
                        } else {
                            Image(systemName: watch.isAppleWatch ? "applewatch" : "watch.analog")
                                .foregroundStyle(tint)
                                .overlay(alignment: .topTrailing) {
                                    Circle()
                                        .fill(Self.livenessColour(watch.liveness))
                                        .frame(width: 9, height: 9)
                                        .overlay(Circle().stroke(Color(uiColor: .systemBackground), lineWidth: 1.5))
                                        .offset(x: 5, y: -4)
                                }
                        }
                    }
                } primaryAction: {
                    onWatch()
                }
                .buttonStyle(.plain)
                .accessibilityLabel(Text(watch.trackingHere ? "Tracking on watch" : "Track on watch"))
                .frame(maxWidth: .infinity)
            }

            TrackingHoldBracket {
                TrackingMuteButton(
                    name: String(localized: "Alert sounds"),
                    symbol: "bell", colour: AppColors.actionSound,
                    state: sound, onTap: onSound, onHold: onSoundHold)
                    .frame(maxWidth: .infinity)

                TrackingMuteButton(
                    name: String(localized: "Vibration"),
                    symbol: "iphone.radiowaves.left.and.right", colour: AppColors.lineTram,
                    state: buzz, onTap: onBuzz, onHold: onBuzzHold)
                    .frame(maxWidth: .infinity)
            }
            .layoutValue(key: TrackingSlotSpan.self, value: 2)
        }
        .frame(maxWidth: 400)
    }

    private static func livenessColour(_ liveness: WatchLiveness) -> Color {
        switch liveness {
        case .green: return WatchLivenessIndicator.green
        case .amber: return WatchLivenessIndicator.amber
        case .grey, .hidden: return WatchLivenessIndicator.grey
        }
    }
}

private struct TrackingSlotSpan: LayoutValueKey {
    static let defaultValue = 1
}

/// Lays its children side by side in equal slots, a child taking as many as
/// its span, each top aligned.
private struct TrackingSlots: Layout {
    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let slots = CGFloat(subviews.reduce(0) { $0 + $1[TrackingSlotSpan.self] })
        guard slots > 0 else { return .zero }
        let unit = proposal.width.map { $0 / slots }
            ?? subviews.map { $0.sizeThatFits(.unspecified).width / CGFloat($0[TrackingSlotSpan.self]) }.max() ?? 0
        let height = subviews.map {
            $0.sizeThatFits(ProposedViewSize(width: unit * CGFloat($0[TrackingSlotSpan.self]), height: nil)).height
        }.max() ?? 0
        return CGSize(width: unit * slots, height: height)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let slots = CGFloat(subviews.reduce(0) { $0 + $1[TrackingSlotSpan.self] })
        guard slots > 0 else { return }
        let unit = bounds.width / slots
        var x = bounds.minX
        for subview in subviews {
            let width = unit * CGFloat(subview[TrackingSlotSpan.self])
            subview.place(at: CGPoint(x: x, y: bounds.minY), anchor: .topLeading,
                          proposal: ProposedViewSize(width: width, height: nil))
            x += width
        }
    }
}

/// Sound and Buzz under one bracket with one line saying what a hold does, so
/// the gesture is found without trying it. The bracket and hint are hidden
/// from accessibility: the buttons' hold actions already say it. A large font
/// wraps the hint to a second line rather than clip it.
private struct TrackingHoldBracket<Buttons: View>: View {
    @ViewBuilder let buttons: () -> Buttons

    var body: some View {
        let ink = Color(uiColor: .secondaryLabel)
        VStack(spacing: 0) {
            HStack(alignment: .top, spacing: 0) { buttons() }
            Canvas { context, size in
                let stroke: CGFloat = 1
                let left = stroke / 2
                let right = size.width - stroke / 2
                let bottom = size.height - stroke / 2
                var path = Path()
                path.move(to: CGPoint(x: left, y: 0))
                path.addLine(to: CGPoint(x: left, y: bottom))
                path.addLine(to: CGPoint(x: right, y: bottom))
                path.addLine(to: CGPoint(x: right, y: 0))
                context.stroke(path, with: .color(ink.opacity(0.5)), lineWidth: stroke)
            }
            .frame(height: 6)
            .padding(.horizontal, 20)
            .accessibilityHidden(true)
            Text("Hold to change for every trip")
                .font(.system(size: 11))
                .foregroundStyle(ink.opacity(0.75))
                .multilineTextAlignment(.center)
                .lineLimit(2)
                .frame(maxWidth: .infinity)
                .padding(.top, 3)
                .accessibilityHidden(true)
        }
    }
}

/// Tap decides for this trip, hold for every trip. Plain gestures, not a
/// Button, so a hold never also fires the tap.
private struct TrackingMuteButton: View {
    let name: String
    let symbol: String
    let colour: Color
    let state: TripMuteState
    let onTap: () -> Void
    let onHold: () -> Void

    var body: some View {
        let caption = Self.caption(state.look)
        let usual = TripMute.usualCaption(state)
        TrackingActionLabel(caption: caption, colour: colour, look: state.look, detail: usual) { tint in
            Image(systemName: symbol)
                .foregroundStyle(tint)
                .frame(width: 24, height: 24)
                .overlay {
                    if strikes > 0 {
                        // The halo matches what sits behind the icon: the solid
                        // disc when off, the screen through the ring when muted
                        // for this trip.
                        TrackingStrikes(
                            count: strikes, colour: tint,
                            halo: state.look == .off ? colour : Color(uiColor: .systemBackground))
                    }
                }
        }
        .contentShape(Rectangle())
        .onTapGesture(perform: onTap)
        .onLongPressGesture(minimumDuration: 0.5, perform: onHold)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text("\(name), \(caption), \(usual)"))
        .accessibilityAddTraits(.isButton)
        .accessibilityAction(.default, onTap)
        .accessibilityAction(named: Text("Set for every trip"), onHold)
    }

    private var strikes: Int {
        switch state.look {
        case .on: return 0
        case .thisTrip: return 1
        case .off: return 2
        }
    }

    private static func caption(_ look: TripMuteLook) -> String {
        switch look {
        case .on: return String(localized: "On")
        case .thisTrip: return String(localized: "This trip")
        case .off: return String(localized: "Off")
        }
    }
}

/// Diagonal strikes through the icon, the mark the system uses for a muted
/// bell, drawn so the vibration icon can carry it too. One strike is this
/// trip, two are every trip. A halo cuts the icon either side of each strike
/// so a pair reads as two lines, not one thick one.
private struct TrackingStrikes: View {
    let count: Int
    let colour: Color
    let halo: Color

    var body: some View {
        Canvas { context, size in
            let gap: CGFloat = 3
            let stroke: CGFloat = 2
            // Offset each line along the perpendicular so a pair sits either side of the diagonal.
            let lines: [Path] = (0..<count).map { i in
                let shift = (CGFloat(i) - CGFloat(count - 1) / 2) * gap
                var path = Path()
                path.move(to: CGPoint(x: size.width * 0.12 + shift, y: size.height * 0.12 - shift))
                path.addLine(to: CGPoint(x: size.width * 0.88 + shift, y: size.height * 0.88 - shift))
                return path
            }
            for line in lines {
                context.stroke(line, with: .color(halo), style: StrokeStyle(lineWidth: stroke * 2.2, lineCap: .round))
            }
            for line in lines {
                context.stroke(line, with: .color(colour), style: StrokeStyle(lineWidth: stroke, lineCap: .round))
            }
        }
        .allowsHitTesting(false)
    }
}

/// Each button carries its own colour. Three looks: on is a tinted disc, muted
/// for this trip an outlined ring, off in Settings a solid disc, so the two
/// muted states read apart at a glance.
private struct TrackingActionLabel<Icon: View>: View {
    let caption: String
    let colour: Color
    var look: TripMuteLook = .on
    var detail: String? = nil
    @ViewBuilder let icon: (Color) -> Icon

    var body: some View {
        VStack(spacing: 0) {
            ZStack {
                Circle().fill(fill)
                if look == .thisTrip {
                    Circle().strokeBorder(colour, lineWidth: 1.5)
                }
                icon(tint).font(.system(size: 20))
            }
            .frame(width: 48, height: 48)
            Text(caption)
                .font(.caption)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .lineLimit(2)
                .padding(.top, 4)
            if let detail {
                Text(detail)
                    .font(.system(size: 11))
                    .foregroundStyle(Color(uiColor: .secondaryLabel).opacity(0.75))
                    .multilineTextAlignment(.center)
                    .lineLimit(2)
            }
        }
        .padding(.vertical, 6)
    }

    private var fill: Color {
        switch look {
        case .on: return colour.opacity(0.18)
        case .thisTrip: return .clear
        case .off: return colour
        }
    }

    private var tint: Color {
        switch look {
        case .on, .thisTrip: return colour
        case .off: return Color(uiColor: .systemBackground)
        }
    }
}

// The next ride leg while tracking a shared route: change station, onward line
// pill + destination, and the connection buffer. Tap to jump onto it early.
struct OnwardConnectionCard: View {
    let onward: OnwardConnection
    let mode: TransportMode
    let onTap: () -> Void

    private static let timeFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm"
        formatter.timeZone = TimeZone(identifier: "Europe/Zurich")
        return formatter
    }()

    var body: some View {
        let leg = onward.leg
        let line = "\(leg.category ?? "")\(leg.lineNumber ?? "")"
        Button(action: onTap) {
            VStack(alignment: .leading, spacing: 4) {
                Text("Change at \(onward.changeStation)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                HStack(spacing: 8) {
                    if !line.isEmpty {
                        Text(line)
                            .font(.system(size: 14, weight: .bold))
                            .foregroundStyle(.white)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 2)
                            .background(RoundedRectangle(cornerRadius: 7).fill(AppColors.linePill(line, mode: mode)))
                    }
                    Text(leg.destName)
                        .fontWeight(.medium)
                        .lineLimit(1)
                }
                Text("\(Self.timeFormatter.string(from: Date(timeIntervalSince1970: TimeInterval(leg.depTs)))) · \(onward.changeMinutes) min to change")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(12)
            .background(RoundedRectangle(cornerRadius: 12).fill(Color(uiColor: .secondarySystemBackground)))
        }
        .buttonStyle(.plain)
        .frame(maxWidth: 320)
    }
}

struct PhoneMapView: View {
    @ObservedObject var viewModel: PhoneViewModel
    @Environment(\.dismiss) var dismiss

    var body: some View {
        NavigationStack {
            if let station = viewModel.currentStation,
               let stationCoord = station.coordinate {
                Map {
                    Marker(station.name ?? String(localized: "Station"), coordinate: stationCoord)
                        .tint(.red)
                    UserAnnotation()
                }
                .mapStyle(.standard)
                .mapControls {
                    MapUserLocationButton()
                    MapCompass()
                    MapScaleView()
                }
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button {
                            dismiss()
                        } label: {
                            Image(systemName: "xmark")
                                .fontWeight(.bold)
                        }
                    }
                    ToolbarItem(placement: .bottomBar) {
                        Button {
                            let destination = MKMapItem(placemark: MKPlacemark(coordinate: stationCoord))
                            destination.name = station.name ?? String(localized: "Station")
                            destination.openInMaps(launchOptions: [
                                MKLaunchOptionsDirectionsModeKey: MKLaunchOptionsDirectionsModeWalking
                            ])
                        } label: {
                            Label("Navigate", systemImage: "figure.walk")
                        }
                    }
                }
                .navigationTitle(station.name ?? String(localized: "Station"))
                .navigationBarTitleDisplayMode(.inline)
            } else {
                Text("No station selected")
                    .foregroundStyle(.secondary)
            }
        }
    }
}
