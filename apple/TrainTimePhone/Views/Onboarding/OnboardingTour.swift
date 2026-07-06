import SwiftUI

// Reports a spotlight target's frame in the "tour" coordinate space, the SwiftUI peer of
// Android's onGloballyPositioned { boundsInRoot() }.
private struct TourTargetPreference: PreferenceKey {
    static var defaultValue: CGRect?
    static func reduce(value: inout CGRect?, nextValue: () -> CGRect?) {
        if let next = nextValue() { value = next }
    }
}

private extension View {
    func tourTarget() -> some View {
        background(
            GeometryReader { geo in
                Color.clear.preference(key: TourTargetPreference.self, value: geo.frame(in: .named("tour")))
            }
        )
    }
}

private enum StationHighlight { case list, modeChips, trackRow, favRow }

// Guided coach-mark walkthrough. Each step renders a real, mocked app surface and spotlights one
// feature with an anchored callout. All state is local (mode/favourites/pins live only here), so
// toggling things in the tour never touches the user's real data. onFinish fires on Done AND Skip.
// Peer of the Android OnboardingTour.kt.
struct OnboardingTour: View {
    let onFinish: () -> Void

    @State private var stepIndex = 0
    @State private var trackingActive = false
    @State private var mode: TransportMode = .train
    @State private var favourites: Set<String> = []
    @State private var pinnedIds: Set<String> = []
    @State private var targetRect: CGRect?

    private let base = Int(Date().timeIntervalSince1970)
    private var departures: [Departure] { TourMockData.departures(base: base, mode: mode) }
    private var step: TourStep { tourSteps[stepIndex] }

    private func favKey(_ d: Departure) -> String { "\(d.lineNumber)|\(d.destination)" }
    private func isFav(_ d: Departure) -> Bool { favourites.contains(favKey(d)) }

    private func goNext() {
        targetRect = nil
        if step.stage == .track && !trackingActive {
            trackingActive = true
        } else if step.stage == .favourite && favourites.isEmpty {
            // First Next on the favourite step stars the line (so the user sees it land above
            // and below) before advancing.
            if let d = departures.first(where: { $0.lineNumber == TourMockData.favouriteLine }) {
                toggleFavourite(d)
            }
        } else if stepIndex < tourSteps.count - 1 {
            if step.stage == .track { trackingActive = false }
            // Leaving the mode step returns the board to trains so the track and
            // favourite steps find IC1 and IR15.
            if step.stage == .mode { mode = .train }
            stepIndex += 1
        } else {
            onFinish()
        }
    }

    private func goBack() {
        targetRect = nil
        if step.stage == .track && trackingActive {
            trackingActive = false
        } else if step.stage == .favourite && !favourites.isEmpty {
            favourites.removeAll()
        } else if stepIndex > 0 {
            trackingActive = false
            if step.stage == .mode { mode = .train }
            stepIndex -= 1
        }
    }

    private func toggleFavourite(_ d: Departure) {
        // Clear the spotlight so it re-anchors (or clears) for the new favourite state.
        targetRect = nil
        let key = favKey(d)
        if favourites.contains(key) { favourites.remove(key) } else { favourites.insert(key) }
    }

    var body: some View {
        GeometryReader { geo in
            ZStack {
                Color(uiColor: .systemBackground)

                surface

                SpotlightScrim(hole: targetRect, accent: AppColors.platform)

                callout(height: geo.size.height)
                    .padding(16)
            }
            .coordinateSpace(name: "tour")
            .onPreferenceChange(TourTargetPreference.self) { targetRect = $0 }
        }
    }

    @ViewBuilder private var surface: some View {
        switch step.stage {
        case .nearby:
            stationSurface(.list)
        case .mode:
            stationSurface(.modeChips)
        case .track:
            if trackingActive { trackingSurface } else { stationSurface(.trackRow) }
        case .favourite:
            stationSurface(.favRow)
        case .pin:
            pickerSurface
        case .settings:
            settingsSurface
        case .share:
            shareSurface
        case .route:
            routeSurface
        case .watch:
            watchSurface
        case .widget:
            widgetSurface
        }
    }

    @ViewBuilder private func callout(height: CGFloat) -> some View {
        // Place below unless the target sits low, so a tall target (eg. the full departures list)
        // keeps the bubble at the bottom instead of overlapping the interface up top.
        let atBottom = (targetRect?.minY).map { $0 < height * 0.55 } ?? true
        let bodyText: String = {
            if step.stage == .track && trackingActive { return tourTrackDetailBody }
            if step.stage == .favourite && !favourites.isEmpty { return tourFavouriteDetailBody }
            return step.body
        }()
        let nextLabel = stepIndex == tourSteps.count - 1 ? "Done" : "Next"
        // The track and favourite steps each expand into a second page (live tracking /
        // starred detail), so both sub-pages carry their own progress dot.
        let trackStep = tourSteps.firstIndex(where: { $0.stage == .track }) ?? 0
        let favStep = tourSteps.firstIndex(where: { $0.stage == .favourite }) ?? 0
        let dotTotal = tourSteps.count + 2
        let dotIndex: Int = {
            var index = stepIndex
            if stepIndex > trackStep || (stepIndex == trackStep && trackingActive) { index += 1 }
            if stepIndex > favStep || (stepIndex == favStep && !favourites.isEmpty) { index += 1 }
            return index
        }()
        let bubble = CalloutBubble(
            title: step.title, message: bodyText, index: dotIndex, total: dotTotal,
            caretUp: atBottom, nextLabel: nextLabel, onBack: goBack, onSkip: onFinish, onNext: goNext
        )
        VStack {
            if atBottom { Spacer(); bubble } else { bubble; Spacer() }
        }
    }

    // MARK: - Surfaces

    private func stationSurface(_ highlight: StationHighlight) -> some View {
        let favDeps = departures.filter { isFav($0) }
        return VStack(spacing: 0) {
            HStack {
                PhoneModePickerView(
                    availableModes: [.train, .bus, .tram],
                    currentMode: mode,
                    onSelect: highlight == .modeChips ? { mode = $0 } : { _ in }
                )
                .modifier(ConditionalTarget(active: highlight == .modeChips))
                Spacer()
                Image(systemName: "location.fill").font(.system(size: 16)).foregroundStyle(AppColors.ahead)
                Image(systemName: "gearshape").font(.system(size: 18)).foregroundStyle(.secondary).padding(.leading, 8)
            }
            .padding(.horizontal, 16).padding(.top, 8)

            HStack(spacing: 4) {
                Text(TourMockData.stationName).font(.title.weight(.bold)).lineLimit(1)
                Image(systemName: "chevron.down").foregroundStyle(.secondary)
            }
            .padding(.top, 10)
            Text(GeoUtils.formatWalkInfo(distanceMeters: 260))
                .font(.system(size: 13)).foregroundStyle(.secondary)
                .padding(.top, 2).padding(.bottom, 8)

            ScrollView {
                VStack(spacing: 0) {
                    ForEach(favDeps) { d in
                        PhoneDepartureRowView(departure: d, isFavourite: true, mode: mode)
                    }
                    if !favDeps.isEmpty {
                        Rectangle().fill(AppColors.favouriteSeparator).frame(height: 2)
                            .padding(.horizontal, 16).padding(.vertical, 4)
                    }
                    ForEach(Array(departures.enumerated()), id: \.element.id) { index, d in
                        let isTarget: Bool = {
                            switch highlight {
                            case .trackRow: return d.lineNumber == TourMockData.trackLine
                            // Spotlight the favourite row only until it's starred; afterwards the
                            // line shows above and below with no dim, so both are visible.
                            case .favRow: return d.lineNumber == TourMockData.favouriteLine && favourites.isEmpty
                            case .list, .modeChips: return false
                            }
                        }()
                        row(d, isTarget: isTarget, highlight: highlight)
                        if index < departures.count - 1 {
                            Divider().padding(.horizontal, 16)
                        }
                    }
                }
            }
            .background(RoundedRectangle(cornerRadius: 20).fill(Color(uiColor: .secondarySystemBackground)))
            .padding(.horizontal, 12).padding(.bottom, 12)
            .modifier(ConditionalTarget(active: highlight == .list))
        }
    }

    @ViewBuilder private func row(_ d: Departure, isTarget: Bool, highlight: StationHighlight) -> some View {
        // Track via tap; favourite via long-press, the real station-screen gesture.
        let tap: (() -> Void)? = (isTarget && highlight == .trackRow) ? { goNext() } : nil
        PhoneDepartureRowView(departure: d, isFavourite: isFav(d), mode: mode, onTap: tap)
            .modifier(ConditionalTarget(active: isTarget))
            .modifier(FavouriteLongPress(active: isTarget && highlight == .favRow) { toggleFavourite(d) })
    }

    private var trackingSurface: some View {
        let focused = TourMockData.focused(base: base)
        return ScrollView {
            VStack(spacing: 0) {
                Text(TourMockData.stationName).font(.system(size: 14)).foregroundStyle(.secondary).padding(.top, 8)
                HStack(spacing: 6) {
                    Text(focused.lineNumber)
                        .font(.system(size: 16, weight: .bold)).foregroundStyle(.white)
                        .padding(.horizontal, 8).padding(.vertical, 3)
                        .background(RoundedRectangle(cornerRadius: 7).fill(AppColors.linePill(focused.lineNumber, mode: mode)))
                    Text(focused.destination).font(.system(size: 22, weight: .bold)).lineLimit(1)
                }
                .padding(.top, 12)
                Text("Platform \(focused.platform)").font(.system(size: 13, weight: .medium))
                    .foregroundStyle(.secondary).padding(.top, 4)

                // A live, looping countdown: the buffer (time left minus walk time) drives the
                // bar and status exactly like the real app, so the user sees it shift from
                // comfortable to tight. The modulo loops it so it never freezes on "Departed".
                TimelineView(.periodic(from: Date(), by: 1)) { context in
                    let now = Int(context.date.timeIntervalSince1970)
                    let remaining = tourTrackRunwaySec - (max(0, now - base) % tourTrackRunwaySec)
                    let minutesLeft = Double(remaining) / 60.0
                    let walkMin = GeoUtils.walkMinutes(distanceMeters: tourTrackDistanceM)
                    let effectBuf = minutesLeft - walkMin
                    VStack(spacing: 0) {
                        Text(tourCountdownText(remaining))
                            .font(.system(size: 56, weight: .bold))
                            .foregroundStyle(minutesLeft < 2 ? AppColors.minutesNow : AppColors.minutesSoon)
                            .padding(.vertical, 8)
                        TrackingBarView(schedBuf: effectBuf, effectBuf: effectBuf, hasGPS: true)
                            .frame(height: 16).padding(.horizontal, 24)
                        Text(tourStatusText(effectBuf)).font(.system(size: 17, weight: .semibold))
                            .foregroundStyle(tourStatusColor(effectBuf)).padding(.top, 12)
                    }
                }
                .padding(.top, 8)
                .frame(maxWidth: .infinity)
                .tourTarget()

                HStack(spacing: 8) {
                    DirectionArrowView(degrees: 45)
                    Text(GeoUtils.formatWalkInfo(distanceMeters: tourTrackDistanceM)).font(.system(size: 14)).foregroundStyle(.secondary)
                }
                .padding(.top, 8)

                FormationDiagramView(formation: TourMockData.formation).padding(.top, 16)
            }
            .padding(.horizontal, 16).padding(.vertical, 24)
            .frame(maxWidth: .infinity)
        }
    }

    private var pickerSurface: some View {
        let pinned = TourMockData.nearbyStations.filter { pinnedIds.contains($0.id ?? "") }
        let rest = TourMockData.nearbyStations.filter { !pinnedIds.contains($0.id ?? "") }
        let stations = pinned + rest
        return VStack(alignment: .leading, spacing: 0) {
            Text("Nearby stations").font(.title3.weight(.bold)).padding(.bottom, 8)
            ForEach(Array(stations.enumerated()), id: \.element.id) { index, station in
                let isPinned = pinnedIds.contains(station.id ?? "")
                let isBern = station.id == TourMockData.stationId
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(station.name ?? "").fontWeight(.medium)
                        Text(station.walkInfo(index: index, total: stations.count))
                            .font(.caption).foregroundStyle(.secondary)
                    }
                    Spacer()
                    Button {
                        if isBern {
                            if isPinned { pinnedIds.remove(station.id ?? "") } else { pinnedIds.insert(station.id ?? "") }
                        }
                    } label: {
                        Image(systemName: isPinned ? "pin.fill" : "pin")
                            .foregroundStyle(isPinned ? AppColors.platform : .secondary)
                    }
                    .buttonStyle(.plain)
                    .modifier(ConditionalTarget(active: isBern))
                }
                .padding(.vertical, 6)
                Divider()
            }
            Spacer()
        }
        .padding(16)
    }

    private var settingsSurface: some View {
        VStack(spacing: 0) {
            Text("Settings").font(.headline).padding(.bottom, 16)
            VStack(alignment: .leading, spacing: 0) {
                Text("Default Mode").font(.system(size: 13)).foregroundStyle(.secondary)
                ForEach([TransportMode.train, .bus, .tram]) { m in
                    Button { mode = m } label: {
                        HStack {
                            Image(systemName: m.sfSymbol).foregroundStyle(.secondary).frame(width: 20)
                            Text(m.label).foregroundStyle(.primary).padding(.leading, 12)
                            Spacer()
                            if mode == m { Image(systemName: "checkmark").foregroundStyle(AppColors.platform) }
                        }
                        .padding(.vertical, 10)
                    }
                    .buttonStyle(.plain)
                }
            }
            .tourTarget()
            Spacer()
        }
        .padding(.horizontal, 20).padding(.vertical, 24)
    }

    // Mock the SBB share sheet handing a trip to TrainTime. Peer of the Android
    // TourShareSurface.
    private var shareSurface: some View {
        VStack(spacing: 10) {
            Spacer()
            Text("From the SBB Mobile app")
                .font(.system(size: 13)).foregroundStyle(.secondary)
            HStack(spacing: 12) {
                Text("Share to").font(.system(size: 14)).foregroundStyle(.secondary)
                Text("TrainTime").font(.headline)
            }
            .padding(16)
            .frame(maxWidth: .infinity)
            .background(RoundedRectangle(cornerRadius: 16).fill(Color(uiColor: .secondarySystemBackground)))
            .tourTarget()
            Text("Your trip opens here, tracked and ready.")
                .font(.system(size: 13)).foregroundStyle(.secondary)
            Spacer()
        }
        .padding(.horizontal, 20).padding(.vertical, 24)
    }

    // Mock a saved route with a couple of legs and on/off labels. Peer of the
    // Android TourRouteSurface.
    private var routeSurface: some View {
        VStack(alignment: .leading, spacing: 14) {
            Spacer()
            VStack(alignment: .leading, spacing: 8) {
                Text("Route to Lausanne").font(.headline)
                tourRouteLeg(line: "IR90", path: "Sion to Lausanne", time: "13:02", tracked: true)
                tourRouteLeg(line: "Walk", path: "Lausanne to gare", time: "", tracked: nil)
                tourRouteLeg(line: "M2", path: "Lausanne to Ouchy", time: "13:31", tracked: false)
            }
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(RoundedRectangle(cornerRadius: 16).fill(Color(uiColor: .secondarySystemBackground)))
            .tourTarget()
            Text("Toggle a connection off to skip its reminder.")
                .font(.system(size: 13)).foregroundStyle(.secondary)
            Spacer()
        }
        .padding(.horizontal, 20).padding(.vertical, 24)
    }

    private func tourRouteLeg(line: String, path: String, time: String, tracked: Bool?) -> some View {
        HStack(spacing: 8) {
            Text(line).font(.system(size: 12)).foregroundStyle(.secondary)
            VStack(alignment: .leading, spacing: 1) {
                Text(path).font(.system(size: 14))
                if !time.isEmpty {
                    Text(time).font(.system(size: 11)).foregroundStyle(.secondary)
                }
            }
            Spacer()
            switch tracked {
            case .some(true): Text("On").font(.system(size: 12)).foregroundStyle(AppColors.platform)
            case .some(false): Text("Off").font(.system(size: 12)).foregroundStyle(.secondary)
            case .none: Text("Walk").font(.system(size: 11)).foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 4)
    }

    private var watchSurface: some View {
        VStack(spacing: 20) {
            Spacer()
            TourWatchCard().tourTarget()
            Spacer()
        }
        .frame(maxWidth: .infinity)
        .padding(.horizontal, 16).padding(.vertical, 24)
    }

    private var widgetSurface: some View {
        VStack(spacing: 24) {
            Spacer()
            TourWidgetMock().tourTarget()
            AddWidgetHint()
            Spacer()
        }
        .frame(maxWidth: .infinity)
        .padding(24)
    }
}

// The watch-step card: a screenshot of each watch app, a sync-capability badge, a store button
// beneath each face, and a mirror summary. On iOS both watches sync. Self-contained so the
// onboarding snapshot test can render it. Peer of the Android TourWatchSurface.
struct TourWatchCard: View {
    var body: some View {
        VStack(spacing: 16) {
            HStack(alignment: .top, spacing: 18) {
                WatchTile(image: "WatchGarmin", name: "Garmin", synced: true) {
                    Link(destination: connectIQStoreURL) {
                        WatchTileButtonLabel(icon: "arrow.up.forward.app", text: "Connect IQ")
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.mini)
                }
                WatchTile(image: "WatchApple", name: "Apple Watch", synced: true) {
                    // Ships embedded in this app, so the button points at the Watch app rather
                    // than a circular App Store link. The caption below carries the meaning if
                    // the scheme ever stops resolving (open just no-ops).
                    Button {
                        UIApplication.shared.open(URL(string: "itms-watchs://")!, options: [:], completionHandler: nil)
                    } label: {
                        WatchTileButtonLabel(icon: "applewatch", text: "Open Watch app")
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.mini)
                }
            }
            Text("The Apple Watch app is included with TrainTime. Install it from the Watch app.")
                .font(.system(size: 12)).foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            Text("Track on your phone and a departure mirrors to a paired watch, which also reads the "
                + "phone's location, handy indoors. The watch icon turns green when it's live.")
                .font(.system(size: 12)).foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(16)
        .background(RoundedRectangle(cornerRadius: 16).fill(Color(uiColor: .secondarySystemBackground)))
    }
}

private struct WatchTileButtonLabel: View {
    let icon: String
    let text: String

    var body: some View {
        HStack(spacing: 4) {
            Image(systemName: icon)
            Text(text).fontWeight(.semibold)
        }
        .font(.system(size: 12))
    }
}

// One watch app: the framed device shot (bezel + bands, reused from the web docs), its name, a
// sync badge and its store button. Shown whole (scaledToFit) so the device reads as a real watch.
private struct WatchTile<Button: View>: View {
    let image: String
    let name: String
    let synced: Bool
    @ViewBuilder let button: Button

    var body: some View {
        VStack(spacing: 8) {
            Image(image)
                .resizable()
                .scaledToFit()
                .frame(height: 150)
            Text(name).font(.system(size: 13, weight: .semibold))
            SyncBadge(synced: synced)
            button
        }
        .frame(maxWidth: .infinity)
    }
}

// Graphical sync-capability chip: green tick when the watch syncs with this phone, grey cross
// when the app installs but can't sync here (eg. an Apple Watch alongside an Android phone).
private struct SyncBadge: View {
    let synced: Bool

    var body: some View {
        HStack(spacing: 4) {
            Image(systemName: synced ? "checkmark.circle.fill" : "xmark.circle.fill")
            Text(synced ? "Syncs live" : "No sync")
        }
        .font(.system(size: 11, weight: .medium))
        .foregroundStyle(synced ? WatchLivenessIndicator.green : Color.secondary)
        .padding(.horizontal, 8).padding(.vertical, 4)
        .background(Capsule().fill((synced ? WatchLivenessIndicator.green : Color.secondary).opacity(0.15)))
    }
}

// Live tracking-demo helpers. Mirror FocusedDeparture.countdownText + the real status logic.
private func tourCountdownText(_ secs: Int) -> String {
    if secs < 5 { return "now" }
    let m = secs / 60, s = secs % 60
    return m < 3 ? String(format: "%d:%02d", m, s) : "\(m) min"
}

private func tourStatusText(_ buffer: Double) -> String {
    // Same status wording as the real tracking screen (PhoneViewModel.trackingStatusText).
    let absBuf = abs(buffer)
    if absBuf < 0.5 { return "On time" }
    let unit = absBuf < 1.5 ? "\(Int(absBuf * 60))s" : "\(Int(absBuf)) min"
    return buffer > 0 ? "\(unit) ahead" : "\(unit) behind"
}

private func tourStatusColor(_ buffer: Double) -> Color {
    if buffer >= 0.5 { return AppColors.ahead }
    if buffer > -0.5 { return AppColors.onTime }
    return AppColors.behind
}

// Adds a long-press handler only to the active favourite target.
private struct FavouriteLongPress: ViewModifier {
    let active: Bool
    let action: () -> Void
    func body(content: Content) -> some View {
        if active {
            content.onLongPressGesture { action() }
        } else {
            content
        }
    }
}

// Applies .tourTarget() only when this element is the active spotlight.
private struct ConditionalTarget: ViewModifier {
    let active: Bool
    func body(content: Content) -> some View {
        if active {
            content.background(
                GeometryReader { geo in
                    Color.clear.preference(key: TourTargetPreference.self, value: geo.frame(in: .named("tour")))
                }
            )
        } else {
            content
        }
    }
}
