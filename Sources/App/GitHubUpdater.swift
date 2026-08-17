import AppKit
import CryptoKit
import Foundation
import SwiftUI
import UserNotifications

/// Self-contained auto-updater backed by GitHub Releases — no Sparkle, no
/// third-party framework.
///
/// ## Flow
/// 1. `GET /repos/{owner}/{repo}/releases/latest` and compare `tag_name` to the
///    running `CFBundleShortVersionString`.
/// 2. Download the `mySolat-<version>-universal.zip` asset to a temp directory.
/// 3. Verify integrity: SHA-256 against the release's `checksums.txt`, plus an
///    optional Ed25519 signature when a public key is embedded in the bundle.
/// 4. Extract with `ditto`, sanity-check the new bundle (identifier + version).
/// 5. Hand the swap to a short shell script that waits for this process to exit,
///    replaces the bundle, and relaunches. Doing the swap out-of-process is what
///    makes it safe to replace an app that is currently running.
@MainActor
final class GitHubUpdater: ObservableObject {

    // MARK: Types

    struct Release: Equatable, Sendable {
        let version: String
        let notes: String
        let pageURL: URL
        let assetURL: URL
        let assetName: String
        let assetSize: Int64
        let checksumsURL: URL?
        let signatureURL: URL?
    }

    enum Phase: Equatable {
        case idle
        case checking
        case upToDate
        case available(Release)
        case downloading(fraction: Double)
        case verifying
        case installing
        case readyToRelaunch
        case failed(String)

        var isBusy: Bool {
            switch self {
            case .checking, .downloading, .verifying, .installing: return true
            default: return false
            }
        }
    }

    enum UpdateError: LocalizedError {
        case noAsset
        case checksumMissing
        case checksumMismatch
        case signatureInvalid
        case extractionFailed(String)
        case invalidBundle(String)
        case notWritable(String)
        case http(Int)

        var errorDescription: String? {
            switch self {
            case .noAsset:
                return "That release doesn't include a downloadable mySolat build."
            case .checksumMissing:
                return "The release is missing its checksums.txt, so the download can't be verified."
            case .checksumMismatch:
                return "The downloaded file doesn't match the published checksum. Update cancelled."
            case .signatureInvalid:
                return "The download failed signature verification. Update cancelled."
            case .extractionFailed(let detail):
                return "The update could not be unpacked: \(detail)"
            case .invalidBundle(let detail):
                return "The downloaded app looks wrong: \(detail)"
            case .notWritable(let path):
                return "mySolat can't update itself at \(path). Move mySolat.app into your Applications folder and try again, or download the update manually."
            case .http(let code):
                return "GitHub returned HTTP \(code)."
            }
        }
    }

    // MARK: State

    @Published private(set) var phase: Phase = .idle
    @Published private(set) var lastChecked: Date?

    private let session: URLSession
    private var installedBundleURL: URL { Bundle.main.bundleURL }

    init() {
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 30
        config.timeoutIntervalForResource = 600
        session = URLSession(configuration: config)
        lastChecked = SharedContainer.defaults.object(forKey: PreferenceKeys.lastUpdateCheck) as? Date
    }

    // MARK: Checking

    /// Silent daily check on launch and hourly maintenance.
    func checkInBackgroundIfNeeded(prefs: Preferences) {
        guard prefs.autoUpdateCheck, !phase.isBusy else { return }
        if let last = lastChecked, Date().timeIntervalSince(last) < 60 * 60 * 24 { return }
        Task { await check(userInitiated: false) }
    }

    func checkForUpdates() {
        guard !phase.isBusy else { return }
        Task { await check(userInitiated: true) }
    }

    private func check(userInitiated: Bool) async {
        phase = .checking
        lastChecked = Date()
        SharedContainer.defaults.set(lastChecked, forKey: PreferenceKeys.lastUpdateCheck)

        do {
            guard let release = try await fetchLatestRelease() else {
                phase = .upToDate
                return
            }
            if AppVersion.isNewer(release.version, than: AppVersion.short) {
                phase = .available(release)
                if !userInitiated { await notifyAvailable(release) }
            } else {
                phase = .upToDate
            }
        } catch {
            phase = .failed(message(for: error))
        }
    }

    // MARK: GitHub API

    private struct APIRelease: Decodable {
        let tagName: String
        let name: String?
        let body: String?
        let htmlURL: String
        let draft: Bool
        let prerelease: Bool
        let assets: [APIAsset]

        enum CodingKeys: String, CodingKey {
            case tagName = "tag_name"
            case name, body, draft, prerelease, assets
            case htmlURL = "html_url"
        }
    }

    private struct APIAsset: Decodable {
        let name: String
        let size: Int64
        let browserDownloadURL: String

        enum CodingKeys: String, CodingKey {
            case name, size
            case browserDownloadURL = "browser_download_url"
        }
    }

    /// Returns the latest published release, or nil when the repo has none yet.
    private func fetchLatestRelease() async throws -> Release? {
        var request = URLRequest(url: AppIdentifiers.releasesAPIURL)
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        request.setValue("mySolat/\(AppVersion.short)", forHTTPHeaderField: "User-Agent")

        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse else { throw UpdateError.http(-1) }
        // A repo with no releases yet answers 404 — treat that as "up to date"
        // rather than as an error the user has to see.
        if http.statusCode == 404 { return nil }
        guard (200..<300).contains(http.statusCode) else { throw UpdateError.http(http.statusCode) }

        let api = try JSONDecoder().decode(APIRelease.self, from: data)
        guard !api.draft, !api.prerelease else { return nil }

        // Prefer the universal zip; the DMG is for manual downloads only because
        // mounting a disk image in-process is needless complexity.
        guard let asset = api.assets.first(where: {
            $0.name.hasSuffix(".zip") && $0.name.lowercased().contains("mysolat")
        }) else {
            throw UpdateError.noAsset
        }

        return Release(
            version: api.tagName,
            notes: api.body ?? "",
            pageURL: URL(string: api.htmlURL) ?? AppIdentifiers.latestReleaseURL,
            assetURL: URL(string: asset.browserDownloadURL)!,
            assetName: asset.name,
            assetSize: asset.size,
            checksumsURL: api.assets.first { $0.name == "checksums.txt" }
                .flatMap { URL(string: $0.browserDownloadURL) },
            signatureURL: api.assets.first { $0.name == asset.name + ".sig" }
                .flatMap { URL(string: $0.browserDownloadURL) }
        )
    }

    // MARK: Install

    /// Downloads, verifies and stages the update, then arms the relaunch.
    func downloadAndInstall() {
        guard case .available(let release) = phase else { return }
        Task { await performInstall(release) }
    }

    private func performInstall(_ release: Release) async {
        do {
            // Fail fast if we can't write where the app lives (e.g. it's still
            // inside a mounted DMG, or owned by another user).
            let target = installedBundleURL
            guard FileManager.default.isWritableFile(atPath: target.deletingLastPathComponent().path) else {
                throw UpdateError.notWritable(target.deletingLastPathComponent().path)
            }

            let workDir = try makeWorkDirectory()
            defer { try? FileManager.default.removeItem(at: workDir) }

            let zipURL = workDir.appendingPathComponent(release.assetName)
            try await download(release.assetURL, to: zipURL) { [weak self] fraction in
                Task { @MainActor in self?.phase = .downloading(fraction: fraction) }
            }

            phase = .verifying
            try await verify(zipURL: zipURL, release: release)

            phase = .installing
            let extractedApp = try extract(zipURL: zipURL, into: workDir)
            try validate(newBundle: extractedApp, expectedVersion: release.version)

            // Stage outside `workDir` so the deferred cleanup can't delete it
            // before the swap script runs.
            let staged = try stage(extractedApp)
            try armSwapScript(newBundle: staged, target: target)

            phase = .readyToRelaunch
        } catch {
            phase = .failed(message(for: error))
        }
    }

    private func makeWorkDirectory() throws -> URL {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("mySolat-update-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    /// Downloads to `destination`, reporting 0…1 progress.
    private func download(_ url: URL,
                          to destination: URL,
                          onProgress: @escaping @Sendable (Double) -> Void) async throws {
        var request = URLRequest(url: url)
        request.setValue("application/octet-stream", forHTTPHeaderField: "Accept")
        request.setValue("mySolat/\(AppVersion.short)", forHTTPHeaderField: "User-Agent")

        let (temporaryURL, response) = try await DownloadTask.run(
            request: request,
            configuration: session.configuration,
            onProgress: onProgress
        )
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            try? FileManager.default.removeItem(at: temporaryURL)
            throw UpdateError.http((response as? HTTPURLResponse)?.statusCode ?? -1)
        }
        if FileManager.default.fileExists(atPath: destination.path) {
            try FileManager.default.removeItem(at: destination)
        }
        try FileManager.default.moveItem(at: temporaryURL, to: destination)
        onProgress(1.0)
    }

    // MARK: Verification

    /// Integrity gate. SHA-256 against `checksums.txt` is mandatory; an Ed25519
    /// signature is additionally required when the app ships a public key.
    private func verify(zipURL: URL, release: Release) async throws {
        let data = try Data(contentsOf: zipURL, options: .mappedIfSafe)
        let digest = SHA256.hash(data: data)
        let hex = digest.map { String(format: "%02x", $0) }.joined()

        guard let checksumsURL = release.checksumsURL else { throw UpdateError.checksumMissing }
        let (checksumData, response) = try await session.data(from: checksumsURL)
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            throw UpdateError.checksumMissing
        }
        guard let text = String(data: checksumData, encoding: .utf8) else {
            throw UpdateError.checksumMissing
        }

        // `shasum -a 256` format: "<hex>  <filename>"
        let expected = text
            .split(separator: "\n")
            .compactMap { line -> (String, String)? in
                let parts = line.split(whereSeparator: \.isWhitespace).map(String.init)
                guard parts.count >= 2 else { return nil }
                return (parts[0].lowercased(), parts[parts.count - 1])
            }
            .first { $0.1.hasSuffix(release.assetName) }?.0

        guard let expected else { throw UpdateError.checksumMissing }
        guard expected == hex else { throw UpdateError.checksumMismatch }

        try await verifySignatureIfConfigured(release: release, payload: data)
    }

    /// Optional hardening: if `UpdatePublicKey` is present in Info.plist and the
    /// release publishes a `.sig`, the signature must validate.
    private func verifySignatureIfConfigured(release: Release, payload: Data) async throws {
        guard let base64Key = Bundle.main.object(forInfoDictionaryKey: "UpdatePublicKey") as? String,
              !base64Key.isEmpty,
              let keyData = Data(base64Encoded: base64Key)
        else { return }

        guard let signatureURL = release.signatureURL else { throw UpdateError.signatureInvalid }
        let (sigData, response) = try await session.data(from: signatureURL)
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            throw UpdateError.signatureInvalid
        }
        let signature = Data(base64Encoded: sigData.trimmedBase64String) ?? sigData

        do {
            let key = try Curve25519.Signing.PublicKey(rawRepresentation: keyData)
            guard key.isValidSignature(signature, for: payload) else {
                throw UpdateError.signatureInvalid
            }
        } catch {
            throw UpdateError.signatureInvalid
        }
    }

    // MARK: Extraction & staging

    private func extract(zipURL: URL, into directory: URL) throws -> URL {
        let extractDir = directory.appendingPathComponent("extracted", isDirectory: true)
        try FileManager.default.createDirectory(at: extractDir, withIntermediateDirectories: true)

        // `ditto` preserves bundle metadata and resource forks; `unzip` does not.
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/ditto")
        process.arguments = ["-x", "-k", zipURL.path, extractDir.path]
        let errPipe = Pipe()
        process.standardError = errPipe
        try process.run()
        process.waitUntilExit()

        guard process.terminationStatus == 0 else {
            let detail = String(data: errPipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
            throw UpdateError.extractionFailed(detail.isEmpty ? "ditto exited \(process.terminationStatus)" : detail)
        }

        let contents = try FileManager.default.contentsOfDirectory(at: extractDir, includingPropertiesForKeys: nil)
        guard let app = contents.first(where: { $0.pathExtension == "app" }) else {
            throw UpdateError.extractionFailed("no .app found in the archive")
        }
        return app
    }

    /// Confirms the archive really contains a newer mySolat before we swap it in.
    private func validate(newBundle: URL, expectedVersion: String) throws {
        guard let bundle = Bundle(url: newBundle) else {
            throw UpdateError.invalidBundle("unreadable bundle")
        }
        let identifier = bundle.bundleIdentifier ?? ""
        guard identifier == AppIdentifiers.appBundleID else {
            throw UpdateError.invalidBundle("unexpected identifier \"\(identifier)\"")
        }
        let version = bundle.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "0"
        guard AppVersion.isNewer(version, than: AppVersion.short) else {
            throw UpdateError.invalidBundle("version \(version) is not newer than \(AppVersion.short)")
        }
        guard FileManager.default.fileExists(atPath: newBundle.appendingPathComponent("Contents/MacOS").path) else {
            throw UpdateError.invalidBundle("missing executable directory")
        }
    }

    /// Moves the verified bundle to a stable temp location that survives cleanup.
    private func stage(_ newBundle: URL) throws -> URL {
        let stagingDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("mySolat-staged-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: stagingDir, withIntermediateDirectories: true)
        let staged = stagingDir.appendingPathComponent(newBundle.lastPathComponent)
        try FileManager.default.moveItem(at: newBundle, to: staged)
        return staged
    }

    // MARK: Swap & relaunch

    private var swapScriptURL: URL?

    /// Writes the swap script. It waits for our PID to exit before touching the
    /// bundle, so the running executable is never pulled out from under us.
    private func armSwapScript(newBundle: URL, target: URL) throws {
        let scriptURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("mySolat-swap-\(UUID().uuidString).sh")

        let script = """
        #!/bin/sh
        set -e
        PID="$1"
        NEW="$2"
        DEST="$3"

        # Wait for mySolat to quit (10s ceiling, then proceed anyway).
        i=0
        while kill -0 "$PID" 2>/dev/null && [ $i -lt 100 ]; do
          sleep 0.1
          i=$((i+1))
        done

        BACKUP="${DEST}.mysolat-old"
        rm -rf "$BACKUP"

        if [ -d "$DEST" ]; then
          mv "$DEST" "$BACKUP" || exit 1
        fi

        if ! mv "$NEW" "$DEST"; then
          # Roll back to the version the user had.
          [ -d "$BACKUP" ] && mv "$BACKUP" "$DEST"
          exit 1
        fi

        rm -rf "$BACKUP"
        xattr -dr com.apple.quarantine "$DEST" 2>/dev/null || true
        rm -rf "$(dirname "$NEW")"
        open "$DEST"
        rm -f "$0"
        """

        try script.write(to: scriptURL, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: scriptURL.path)

        swapScriptURL = scriptURL
        pendingSwap = (newBundle: newBundle, target: target)
    }

    private var pendingSwap: (newBundle: URL, target: URL)?

    /// Runs the swap script and quits so it can complete.
    func relaunchAndFinishUpdate() {
        guard let scriptURL = swapScriptURL, let pendingSwap else { return }

        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/sh")
        process.arguments = [
            scriptURL.path,
            String(ProcessInfo.processInfo.processIdentifier),
            pendingSwap.newBundle.path,
            pendingSwap.target.path,
        ]
        do {
            try process.run()
        } catch {
            phase = .failed("Couldn't start the installer: \(error.localizedDescription)")
            return
        }
        NSApp.terminate(nil)
    }

    // MARK: Misc

    func openReleasePage() {
        if case .available(let release) = phase {
            NSWorkspace.shared.open(release.pageURL)
        } else {
            NSWorkspace.shared.open(AppIdentifiers.latestReleaseURL)
        }
    }

    func dismissStatus() {
        if case .failed = phase { phase = .idle }
        if case .upToDate = phase { phase = .idle }
    }

    private func notifyAvailable(_ release: Release) async {
        let content = UNMutableNotificationContent()
        content.title = "mySolat \(release.version) is available"
        content.body = "You're on \(AppVersion.short). Open Settings › Updates to install it."
        let request = UNNotificationRequest(
            identifier: "mySolat.update.\(release.version)",
            content: content,
            trigger: UNTimeIntervalNotificationTrigger(timeInterval: 2, repeats: false)
        )
        try? await UNUserNotificationCenter.current().add(request)
    }

    private func message(for error: Error) -> String {
        (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
    }
}

private extension Data {
    /// GitHub-hosted `.sig` files are base64 text; tolerate trailing newlines.
    var trimmedBase64String: String {
        String(data: self, encoding: .utf8)?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
    }
}

/// A one-shot `URLSessionDownloadTask` wrapped for `async`/`await` with progress.
///
/// `URLSession.download(for:)` gives no progress, and iterating `URLSession.bytes`
/// one byte at a time is far too slow for a multi-megabyte archive — hence the
/// delegate. The download task moves its own temp file, so we relocate it to a
/// path we control before the delegate callback returns.
private final class DownloadTask: NSObject, URLSessionDownloadDelegate {
    private let onProgress: @Sendable (Double) -> Void
    private var continuation: CheckedContinuation<(URL, URLResponse), Error>?
    private var session: URLSession?

    private init(onProgress: @escaping @Sendable (Double) -> Void) {
        self.onProgress = onProgress
    }

    static func run(request: URLRequest,
                    configuration: URLSessionConfiguration,
                    onProgress: @escaping @Sendable (Double) -> Void) async throws -> (URL, URLResponse) {
        let delegate = DownloadTask(onProgress: onProgress)
        return try await delegate.start(request: request, configuration: configuration)
    }

    private func start(request: URLRequest,
                       configuration: URLSessionConfiguration) async throws -> (URL, URLResponse) {
        try await withCheckedThrowingContinuation { continuation in
            self.continuation = continuation
            let session = URLSession(configuration: configuration, delegate: self, delegateQueue: nil)
            self.session = session
            session.downloadTask(with: request).resume()
        }
    }

    private func finish(_ result: Result<(URL, URLResponse), Error>) {
        guard let continuation else { return }
        self.continuation = nil
        session?.finishTasksAndInvalidate()
        session = nil
        continuation.resume(with: result)
    }

    func urlSession(_ session: URLSession,
                    downloadTask: URLSessionDownloadTask,
                    didWriteData bytesWritten: Int64,
                    totalBytesWritten: Int64,
                    totalBytesExpectedToWrite: Int64) {
        guard totalBytesExpectedToWrite > 0 else { return }
        onProgress(min(1.0, Double(totalBytesWritten) / Double(totalBytesExpectedToWrite)))
    }

    func urlSession(_ session: URLSession,
                    downloadTask: URLSessionDownloadTask,
                    didFinishDownloadingTo location: URL) {
        // `location` is deleted as soon as this method returns, so copy it out now.
        let destination = FileManager.default.temporaryDirectory
            .appendingPathComponent("mySolat-dl-\(UUID().uuidString)")
        do {
            try FileManager.default.moveItem(at: location, to: destination)
            guard let response = downloadTask.response else {
                finish(.failure(URLError(.badServerResponse)))
                return
            }
            finish(.success((destination, response)))
        } catch {
            finish(.failure(error))
        }
    }

    func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        if let error { finish(.failure(error)) }
    }
}
