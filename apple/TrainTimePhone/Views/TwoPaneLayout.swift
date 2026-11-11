import SwiftUI

// board and tracking are the compact flow, one screen at a time. sideBySide
// gives each pane a phone's width. card keeps the board readable and lays
// tracking over its right side at one of three stops.
enum PaneMode: Equatable { case board, tracking, sideBySide, card }

enum CardStop: Equatable { case peek, half, full }

// The board spans 0 to boardWidth and tracking, or the hint, starts at
// detailStart. A gap between them is the divider.
struct PaneLayout: Equatable {
    var mode: PaneMode
    var stop: CardStop?
    var boardWidth: CGFloat
    var detailStart: CGFloat
}

// The board's normal width. Two of them side by side need 800.
let boardNormalWidth: CGFloat = 400
// The folded iPhone Duo's width, the widest the board grows beside the Peek card.
let boardPeekMaxWidth: CGFloat = 466
let peekCardMinWidth: CGFloat = 200
// The narrowest window tracking is drawn in full on a compact phone.
let trackingMinWidth: CGFloat = 360
let wideMinWidth: CGFloat = 600
let compactHeight: CGFloat = 480
private let dividerWidth: CGFloat = 1

// The one decision for the window, read from its size so both phones decide
// the same at the same size. A compact window, or a landscape phone too short
// for a second pane, keeps the board, then tracking full-screen, and tracking
// scrolls. Room for two board-width panes splits at the middle. Any other wide
// window is card mode: Peek while nothing is tracked, Half once tracking starts
// unless the user chose another stop. Inactive (state 3) shows the board, or
// the idle split, under its scrim.
func paneLayout(width: CGFloat, height: CGFloat, appState: Int, stop: CardStop? = nil) -> PaneLayout {
    let tracking = appState == 2
    if width < wideMinWidth || height < compactHeight {
        return tracking
            ? PaneLayout(mode: .tracking, stop: nil, boardWidth: 0, detailStart: 0)
            : PaneLayout(mode: .board, stop: nil, boardWidth: width, detailStart: width)
    }
    if width >= 2 * boardNormalWidth {
        let board = ((width - dividerWidth) / 2).rounded(.down)
        return PaneLayout(mode: .sideBySide, stop: nil, boardWidth: board, detailStart: board + dividerWidth)
    }
    let at = tracking ? stop ?? .half : .peek
    let edge: CGFloat
    switch at {
    case .peek: edge = min(boardPeekMaxWidth, width - peekCardMinWidth)
    case .half: edge = width - trackingMinWidth
    case .full: edge = 0
    }
    return PaneLayout(mode: .card, stop: at, boardWidth: edge, detailStart: edge)
}

// The tracking poll, walk distance and train match all read the board's
// station and mode, so the board must not move away while a train is tracked.
func boardPickersLocked(appState: Int) -> Bool { appState == 2 }

enum BoardPicker: Equatable {
    case station
    case mode(TransportMode)
}

enum PickerTap: Equatable { case open, keep, ask }

// A locked picker still takes the tap and asks to stop tracking, so the board
// never looks usable and does nothing. The shown mode is no change to ask about.
func pickerTap(_ picker: BoardPicker, appState: Int, currentMode: TransportMode) -> PickerTap {
    if case .mode(let mode) = picker, mode == currentMode { return .keep }
    return boardPickersLocked(appState: appState) ? .ask : .open
}

// A confirmed picker tap stops the session before the picker opens. The
// session may have ended while the dialog was up, then the picker only opens.
struct PickerPlan: Equatable { let endSession: Bool }

func confirmedPickerTap(appState: Int) -> PickerPlan {
    PickerPlan(endSession: boardPickersLocked(appState: appState))
}

// A board row is the tracked journey when it leaves at the tracked scheduled
// time and carries the same train number. Without a train number on both, the
// destination decides. Twins in one minute differ only by train number.
func isTrackedJourney(_ dep: Departure, focused: FocusedDeparture) -> Bool {
    guard dep.departureTimestamp == focused.departureTimestamp else { return false }
    if let depTrain = dep.trainNumber, let focusedTrain = focused.trainNumber {
        return depTrain == focusedTrain
    }
    return dep.destination == focused.destination
}

// Re-tapping the tracked row on a split board must not restart the session.
func isAlreadyTracked(_ dep: Departure, appState: Int, focused: FocusedDeparture?) -> Bool {
    guard appState == 2, let focused else { return false }
    return isTrackedJourney(dep, focused: focused)
}

enum BoardTap: Equatable { case track, keep, ask }

// A board tap tracks when nothing is tracked and leaves the tracked row alone.
// Any other row would replace a running session, its alerts and its queued
// route, so the board asks first.
func boardTap(_ dep: Departure, appState: Int, focused: FocusedDeparture?) -> BoardTap {
    guard appState == 2, let focused else { return .track }
    return isTrackedJourney(dep, focused: focused) ? .keep : .ask
}

// A confirmed switch ends the tracked session before the asked row starts.
// The session may have ended while the dialog was up, then nothing is ended.
// Nil when the asked row has become the tracked one meanwhile.
struct SwitchPlan: Equatable { let endDepTs: Int? }

func confirmedSwitch(_ dep: Departure, appState: Int, focused: FocusedDeparture?) -> SwitchPlan? {
    switch boardTap(dep, appState: appState, focused: focused) {
    case .track: return SwitchPlan(endDepTs: nil)
    case .keep: return nil
    case .ask: return SwitchPlan(endDepTs: focused?.departureTimestamp)
    }
}

// The row the board marks as tracked. Only state 2 has a session, and only a
// split window shows the board beside it.
func trackedRowIndex(_ rows: [Departure], appState: Int, focused: FocusedDeparture?) -> Int? {
    rows.firstIndex { isAlreadyTracked($0, appState: appState, focused: focused) }
}

// The board row's fill: the selected tint for the tracked row, the favourite
// highlight otherwise. Nil keeps the list's own row background.
func boardRowFill(isSelected: Bool, isFavourite: Bool) -> Color? {
    if isSelected { return Color.accentColor.opacity(0.15) }
    return isFavourite ? AppColors.favouriteBackground : nil
}

// The stop the user dragged the card to, kept for the tracking session so
// rotating, folding or unfolding returns to it. Side by side has no stop and
// leaves the choice alone. A new session, or the end of one, forgets it, so
// tracking opens at Half and idle rests at Peek.
struct CardStopChoice: Equatable {
    private(set) var chosen: CardStop?
    private var tracking = false

    mutating func appStateChanged(_ appState: Int) {
        let now = appState == 2
        if now != tracking { chosen = nil }
        tracking = now
    }

    mutating func choose(_ stop: CardStop) { chosen = stop }

    func layout(width: CGFloat, height: CGFloat, appState: Int) -> PaneLayout {
        paneLayout(width: width, height: height, appState: appState, stop: chosen)
    }
}

// The stop whose card edge is nearest where the drag would carry it. The
// predicted translation includes the release velocity, so a fling travels
// past the nearest stop.
func settledStop(width: CGFloat, height: CGFloat, from: CardStop, predictedTranslation: CGFloat) -> CardStop {
    func edge(_ stop: CardStop) -> CGFloat {
        paneLayout(width: width, height: height, appState: 2, stop: stop).detailStart
    }
    let projected = edge(from) + predictedTranslation
    return [CardStop.peek, .half, .full].min { abs(edge($0) - projected) < abs(edge($1) - projected) } ?? from
}

// The grabber's button and accessibility actions move the card a stop, so
// dragging is never the only way.
func openedStop(_ stop: CardStop) -> CardStop { stop == .peek ? .half : .full }
func closedStop(_ stop: CardStop) -> CardStop { stop == .full ? .half : .peek }

// The one place the layout decision becomes panes, so the app and its
// snapshots draw the same thing at the same size. Both wide modes draw the
// board as the first layer, so a rotation between them keeps its scroll.
struct AdaptivePanes<Board: View, Tracking: View, Summary: View, Hint: View>: View {
    var layout: PaneLayout
    var showsTracking: Bool
    var onStop: () -> Void = {}
    var onChoose: (CardStop) -> Void = { _ in }
    @ViewBuilder var board: () -> Board
    @ViewBuilder var tracking: () -> Tracking
    @ViewBuilder var summary: () -> Summary
    @ViewBuilder var hint: () -> Hint

    @GestureState private var drag: CGFloat = 0

    var body: some View {
        switch layout.mode {
        case .board:
            board()
        case .tracking:
            tracking()
        case .sideBySide, .card:
            GeometryReader { geo in
                ZStack(alignment: .topLeading) {
                    // At Full the card covers the board, which keeps its Half
                    // width underneath rather than laying out at zero.
                    board()
                        .frame(width: layout.boardWidth > 0 ? layout.boardWidth : geo.size.width - trackingMinWidth,
                               height: geo.size.height)
                        .accessibilityHidden(layout.stop == .full)
                    if layout.mode == .sideBySide {
                        Rectangle()
                            .fill(Color(uiColor: .separator))
                            .frame(width: layout.detailStart - layout.boardWidth, height: geo.size.height)
                            .offset(x: layout.boardWidth)
                        sidePane
                            .frame(width: geo.size.width - layout.detailStart, height: geo.size.height)
                            .offset(x: layout.detailStart)
                    } else {
                        card(in: geo.size)
                    }
                }
            }
        }
    }

    private var sidePane: some View {
        Group {
            if showsTracking {
                VStack(spacing: 0) {
                    TrackingCardHeader(onStop: onStop)
                    tracking()
                }
            } else {
                hint()
                    .frame(maxWidth: 320)
                    .background(RoundedRectangle(cornerRadius: 16).fill(Color(uiColor: .secondarySystemBackground)))
                    .padding(24)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
    }

    private func card(in size: CGSize) -> some View {
        let stop = layout.stop ?? .peek
        let peekEdge = paneLayout(width: size.width, height: size.height, appState: 2, stop: .peek).detailStart
        let edge = min(max(layout.detailStart + drag, 0), peekEdge)
        return HStack(spacing: 0) {
            if showsTracking {
                CardGrabber(stop: stop, onChoose: onChoose)
                    .gesture(
                        DragGesture(minimumDistance: 4, coordinateSpace: .global)
                            .updating($drag) { value, state, _ in state = value.translation.width }
                            .onEnded { value in
                                onChoose(settledStop(width: size.width, height: size.height, from: stop,
                                                     predictedTranslation: value.predictedEndTranslation.width))
                            }
                    )
            }
            VStack(spacing: 0) {
                if !showsTracking {
                    hint().frame(maxWidth: .infinity, maxHeight: .infinity)
                } else if stop == .peek {
                    TrackingCardHeader(onStop: onStop)
                    Button { onChoose(.half) } label: {
                        summary().frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .buttonStyle(.plain)
                    Spacer(minLength: 0)
                } else {
                    TrackingCardHeader(onStop: onStop)
                    tracking()
                }
            }
        }
        .frame(width: size.width - edge, height: size.height)
        .clipShape(UnevenRoundedRectangle(topLeadingRadius: 20, bottomLeadingRadius: 20))
        // The shadow sits outside the clip, so the card's edge shows on a light board.
        .background(
            UnevenRoundedRectangle(topLeadingRadius: 20, bottomLeadingRadius: 20)
                .fill(Color(uiColor: .secondarySystemGroupedBackground))
                .shadow(color: .black.opacity(0.22), radius: 12, x: -2, y: 0)
        )
        .offset(x: edge)
        .animation(.spring(response: 0.35, dampingFraction: 0.85), value: layout)
    }
}

// The x stops tracking. Back is not drawn beside a board that is already on screen.
struct TrackingCardHeader: View {
    var onStop: () -> Void

    var body: some View {
        HStack {
            Spacer()
            Button(action: onStop) {
                Image(systemName: "xmark")
                    .font(.system(size: 14, weight: .bold))
                    .foregroundStyle(.secondary)
                    .frame(width: 30, height: 30)
                    .background(Circle().fill(Color(uiColor: .tertiarySystemFill)))
                    .frame(width: 44, height: 44)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(Text("Stop tracking"))
        }
        .padding(.horizontal, 6)
    }
}

// The vertical handle on the card's leading edge. A tap moves the card one stop.
struct CardGrabber: View {
    var stop: CardStop
    var onChoose: (CardStop) -> Void

    var body: some View {
        Button {
            onChoose(stop == .full ? closedStop(stop) : openedStop(stop))
        } label: {
            Capsule()
                .fill(Color(uiColor: .tertiaryLabel))
                .frame(width: 5, height: 44)
                .frame(width: 22)
                .frame(maxHeight: .infinity)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(Text("Tracking card"))
        .accessibilityValue(Text(Self.value(stop)))
        .accessibilityAction(named: Text("Expand")) { onChoose(openedStop(stop)) }
        .accessibilityAction(named: Text("Collapse")) { onChoose(closedStop(stop)) }
    }

    private static func value(_ stop: CardStop) -> LocalizedStringResource {
        switch stop {
        case .peek: return "Collapsed"
        case .half: return "Half open"
        case .full: return "Full screen"
        }
    }
}

// The card at Peek while tracking: enough to glance at, a tap opens it to Half.
struct TrackingPeekSummary: View {
    var lineNumber: String
    var lineColour: Color
    var destination: String
    var countdown: String
    var countdownColour: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            if !lineNumber.isEmpty {
                Text(lineNumber)
                    .font(.subheadline.weight(.bold))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 7)
                    .padding(.vertical, 2)
                    .background(RoundedRectangle(cornerRadius: 6).fill(lineColour))
            }
            Text(destination)
                .font(.headline)
                .lineLimit(2)
            Text(countdown)
                .font(.system(size: 34, weight: .bold, design: .rounded))
                .monospacedDigit()
                .foregroundStyle(countdownColour)
                .lineLimit(1)
                .minimumScaleFactor(0.6)
        }
        .padding(.horizontal, 12)
        .padding(.bottom, 12)
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
        .accessibilityHint(Text("Opens tracking"))
    }
}

struct TrackingPaneHint: View {
    var body: some View {
        Text("Tap a departure on the left to track it here.")
            .font(.body)
            .foregroundStyle(.secondary)
            .multilineTextAlignment(.center)
            .padding(20)
    }
}
