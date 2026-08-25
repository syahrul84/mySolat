import SwiftUI

/// The contents of the on-screen prayer popup.
struct PrayerAlertView: View {
    let alert: PrayerAlert
    let zoneDescription: String
    let use24Hour: Bool
    /// Seconds until self-dismiss; 0 means it waits for the user.
    let autoDismissAfter: Int
    let dismiss: () -> Void

    @State private var remaining: Int = 0
    @State private var appeared = false

    private var accent: Color { alert.kind == .atPrayerTime ? .green : .accentColor }

    var body: some View {
        HStack(spacing: 14) {
            ZStack {
                Circle()
                    .fill(accent.opacity(0.15))
                    .frame(width: 54, height: 54)
                Image(systemName: alert.prayer.symbolName)
                    .font(.system(size: 24, weight: .medium))
                    .foregroundStyle(accent)
            }

            VStack(alignment: .leading, spacing: 3) {
                Text(alert.title)
                    .font(.system(size: 15, weight: .semibold))
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)

                Text(SolatCalendar.string(for: alert.prayerDate, use24Hour: use24Hour))
                    .font(.system(size: 22, weight: .semibold, design: .rounded))
                    .monospacedDigit()
                    .foregroundStyle(accent)

                Text(zoneDescription)
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            Spacer(minLength: 4)

            VStack(spacing: 6) {
                Button(action: dismiss) {
                    Text("Dismiss")
                        .font(.system(size: 12, weight: .medium))
                        .frame(minWidth: 62)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.regular)

                if autoDismissAfter > 0 {
                    Text("closes in \(remaining)s")
                        .font(.system(size: 9))
                        .foregroundStyle(.tertiary)
                        .monospacedDigit()
                }
            }
        }
        .padding(16)
        .frame(width: 380, height: 190, alignment: .center)
        .background {
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(.regularMaterial)
                .overlay {
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .strokeBorder(accent.opacity(0.35), lineWidth: 1)
                }
        }
        .scaleEffect(appeared ? 1 : 0.96)
        .opacity(appeared ? 1 : 0)
        .animation(.spring(response: 0.32, dampingFraction: 0.8), value: appeared)
        .onAppear {
            appeared = true
            remaining = autoDismissAfter
            guard autoDismissAfter > 0 else { return }
            // The panel is torn down when the countdown ends, so this timer dies
            // with the view.
            Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { timer in
                Task { @MainActor in
                    remaining -= 1
                    if remaining <= 0 { timer.invalidate() }
                }
            }
        }
    }
}
