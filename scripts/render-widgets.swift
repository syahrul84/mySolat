// Renders the widget views to PNGs for the README.
//
// This draws the real `PrayerWidgetView` with the real `PrayerTimelineProvider`
// entry — the same code and the same cached prayer times the installed widget
// uses — at each family's canonical macOS point size. It exists so the README
// images can be regenerated from source instead of being stale screen grabs.
//
//   make screenshots
//
// Compiled by the Makefile together with Sources/Shared and Sources/Widget.

import AppKit
import SwiftUI
import WidgetKit

@MainActor
func render(_ view: some View, size: CGSize, scale: CGFloat, to url: URL) throws {
    let renderer = ImageRenderer(
        content: view
            .frame(width: size.width, height: size.height)
            .background(WidgetBackdrop())
            .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
    )
    renderer.proposedSize = ProposedViewSize(size)
    renderer.scale = scale

    guard let image = renderer.nsImage,
          let tiff = image.tiffRepresentation,
          let rep = NSBitmapImageRep(data: tiff),
          let png = rep.representation(using: .png, properties: [:])
    else {
        throw NSError(domain: "render", code: 1,
                      userInfo: [NSLocalizedDescriptionKey: "could not rasterise \(url.lastPathComponent)"])
    }
    try png.write(to: url)
    FileHandle.standardOutput.write("✓ \(url.lastPathComponent)\n".data(using: .utf8)!)
}

/// Approximates the widget host's material so the rounded corners read correctly.
private struct WidgetBackdrop: View {
    var body: some View {
        ZStack {
            Color(nsColor: .windowBackgroundColor)
            LinearGradient(
                colors: [Color.white.opacity(0.10), Color.black.opacity(0.10)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        }
    }
}

@main
struct RenderWidgets {
    /// Canonical macOS widget point sizes.
    ///
    /// `\.widgetFamily` is read-only in the environment, so the per-family views
    /// are constructed directly rather than going through `PrayerWidgetView`'s
    /// switch. Same views the widget renders.
    static let families: [(name: String, size: CGSize)] = [
        ("small", CGSize(width: 170, height: 170)),
        ("medium", CGSize(width: 364, height: 170)),
        ("large", CGSize(width: 364, height: 382)),
    ]

    @MainActor
    static func view(for name: String, entry: PrayerEntry) -> AnyView {
        switch name {
        case "small": return AnyView(SmallWidget(entry: entry))
        case "large": return AnyView(LargeWidget(entry: entry))
        default: return AnyView(MediumWidget(entry: entry))
        }
    }

    static func main() async throws {
        let outputDir = URL(fileURLWithPath: CommandLine.arguments.count > 1
                            ? CommandLine.arguments[1]
                            : "docs/screenshots")
        try FileManager.default.createDirectory(at: outputDir, withIntermediateDirectories: true)

        // Prefer the real cache so the README shows genuine times; fall back to the
        // same sample entry the widget gallery previews use.
        let entry: PrayerEntry
        if let cache = PrayerCacheFile.load(), let day = cache.day(containing: Date()) {
            let now = Date()
            entry = PrayerEntry(
                date: now,
                day: day,
                next: cache.upcomingEvents(from: now).first,
                zoneDescription: ZoneCatalog.shared.describe(code: cache.zone),
                hijri: SolatCalendar.formatHijri(day.hijri),
                use24Hour: Preferences().use24HourClock,
                visiblePrayers: Prayer.displayOrder,
                isPlaceholder: false
            )
            FileHandle.standardOutput.write("· using cached times for \(cache.zone)\n".data(using: .utf8)!)
        } else {
            entry = .sample()
            FileHandle.standardOutput.write("· no cache found — using sample times\n".data(using: .utf8)!)
        }

        for spec in families {
            try await MainActor.run {
                try render(
                    view(for: spec.name, entry: entry).padding(14),
                    size: spec.size,
                    scale: 2,
                    to: outputDir.appendingPathComponent("widget-\(spec.name).png")
                )
            }
        }
    }
}
