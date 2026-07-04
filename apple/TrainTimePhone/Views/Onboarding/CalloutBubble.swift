import SwiftUI

// A small anchored coach-mark, not a full-screen card. The caret hints at the spotlighted
// feature; the host places the bubble in the screen half opposite the target so it never sits
// over what it explains. Peer of the Android CalloutBubble.kt.
struct CalloutBubble: View {
    let title: String
    let message: String
    let index: Int
    let total: Int
    let caretUp: Bool
    let nextLabel: String
    let onBack: () -> Void
    let onSkip: () -> Void
    let onNext: () -> Void

    var body: some View {
        VStack(spacing: 2) {
            if caretUp { Caret(up: true) }

            VStack(alignment: .leading, spacing: 6) {
                Text(title)
                    .font(.headline)
                Text(message)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)

                HStack(spacing: 4) {
                    if index > 0 {
                        Button("Back", action: onBack)
                            .buttonStyle(.borderless)
                    }
                    HStack(spacing: 6) {
                        ForEach(0..<total, id: \.self) { i in
                            Circle()
                                .fill(i == index ? Color.accentColor : Color.secondary.opacity(0.4))
                                .frame(width: i == index ? 8 : 6, height: i == index ? 8 : 6)
                        }
                    }
                    .frame(maxWidth: .infinity)
                    .accessibilityElement()
                    .accessibilityLabel("Step \(index + 1) of \(total)")

                    Button("Skip", action: onSkip)
                        .buttonStyle(.borderless)
                        .tint(.secondary)
                    Button(nextLabel, action: onNext)
                        .buttonStyle(.borderedProminent)
                        .controlSize(.small)
                }
                .padding(.top, 8)
            }
            .padding(.horizontal, 18)
            .padding(.vertical, 16)
            .background(
                RoundedRectangle(cornerRadius: 16)
                    .fill(Color(uiColor: .tertiarySystemBackground))
                    .shadow(radius: 8, y: 2)
            )
            .overlay(
                // Faint border so the callout reads as a raised sheet over the dimmed background.
                RoundedRectangle(cornerRadius: 16)
                    .stroke(Color.primary.opacity(0.12), lineWidth: 1)
            )

            if !caretUp { Caret(up: false) }
        }
        .frame(maxWidth: 380)
    }
}

// A triangle caret pointing toward the target.
private struct Caret: View {
    let up: Bool
    var body: some View {
        Canvas { context, size in
            var path = Path()
            if up {
                path.move(to: CGPoint(x: size.width / 2, y: 0))
                path.addLine(to: CGPoint(x: size.width, y: size.height))
                path.addLine(to: CGPoint(x: 0, y: size.height))
            } else {
                path.move(to: CGPoint(x: 0, y: 0))
                path.addLine(to: CGPoint(x: size.width, y: 0))
                path.addLine(to: CGPoint(x: size.width / 2, y: size.height))
            }
            path.closeSubpath()
            context.fill(path, with: .color(Color(uiColor: .tertiarySystemBackground)))
        }
        .frame(width: 18, height: 9)
        .accessibilityHidden(true)
    }
}
