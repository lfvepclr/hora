import SwiftUI

struct BreakOverlayView: View {
    var session: RestNowSession

    var body: some View {
        ZStack {
            // Background gradients
            ZStack {
                LinearGradient(
                    colors: [
                        Color.black.opacity(0.85),
                        Color.black.opacity(0.65),
                        Color.black.opacity(0.85)
                    ],
                    startPoint: .top,
                    endPoint: .bottom
                )

                RadialGradient(
                    gradient: Gradient(colors: [
                        Color.black.opacity(0.95),
                        Color.black.opacity(1.0)
                    ]),
                    center: .center,
                    startRadius: 0,
                    endRadius: 900
                )
            }
            .ignoresSafeArea()

            VStack(spacing: 20) {
                Text("休息一下")
                    .font(.largeTitle.weight(.bold))
                    .foregroundColor(.white)

                Text("站起来活动一下")
                    .font(.largeTitle.weight(.regular))
                    .multilineTextAlignment(.center)
                    .foregroundColor(.white.opacity(0.9))

                Text(formattedTime(session.remainingSeconds))
                    .font(.system(size: 44, weight: .medium, design: .monospaced))
                    .foregroundColor(.white)

                // Show skip button after forced rest time to prevent accidental taps
                if (session.restDuration - session.remainingSeconds) >= session.forcedRestSeconds {
                    Button {
                        session.skipBreak()
                    } label: {
                        HStack(spacing: 5) {
                            Image(systemName: "chevron.right.2")
                                .font(.system(size: 13, weight: .semibold))
                            Text("跳过休息")
                                .font(.system(size: 16, weight: .semibold))
                        }
                        .foregroundStyle(.white)
                        .padding(.horizontal, 16)
                        .padding(.vertical, 10)
                        .background(Color.gray.opacity(0.35))
                        .overlay(
                            Capsule()
                                .stroke(Color.white.opacity(0.25), lineWidth: 1)
                        )
                        .clipShape(Capsule())
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding()
        }
    }

    private func formattedTime(_ seconds: Int) -> String {
        let total = max(seconds, 0)
        let minutes = total / 60
        let secs = total % 60
        return String(format: "%02d:%02d", minutes, secs)
    }
}
