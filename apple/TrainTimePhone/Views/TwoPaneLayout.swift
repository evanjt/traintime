import SwiftUI

enum PaneLayout: Equatable { case board, tracking, splitTracking, splitHint }

// A regular-width window has room for the board beside tracking. Compact
// keeps the board, then tracking full-screen. Inactive (state 3) shows the
// board, or the split, under its scrim.
func paneLayout(_ sizeClass: UserInterfaceSizeClass?, appState: Int) -> PaneLayout {
    switch (sizeClass == .regular, appState == 2) {
    case (true, true): return .splitTracking
    case (true, false): return .splitHint
    case (false, true): return .tracking
    case (false, false): return .board
    }
}

// Tracking keeps at least a small phone's width, the board a readable column.
func boardPaneWidth(totalWidth: CGFloat) -> CGFloat {
    min(400, max(300, totalWidth - 360))
}

// The tracking poll, walk distance and train match all read the board's
// station and mode, so the board must not move away while a train is tracked.
func boardPickersLocked(appState: Int) -> Bool { appState == 2 }

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

struct TwoPaneLayout<Board: View, Detail: View>: View {
    @ViewBuilder var board: () -> Board
    @ViewBuilder var detail: () -> Detail

    var body: some View {
        GeometryReader { geo in
            HStack(spacing: 0) {
                board()
                    .frame(width: boardPaneWidth(totalWidth: geo.size.width))
                Divider()
                detail()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
    }
}

struct TrackingPaneHint: View {
    var body: some View {
        Text("Tap a departure on the left to track it here.")
            .font(.body)
            .foregroundStyle(.secondary)
            .multilineTextAlignment(.center)
            .padding(32)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
