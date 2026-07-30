import ActivityKit
import AppIntents
import SwiftUI
import WidgetKit

/// Lock Screen + Dynamic Island rendering of a tracking session. The countdown
/// (`Text(timerInterval:)`) and the progress bar (`ProgressView(timerInterval:)`)
/// are system-driven, so they stay correct between updates and after the app
/// dies; delay, platform, verdict and walk refresh with each activity update.
struct TrackingLiveActivity: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: TrackingActivityAttributes.self) { context in
            TrackingActivityLockView(context: context)
                .padding(14)
        } dynamicIsland: { context in
            DynamicIsland {
                DynamicIslandExpandedRegion(.leading) {
                    LinePill(line: context.attributes.line)
                }
                DynamicIslandExpandedRegion(.trailing) {
                    PlatformLabel(state: context.state)
                }
                DynamicIslandExpandedRegion(.center) {
                    Text(context.state.destination)
                        .font(.headline)
                        .lineLimit(1)
                }
                DynamicIslandExpandedRegion(.bottom) {
                    VStack(spacing: 6) {
                        CountdownText(state: context.state)
                            .font(.system(size: 30, weight: .bold, design: .rounded))
                        TrackingProgressBar(context: context)
                        HStack {
                            StatusLine(state: context.state)
                            StopButton()
                        }
                    }
                }
            } compactLeading: {
                // A legible mini of the real diverging bar (with the centre
                // marker) on one side; the compact island can't draw across or
                // around the camera notch, so no wrap-around. Widened to use
                // the available leading space.
                TrackingProgressBar(context: context, barHeight: 9)
                    .frame(width: 62)
            } compactTrailing: {
                CompactCountdown(state: context.state)
            } minimal: {
                CompactCountdown(state: context.state)
            }
        }
    }
}

private struct TrackingActivityLockView: View {
    let context: ActivityViewContext<TrackingActivityAttributes>

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                LinePill(line: context.attributes.line)
                Text(context.state.destination)
                    .font(.headline)
                    .lineLimit(1)
                Spacer(minLength: 4)
                PlatformLabel(state: context.state)
                StopButton()
            }
            HStack(alignment: .firstTextBaseline) {
                CountdownText(state: context.state)
                    .font(.system(size: 34, weight: .bold, design: .rounded))
                Spacer()
                Text(context.attributes.stationName)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            TrackingProgressBar(context: context)
            StatusLine(state: context.state)
        }
    }
}

private struct LinePill: View {
    let line: String

    var body: some View {
        Text(line)
            .font(.caption.bold())
            .padding(.horizontal, 7)
            .padding(.vertical, 3)
            .background(Capsule().fill(Color(red: 0.92, green: 0, blue: 0)))
            .foregroundStyle(.white)
            .lineLimit(1)
    }
}

/// Stop the tracking session from the Live Activity. Shows expanded (Lock Screen
/// + expanded island) only, mirroring the Android notification whose Stop action
/// also renders only expanded. Icon-only, so no per-locale label to clip.
private struct StopButton: View {
    var body: some View {
        Button(intent: StopTrackingIntent()) {
            Image(systemName: "xmark")
                .font(.caption.bold())
                .foregroundStyle(.secondary)
                .frame(width: 26, height: 26)
                .background(Circle().fill(Color.secondary.opacity(0.18)))
        }
        .buttonStyle(.plain)
    }
}

private struct PlatformLabel: View {
    let state: TrackingActivityAttributes.ContentState

    var body: some View {
        if !state.platform.isEmpty {
            Text("Platform \(state.platform)")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(state.platformChanged ? Color.orange : Color.primary)
                .lineLimit(1)
        }
    }
}

/// The live countdown targets the leave-by moment (departure − walk), so the
/// number IS the ahead margin: at 0:00 it is time to leave. This mirrors the
/// Android notification's chronometer. Without a walk estimate (no GPS) it falls
/// back to the departure time. Once past leave-by but before departure it shows
/// "Leave now" rather than a negative timer, since `timerInterval` needs a
/// forward range; the verdict line already reads "N min behind".
private enum LeaveByPhase {
    case departed
    case leaveNow
    case counting(Date)
}

private func leaveByPhase(_ state: TrackingActivityAttributes.ContentState) -> LeaveByPhase {
    if state.departed || state.effectiveDeparture <= Date.now { return .departed }
    guard let walk = state.walkMinutes, walk > 0 else { return .counting(state.effectiveDeparture) }
    let leaveBy = state.effectiveDeparture.addingTimeInterval(-Double(walk) * 60)
    return leaveBy <= Date.now ? .leaveNow : .counting(leaveBy)
}

private struct CountdownText: View {
    let state: TrackingActivityAttributes.ContentState

    var body: some View {
        switch leaveByPhase(state) {
        case .departed:
            Text("Departed")
        case .leaveNow:
            Text("Leave now")
        case .counting(let target):
            Text(timerInterval: Date.now...target, countsDown: true)
                .monospacedDigit()
        }
    }
}

private struct CompactCountdown: View {
    let state: TrackingActivityAttributes.ContentState

    var body: some View {
        switch leaveByPhase(state) {
        case .departed:
            Image(systemName: "checkmark")
        case .leaveNow:
            Image(systemName: "figure.walk")
        case .counting(let target):
            Text(timerInterval: Date.now...target, countsDown: true)
                .monospacedDigit()
                .font(.caption2.bold())
                .frame(maxWidth: 44)
                .multilineTextAlignment(.trailing)
        }
    }
}

/// One half of the camera-wrapping compact bar. The edge next to the camera
/// notch is the zero-margin centre; the fill grows outward from it — green to
/// The in-app diverging tracking bar (`TrackingBarView`), redrawn here: centre
/// is zero margin, coloured runs grow outward (dark/light green = margin to
/// spare, amber/red = behind), gapless. It redraws on each activity update
/// rather than gliding, matching the Android notification's static bitmap bar.
private struct TrackingProgressBar: View {
    let context: ActivityViewContext<TrackingActivityAttributes>

    var barHeight: CGFloat = 10
    private let scale = 3.0 // ±3 minutes maps to half the bar

    private var hasGPS: Bool { TrackingVerdict(rawValue: context.state.verdict) != .noGps }

    var body: some View {
        let sched = context.state.schedBuf
        let effect = context.state.effectBuf
        GeometryReader { geo in
            let width = geo.size.width
            let midX = width / 2
            ZStack(alignment: .leading) {
                RoundedRectangle(cornerRadius: 3).fill(Color.secondary.opacity(0.25))
                if !hasGPS {
                    RoundedRectangle(cornerRadius: 3).fill(Color.gray)
                } else {
                    bar(sched: sched, effect: effect, width: width, midX: midX)
                }
                Rectangle()
                    .fill(Color.gray.opacity(0.8))
                    .frame(width: 2)
                    .offset(x: midX - 1)
            }
        }
        .frame(height: barHeight)
        .clipShape(RoundedRectangle(cornerRadius: 3))
    }

    @ViewBuilder
    private func bar(sched: Double, effect: Double, width: CGFloat, midX: CGFloat) -> some View {
        let schedPos = position(sched, midX: midX)
        let effectPos = position(effect, midX: midX)
        if sched >= 0 && effect >= 0 {
            Rectangle().fill(barDarkGreen).frame(width: max(0, schedPos - midX)).offset(x: midX)
            if effectPos > schedPos {
                Rectangle().fill(barLightGreen).frame(width: effectPos - schedPos).offset(x: schedPos)
            }
        } else if sched < 0 && effect < 0 {
            Rectangle().fill(barDarkRed).frame(width: max(0, midX - effectPos)).offset(x: effectPos)
            if schedPos < effectPos {
                Rectangle().fill(barAmber).frame(width: effectPos - schedPos).offset(x: schedPos)
            }
        } else if sched < 0 && effect >= 0 {
            Rectangle().fill(barAmber).frame(width: max(0, midX - schedPos)).offset(x: schedPos)
            Rectangle().fill(barLightGreen).frame(width: max(0, effectPos - midX)).offset(x: midX)
        }
    }

    private func position(_ buffer: Double, midX: CGFloat) -> CGFloat {
        let clamped = max(-scale, min(scale, buffer))
        return midX + CGFloat(clamped / scale) * midX
    }
}

// AppColors mirror (the widget target can't see the app's palette).
private let barDarkGreen = Color(red: 0.12, green: 0.56, blue: 0.24)
private let barLightGreen = Color(red: 0.44, green: 0.81, blue: 0.51)
private let barAmber = Color(red: 0.88, green: 0.54, blue: 0.0)
private let barDarkRed = Color(red: 0.83, green: 0.18, blue: 0.18)

private struct StatusLine: View {
    let state: TrackingActivityAttributes.ContentState

    var body: some View {
        HStack(spacing: 6) {
            if state.delay > 0 {
                Text(verbatim: "+\(state.delay)")
                    .foregroundStyle(Color(red: 0.78, green: 0.24, blue: 0))
                    .bold()
            }
            Text(statusText)
                .foregroundStyle(verdictColor(state))
            if let walk = state.walkMinutes, walk >= 1 {
                Text(verbatim: "·").foregroundStyle(.secondary)
                Text("\(walk) min walk", comment: "Walk time on the Live Activity")
                    .foregroundStyle(.secondary)
            }
            Spacer()
        }
        .font(.caption)
    }

    private var statusText: String {
        switch TrackingVerdict(rawValue: state.verdict) {
        case .noGps, .none: return String(localized: "No GPS")
        case .onTime: return String(localized: "On time")
        case .ahead: return String(localized: "\(unitLabel) ahead")
        case .behind: return String(localized: "\(unitLabel) behind")
        }
    }

    private var unitLabel: String {
        String(localized: "\(state.bufferMinutes) min")
    }
}

private func verdictColor(_ state: TrackingActivityAttributes.ContentState) -> Color {
    switch TrackingVerdict(rawValue: state.verdict) {
    case .ahead, .onTime: return Color(red: 0.12, green: 0.56, blue: 0.24)
    case .behind: return Color(red: 0.83, green: 0.18, blue: 0.18)
    case .noGps, .none: return Color.gray
    }
}
