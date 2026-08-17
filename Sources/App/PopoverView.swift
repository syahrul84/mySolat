import AppKit
import SwiftUI

/// The panel shown when the menu bar item is clicked.
struct PopoverView: View {
    @EnvironmentObject private var state: AppState
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            Divider()
            if state.visibleEvents.isEmpty {
                emptyState
            } else {
                prayerList
            }
            Divider()
            footer
        }
        .frame(width: 300)
    }

    // MARK: Header

    private var header: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(state.zoneDescription)
                        .font(.system(size: 13, weight: .semibold))
                        .lineLimit(2)
                    Text(state.prefs.zoneCode)
                        .font(.system(size: 10, weight: .medium))
                        .foregroundStyle(.tertiary)
                }
                Spacer()
                if state.isRefreshing {
                    ProgressView().controlSize(.small)
                }
            }

            if let hijri = state.hijriDescription {
                Text(hijri)
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
            }

            if let next = state.nextEvent {
                HStack(spacing: 6) {
                    Image(systemName: next.prayer.symbolName)
                        .foregroundStyle(.tint)
                    Text("\(next.prayer.displayName) in \(SolatCalendar.preciseCountdownString(until: next.date, from: state.tick))")
                        .font(.system(size: 12, weight: .medium))
                        .monospacedDigit()
                }
                .padding(.top, 2)
            }

            if SolatCalendar.systemDiffersFromZone {
                Label("Times shown in Malaysia time (UTC+8)", systemImage: "globe.asia.australia")
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)
            }

            if let error = state.errorMessage {
                Label(error, systemImage: "exclamationmark.triangle")
                    .font(.system(size: 10))
                    .foregroundStyle(.orange)
                    .lineLimit(3)
            }

            if !state.notificationsAuthorized {
                Button {
                    state.openNotificationSettings()
                } label: {
                    Label("Notifications are off — enable them", systemImage: "bell.slash")
                        .font(.system(size: 10))
                }
                .buttonStyle(.link)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
    }

    // MARK: Prayer rows

    private var prayerList: some View {
        VStack(spacing: 0) {
            ForEach(state.visibleEvents) { event in
                PrayerRow(
                    event: event,
                    isNext: state.nextEvent?.id == event.id,
                    isCurrent: state.currentEvent?.id == event.id,
                    isPast: event.date < state.tick,
                    use24Hour: state.prefs.use24HourClock,
                    isNotified: state.prefs.enabledPrayers.contains(event.prayer)
                )
            }
        }
        .padding(.vertical, 4)
    }

    private var emptyState: some View {
        VStack(spacing: 8) {
            Image(systemName: "wifi.exclamationmark")
                .font(.system(size: 22))
                .foregroundStyle(.secondary)
            Text("No prayer times yet")
                .font(.system(size: 12, weight: .medium))
            Text("Connect to the internet once and mySolat will store the next 30 days.")
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
            Button("Try again") {
                Task { await state.refresh(force: true) }
            }
            .controlSize(.small)
        }
        .frame(maxWidth: .infinity)
        .padding(.horizontal, 16)
        .padding(.vertical, 20)
    }

    // MARK: Footer

    private var footer: some View {
        VStack(spacing: 0) {
            HStack(spacing: 4) {
                Image(systemName: state.coverageIsHealthy ? "checkmark.icloud" : "exclamationmark.icloud")
                    .font(.system(size: 10))
                    .foregroundStyle(state.coverageIsHealthy ? .green : .orange)
                Text("\(state.coverageDays) days stored offline")
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)
                Spacer()
                Button {
                    Task { await state.refresh(force: true) }
                } label: {
                    Image(systemName: "arrow.clockwise")
                        .font(.system(size: 10))
                }
                .buttonStyle(.borderless)
                .disabled(state.isRefreshing)
                .help("Refresh prayer times now")
            }
            .padding(.horizontal, 12)
            .padding(.top, 8)
            .padding(.bottom, 6)

            Divider()

            VStack(spacing: 1) {
                MenuButton(title: "Settings…", symbol: "gearshape", shortcut: "⌘,") {
                    openSettings()
                }
                MenuButton(title: "Support this app", symbol: "cup.and.saucer") {
                    state.openTipPage()
                }
                MenuButton(title: "Check for Updates…", symbol: "arrow.down.circle") {
                    state.updater.checkForUpdates()
                    openSettings()
                }
                MenuButton(title: "Quit mySolat", symbol: "power", shortcut: "⌘Q") {
                    NSApp.terminate(nil)
                }
            }
            .padding(.horizontal, 6)
            .padding(.vertical, 5)
        }
    }

    private func openSettings() {
        openWindow(id: SettingsWindow.id)
        NSApp.activate(ignoringOtherApps: true)
    }
}

// MARK: - Rows

private struct PrayerRow: View {
    let event: PrayerEvent
    let isNext: Bool
    let isCurrent: Bool
    let isPast: Bool
    let use24Hour: Bool
    let isNotified: Bool

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: event.prayer.symbolName)
                .font(.system(size: 11))
                .frame(width: 16)
                .foregroundStyle(isNext ? AnyShapeStyle(.tint) : AnyShapeStyle(.secondary))

            Text(event.prayer.displayName)
                .font(.system(size: 12, weight: isNext ? .semibold : .regular))

            if !isNotified {
                Image(systemName: "bell.slash")
                    .font(.system(size: 8))
                    .foregroundStyle(.tertiary)
                    .help("Notifications off for \(event.prayer.displayName)")
            }

            Spacer(minLength: 8)

            Text(SolatCalendar.string(for: event.date, use24Hour: use24Hour))
                .font(.system(size: 12, weight: isNext ? .semibold : .regular))
                .monospacedDigit()
                .foregroundStyle(foreground)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 5)
        .background {
            if isNext {
                RoundedRectangle(cornerRadius: 6)
                    .fill(Color.accentColor.opacity(0.12))
                    .padding(.horizontal, 6)
            } else if isCurrent {
                RoundedRectangle(cornerRadius: 6)
                    .fill(Color.primary.opacity(0.05))
                    .padding(.horizontal, 6)
            }
        }
        .opacity(isPast && !isCurrent ? 0.45 : 1)
    }

    private var foreground: some ShapeStyle {
        isNext ? AnyShapeStyle(.tint) : AnyShapeStyle(.primary)
    }
}

/// A row in the popover's action list, styled like a menu item.
private struct MenuButton: View {
    let title: String
    let symbol: String
    var shortcut: String? = nil
    let action: () -> Void

    @State private var isHovering = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 8) {
                Image(systemName: symbol)
                    .font(.system(size: 11))
                    .frame(width: 16)
                Text(title)
                    .font(.system(size: 12))
                Spacer()
                if let shortcut {
                    Text(shortcut)
                        .font(.system(size: 11))
                        .foregroundStyle(.tertiary)
                }
            }
            .padding(.horizontal, 6)
            .padding(.vertical, 5)
            .background(
                RoundedRectangle(cornerRadius: 5)
                    .fill(isHovering ? Color.accentColor.opacity(0.15) : .clear)
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { isHovering = $0 }
    }
}
