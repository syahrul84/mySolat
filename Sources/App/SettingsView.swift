import AppKit
import SwiftUI

struct SettingsView: View {
    @EnvironmentObject private var state: AppState
    @State private var tab: Tab = .location

    /// An explicit switcher rather than `TabView`: inside a plain `Window` scene
    /// TabView's bar renders empty, so the sections are driven directly.
    enum Tab: String, CaseIterable, Identifiable {
        case location, alerts, appearance, updates, about

        var id: String { rawValue }

        var title: String {
            switch self {
            case .location: return "Location"
            case .alerts: return "Alerts"
            case .appearance: return "Appearance"
            case .updates: return "Updates"
            case .about: return "About"
            }
        }

        var symbol: String {
            switch self {
            case .location: return "mappin.and.ellipse"
            case .alerts: return "bell"
            case .appearance: return "menubar.rectangle"
            case .updates: return "arrow.down.circle"
            case .about: return "info.circle"
            }
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            Picker("", selection: $tab) {
                ForEach(Tab.allCases) { item in
                    Label(item.title, systemImage: item.symbol).tag(item)
                }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .padding(.horizontal, 18)
            .padding(.top, 10)
            .padding(.bottom, 10)

            Divider()

            Group {
                switch tab {
                case .location: LocationSettings()
                case .alerts: NotificationSettings()
                case .appearance: AppearanceSettings()
                case .updates: UpdateSettings()
                case .about: AboutSettings()
                }
            }
            .padding(18)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        }
        .frame(width: 580, height: 660)
    }
}

// MARK: - Location

private struct LocationSettings: View {
    @EnvironmentObject private var state: AppState
    @StateObject private var locator = LocationResolver()

    @State private var search = ""
    @State private var isDetecting = false
    @State private var detectError: String?

    private var results: [(negeri: String, zones: [Zone])] {
        let matching = ZoneCatalog.shared.search(search)
        return Dictionary(grouping: matching, by: \.negeri)
            .map { (negeri: $0.key, zones: $0.value.sorted { $0.jakimCode < $1.jakimCode }) }
            .sorted { $0.negeri < $1.negeri }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Prayer zone").font(.headline)
                    Text(state.zoneDescription)
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Button {
                    detect()
                } label: {
                    if isDetecting {
                        ProgressView().controlSize(.small)
                    } else {
                        Label("Detect", systemImage: "location")
                    }
                }
                .disabled(isDetecting)
                .help("Find your JAKIM zone from your current location")
            }

            if let detectError {
                Text(detectError)
                    .font(.system(size: 11))
                    .foregroundStyle(.orange)
                    .fixedSize(horizontal: false, vertical: true)
            }

            TextField("Search state, district or code…", text: $search)
                .textFieldStyle(.roundedBorder)

            List {
                ForEach(results, id: \.negeri) { group in
                    Section(group.negeri) {
                        ForEach(group.zones) { zone in
                            ZoneRow(zone: zone, isSelected: zone.jakimCode == state.prefs.zoneCode) {
                                Task { await state.changeZone(to: zone.jakimCode) }
                            }
                        }
                    }
                }
            }
            .listStyle(.inset)
            .frame(minHeight: 260)

            HStack(spacing: 6) {
                Image(systemName: state.coverageIsHealthy ? "checkmark.circle.fill" : "exclamationmark.triangle.fill")
                    .foregroundStyle(state.coverageIsHealthy ? .green : .orange)
                Text(coverageText)
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                Spacer()
                Button("Refresh now") {
                    Task { await state.refresh(force: true) }
                }
                .controlSize(.small)
                .disabled(state.isRefreshing)
            }
        }
    }

    private var coverageText: String {
        var text = "\(state.coverageDays) days of prayer times stored offline"
        if let last = state.lastFetch {
            let f = RelativeDateTimeFormatter()
            f.unitsStyle = .short
            text += " · updated \(f.localizedString(for: last, relativeTo: Date()))"
        }
        return text
    }

    private func detect() {
        isDetecting = true
        detectError = nil
        Task {
            do {
                try await state.detectZone(using: locator)
            } catch {
                detectError = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
            }
            isDetecting = false
        }
    }
}

private struct ZoneRow: View {
    let zone: Zone
    let isSelected: Bool
    let select: () -> Void

    var body: some View {
        Button(action: select) {
            HStack(spacing: 8) {
                Image(systemName: isSelected ? "largecircle.fill.circle" : "circle")
                    .foregroundStyle(isSelected ? AnyShapeStyle(.tint) : AnyShapeStyle(.tertiary))
                VStack(alignment: .leading, spacing: 1) {
                    Text(zone.daerah).font(.system(size: 12))
                    Text(zone.jakimCode)
                        .font(.system(size: 10, weight: .medium))
                        .foregroundStyle(.tertiary)
                }
                Spacer()
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Alerts

private struct NotificationSettings: View {
    @EnvironmentObject private var state: AppState

    @State private var notifyAtTime = true
    @State private var preAlertOn = true
    @State private var preAlertMinutes = 15
    @State private var soundOn = true
    @State private var enabled: Set<Prayer> = []

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                if !state.notificationsAuthorized {
                    permissionBanner
                }

                GroupBox("When to alert") {
                    VStack(alignment: .leading, spacing: 10) {
                        Toggle("Notify when the prayer time enters", isOn: $notifyAtTime)
                            .onValueChange(of: notifyAtTime) { value in
                                state.prefs.notifyAtPrayerTime = value
                                commit()
                            }

                        Divider()

                        Toggle("Notify me before the prayer time", isOn: $preAlertOn)
                            .onValueChange(of: preAlertOn) { value in
                                state.prefs.preAlertEnabled = value
                                commit()
                            }

                        HStack(spacing: 8) {
                            Text("Remind me")
                            Stepper(value: $preAlertMinutes, in: 1...120) {
                                Text("\(preAlertMinutes) min")
                                    .monospacedDigit()
                                    .frame(minWidth: 54, alignment: .leading)
                            }
                            .onValueChange(of: preAlertMinutes) { value in
                                state.prefs.preAlertMinutes = value
                                commit()
                            }
                            Text("before")
                            Spacer()
                        }
                        .disabled(!preAlertOn)
                        .foregroundStyle(preAlertOn ? .primary : .secondary)

                        Text("A heads-up so you have time to prepare — wudhu, wrap up a meeting, or head to the masjid.")
                            .font(.system(size: 10))
                            .foregroundStyle(.secondary)

                        Divider()

                        Toggle("Play a sound", isOn: $soundOn)
                            .onValueChange(of: soundOn) { value in
                                state.prefs.notificationSoundEnabled = value
                                commit()
                            }
                        Text("mySolat has no adzan audio — it uses the standard macOS notification sound.")
                            .font(.system(size: 10))
                            .foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(6)
                }

                GroupBox("Which prayers") {
                    VStack(alignment: .leading, spacing: 6) {
                        ForEach(Prayer.displayOrder) { prayer in
                            Toggle(isOn: binding(for: prayer)) {
                                HStack(spacing: 6) {
                                    Image(systemName: prayer.symbolName)
                                        .frame(width: 16)
                                        .foregroundStyle(.secondary)
                                    Text(prayer.displayName)
                                    Text(prayer.latinName)
                                        .font(.system(size: 10))
                                        .foregroundStyle(.tertiary)
                                }
                            }
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(6)
                }

                HStack {
                    Button("Send a test notification") {
                        Task { await state.sendTestNotification() }
                    }
                    Spacer()
                    Text("\(state.scheduledAlertCount) alerts queued")
                        .font(.system(size: 10))
                        .foregroundStyle(.secondary)
                        .help("macOS allows 64 pending notifications, so mySolat schedules a rolling window and refreshes it hourly. Your prayer times stay cached 30+ days regardless.")
                }
            }
            .padding(2)
        }
        .onAppear(perform: load)
    }

    private var permissionBanner: some View {
        HStack(spacing: 8) {
            Image(systemName: "bell.slash.fill").foregroundStyle(.orange)
            VStack(alignment: .leading, spacing: 2) {
                Text("Notifications are turned off").font(.system(size: 12, weight: .medium))
                Text("mySolat can't alert you until macOS allows it.")
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Button("Open Settings") { state.openNotificationSettings() }
                .controlSize(.small)
        }
        .padding(10)
        .background(RoundedRectangle(cornerRadius: 8).fill(Color.orange.opacity(0.12)))
    }

    private func binding(for prayer: Prayer) -> Binding<Bool> {
        Binding(
            get: { enabled.contains(prayer) },
            set: { isOn in
                if isOn { enabled.insert(prayer) } else { enabled.remove(prayer) }
                state.prefs.enabledPrayers = enabled
                commit()
            }
        )
    }

    private func load() {
        notifyAtTime = state.prefs.notifyAtPrayerTime
        preAlertOn = state.prefs.preAlertEnabled
        preAlertMinutes = state.prefs.preAlertMinutes
        soundOn = state.prefs.notificationSoundEnabled
        enabled = state.prefs.enabledPrayers
    }

    private func commit() {
        Task { await state.settingsChanged() }
    }
}

// MARK: - Appearance

private struct AppearanceSettings: View {
    @EnvironmentObject private var state: AppState

    @State private var style: MenuBarStyle = .nameAndTime
    @State private var use24Hour = false
    @State private var showSecondary = true
    @State private var launchAtLogin = false

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            GroupBox("Menu bar") {
                VStack(alignment: .leading, spacing: 10) {
                    Picker("Show", selection: $style) {
                        ForEach(MenuBarStyle.allCases) { option in
                            Text(option.displayName).tag(option)
                        }
                    }
                    .onValueChange(of: style) { value in
                        state.prefs.menuBarStyle = value
                        commit()
                    }

                    HStack(spacing: 6) {
                        Text("Preview:")
                            .font(.system(size: 11))
                            .foregroundStyle(.secondary)
                        HStack(spacing: 4) {
                            Image(systemName: state.menuBarSymbol)
                            if !state.menuBarTitle.isEmpty { Text(state.menuBarTitle) }
                        }
                        .font(.system(size: 12))
                        .padding(.horizontal, 6)
                        .padding(.vertical, 3)
                        .background(RoundedRectangle(cornerRadius: 5).fill(Color.primary.opacity(0.08)))
                    }
                }
                .padding(6)
            }

            GroupBox("Times") {
                VStack(alignment: .leading, spacing: 10) {
                    Toggle("Use a 24-hour clock", isOn: $use24Hour)
                        .onValueChange(of: use24Hour) { value in
                            state.prefs.use24HourClock = value
                            commit()
                        }
                    Toggle("Show Imsak, Syuruk and Dhuha", isOn: $showSecondary)
                        .onValueChange(of: showSecondary) { value in
                            state.prefs.showSecondaryMarkers = value
                            commit()
                        }
                }
                .padding(6)
            }

            GroupBox("Startup") {
                VStack(alignment: .leading, spacing: 6) {
                    Toggle("Launch mySolat at login", isOn: $launchAtLogin)
                        .onValueChange(of: launchAtLogin) { value in
                            let result = LaunchAtLogin.set(value)
                            state.prefs.launchAtLogin = result
                            if result != value { launchAtLogin = result }
                        }
                    if LaunchAtLogin.requiresApproval {
                        Text("macOS needs you to approve mySolat under System Settings › General › Login Items.")
                            .font(.system(size: 10))
                            .foregroundStyle(.orange)
                    }
                }
                .padding(6)
            }

            Spacer()
        }
        .onAppear {
            style = state.prefs.menuBarStyle
            use24Hour = state.prefs.use24HourClock
            showSecondary = state.prefs.showSecondaryMarkers
            launchAtLogin = LaunchAtLogin.isEnabled
        }
    }

    private func commit() {
        Task { await state.settingsChanged() }
    }
}

// MARK: - Updates

private struct UpdateSettings: View {
    @EnvironmentObject private var state: AppState
    @State private var autoCheck = true

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            GroupBox("Automatic updates") {
                VStack(alignment: .leading, spacing: 10) {
                    Toggle("Check for updates automatically", isOn: $autoCheck)
                        .onValueChange(of: autoCheck) { value in
                            state.prefs.autoUpdateCheck = value
                        }

                    HStack {
                        Button("Check Now") { state.updater.checkForUpdates() }
                            .disabled(state.updater.phase.isBusy)
                        Spacer()
                        if let last = state.updater.lastChecked {
                            let f = RelativeDateTimeFormatter()
                            Text("Checked \(f.localizedString(for: last, relativeTo: Date()))")
                                .font(.system(size: 10))
                                .foregroundStyle(.tertiary)
                        }
                    }

                    statusLine

                    Text("Updates are downloaded from GitHub Releases, checked against the published SHA-256, then installed in place. mySolat restarts itself when it's done.")
                        .font(.system(size: 10))
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(6)
            }

            GroupBox("Version") {
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("mySolat \(AppVersion.displayString)")
                            .font(.system(size: 12, weight: .medium))
                        Text(archDescription)
                            .font(.system(size: 10))
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    Button("All Releases") { state.updater.openReleasePage() }
                        .controlSize(.small)
                }
                .padding(6)
            }

            Spacer()
        }
        .onAppear { autoCheck = state.prefs.autoUpdateCheck }
    }

    @ViewBuilder
    private var statusLine: some View {
        switch state.updater.phase {
        case .idle:
            EmptyView()

        case .checking:
            HStack(spacing: 6) {
                ProgressView().controlSize(.small)
                Text("Checking…").font(.system(size: 11)).foregroundStyle(.secondary)
            }

        case .upToDate:
            Label("You're on the latest version.", systemImage: "checkmark.circle.fill")
                .font(.system(size: 11))
                .foregroundStyle(.green)

        case .available(let release):
            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 8) {
                    Label("Version \(release.version) is available", systemImage: "arrow.down.circle.fill")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(.tint)
                    Spacer()
                    Button("Release Notes") { state.updater.openReleasePage() }
                        .buttonStyle(.link)
                        .font(.system(size: 10))
                    Button("Update Now") { state.updater.downloadAndInstall() }
                        .controlSize(.small)
                        .buttonStyle(.borderedProminent)
                }
                if !release.notes.isEmpty {
                    ScrollView {
                        Text(release.notes)
                            .font(.system(size: 10))
                            .foregroundStyle(.secondary)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .textSelection(.enabled)
                    }
                    .frame(maxHeight: 90)
                }
            }

        case .downloading(let fraction):
            VStack(alignment: .leading, spacing: 4) {
                ProgressView(value: fraction)
                Text("Downloading… \(Int(fraction * 100))%")
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
            }

        case .verifying:
            HStack(spacing: 6) {
                ProgressView().controlSize(.small)
                Text("Verifying download…").font(.system(size: 11)).foregroundStyle(.secondary)
            }

        case .installing:
            HStack(spacing: 6) {
                ProgressView().controlSize(.small)
                Text("Installing…").font(.system(size: 11)).foregroundStyle(.secondary)
            }

        case .readyToRelaunch:
            HStack(spacing: 8) {
                Label("Update ready", systemImage: "checkmark.circle.fill")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(.green)
                Spacer()
                Button("Restart mySolat") { state.updater.relaunchAndFinishUpdate() }
                    .controlSize(.small)
                    .buttonStyle(.borderedProminent)
            }

        case .failed(let message):
            VStack(alignment: .leading, spacing: 6) {
                Label(message, systemImage: "exclamationmark.triangle.fill")
                    .font(.system(size: 11))
                    .foregroundStyle(.orange)
                    .fixedSize(horizontal: false, vertical: true)
                HStack(spacing: 8) {
                    Button("Download Manually") { state.updater.openReleasePage() }
                        .controlSize(.small)
                    Button("Dismiss") { state.updater.dismissStatus() }
                        .controlSize(.small)
                }
            }
        }
    }

    private var archDescription: String {
        #if arch(arm64)
        return "Apple silicon · universal build"
        #else
        return "Intel (x86_64) · universal build"
        #endif
    }
}

// MARK: - About

private struct AboutSettings: View {
    @EnvironmentObject private var state: AppState

    var body: some View {
        VStack(spacing: 14) {
            AppLogo(size: 72)
                .padding(.top, 8)

            VStack(spacing: 3) {
                Text("mySolat").font(.system(size: 18, weight: .semibold))
                Text("Malaysian prayer times in your menu bar")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                Text("Version \(AppVersion.displayString)")
                    .font(.system(size: 10))
                    .foregroundStyle(.tertiary)
            }

            VStack(spacing: 4) {
                Text("Created by \(AppIdentifiers.authorName)")
                    .font(.system(size: 12, weight: .medium))

                HStack(spacing: 4) {
                    Text("© 2026 \(AppIdentifiers.authorName) ·")
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                    Button(AppIdentifiers.licenseName) {
                        NSWorkspace.shared.open(AppIdentifiers.licenseURL)
                    }
                    .buttonStyle(.link)
                    .font(.system(size: 11))
                    .help("Read the licence on GitHub")
                }

                Text("Free and open source software.")
                    .font(.system(size: 10))
                    .foregroundStyle(.tertiary)
            }

            VStack(alignment: .leading, spacing: 6) {
                Text("Enjoying mySolat?")
                    .font(.system(size: 12, weight: .medium))
                Text("It's free and open source. If it's useful to you, a small tip helps me keep it maintained.")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                Button {
                    state.openTipPage()
                } label: {
                    Label("Buy me a coffee", systemImage: "cup.and.saucer.fill")
                }
                .controlSize(.large)
                .padding(.top, 2)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(12)
            .background(RoundedRectangle(cornerRadius: 10).fill(Color.primary.opacity(0.05)))

            HStack(spacing: 14) {
                Button("GitHub") { state.openRepo() }.buttonStyle(.link)
                Button("Prayer data: waktusolat.app") {
                    NSWorkspace.shared.open(URL(string: "https://waktusolat.app")!)
                }
                .buttonStyle(.link)
            }
            .font(.system(size: 11))

            Text("Prayer times are sourced from JAKIM via the waktusolat.app API. Always verify against your local masjid.")
                .font(.system(size: 10))
                .foregroundStyle(.tertiary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)

            Spacer()
        }
        .frame(maxWidth: .infinity)
    }
}
