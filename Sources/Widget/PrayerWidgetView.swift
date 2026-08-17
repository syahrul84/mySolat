import SwiftUI
import WidgetKit

extension View {
    /// macOS 14 moved widget backgrounds behind `containerBackground`, and widgets
    /// that don't adopt it are rejected on Sonoma+. On Ventura the widget host
    /// supplies its own background, so the modifier is simply skipped there.
    @ViewBuilder
    func solatWidgetBackground() -> some View {
        if #available(macOS 14.0, *) {
            self.containerBackground(.fill.tertiary, for: .widget)
        } else {
            self.padding(12)
        }
    }
}

struct PrayerWidgetView: View {
    let entry: PrayerEntry
    @Environment(\.widgetFamily) private var family

    var body: some View {
        switch family {
        case .systemSmall: SmallWidget(entry: entry)
        case .systemLarge: LargeWidget(entry: entry)
        default: MediumWidget(entry: entry)
        }
    }
}

// MARK: - Small: next prayer only

struct SmallWidget: View {
    let entry: PrayerEntry

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            if let next = entry.next {
                Label(next.prayer.displayName, systemImage: next.prayer.symbolName)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(.tint)
                    .labelStyle(.titleAndIcon)

                Text(SolatCalendar.string(for: next.date, use24Hour: entry.use24Hour))
                    .font(.system(size: 26, weight: .semibold, design: .rounded))
                    .monospacedDigit()
                    .minimumScaleFactor(0.6)
                    .lineLimit(1)
                    .padding(.top, 1)

                Text(next.date, style: .relative)
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            } else {
                PlaceholderBody()
            }

            Spacer(minLength: 4)

            Text(entry.zoneDescription)
                .font(.system(size: 9))
                .foregroundStyle(.tertiary)
                .lineLimit(2)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

// MARK: - Medium: today's list, two columns

struct MediumWidget: View {
    let entry: PrayerEntry

    private var rows: [PrayerEvent] {
        guard let day = entry.day else { return [] }
        let visible = Set(entry.visiblePrayers)
        return day.events.filter { visible.contains($0.prayer) }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            WidgetHeader(entry: entry)

            if rows.isEmpty {
                PlaceholderBody()
            } else {
                let split = Int((Double(rows.count) / 2).rounded(.up))
                HStack(alignment: .top, spacing: 14) {
                    column(Array(rows.prefix(split)))
                    column(Array(rows.dropFirst(split)))
                }
            }
            Spacer(minLength: 0)
        }
    }

    private func column(_ events: [PrayerEvent]) -> some View {
        VStack(spacing: 3) {
            ForEach(events) { event in
                WidgetRow(
                    event: event,
                    isNext: entry.next?.id == event.id,
                    isPast: event.date < entry.date,
                    use24Hour: entry.use24Hour,
                    compact: true
                )
            }
        }
        .frame(maxWidth: .infinity)
    }
}

// MARK: - Large: full day + countdown

struct LargeWidget: View {
    let entry: PrayerEntry

    private var rows: [PrayerEvent] {
        guard let day = entry.day else { return [] }
        let visible = Set(entry.visiblePrayers)
        return day.events.filter { visible.contains($0.prayer) }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            WidgetHeader(entry: entry)

            if let next = entry.next {
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    Image(systemName: next.prayer.symbolName)
                        .foregroundStyle(.tint)
                    VStack(alignment: .leading, spacing: 0) {
                        Text("\(next.prayer.displayName) · \(SolatCalendar.string(for: next.date, use24Hour: entry.use24Hour))")
                            .font(.system(size: 14, weight: .semibold))
                        Text(next.date, style: .relative)
                            .font(.system(size: 10))
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                }
                .padding(8)
                .background(RoundedRectangle(cornerRadius: 8).fill(.tint.opacity(0.12)))
            }

            if rows.isEmpty {
                PlaceholderBody()
            } else {
                VStack(spacing: 4) {
                    ForEach(rows) { event in
                        WidgetRow(
                            event: event,
                            isNext: entry.next?.id == event.id,
                            isPast: event.date < entry.date,
                            use24Hour: entry.use24Hour,
                            compact: false
                        )
                    }
                }
            }
            Spacer(minLength: 0)
        }
    }
}

// MARK: - Pieces

private struct WidgetHeader: View {
    let entry: PrayerEntry

    var body: some View {
        VStack(alignment: .leading, spacing: 1) {
            Text(entry.zoneDescription)
                .font(.system(size: 11, weight: .semibold))
                .lineLimit(1)
            if let hijri = entry.hijri {
                Text(hijri)
                    .font(.system(size: 9))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
        }
    }
}

private struct WidgetRow: View {
    let event: PrayerEvent
    let isNext: Bool
    let isPast: Bool
    let use24Hour: Bool
    let compact: Bool

    var body: some View {
        HStack(spacing: 5) {
            Image(systemName: event.prayer.symbolName)
                .font(.system(size: compact ? 8 : 10))
                .frame(width: compact ? 11 : 14)
                .foregroundStyle(isNext ? AnyShapeStyle(.tint) : AnyShapeStyle(.secondary))

            Text(event.prayer.displayName)
                .font(.system(size: compact ? 10 : 12, weight: isNext ? .semibold : .regular))
                .lineLimit(1)

            Spacer(minLength: 4)

            Text(SolatCalendar.string(for: event.date, use24Hour: use24Hour))
                .font(.system(size: compact ? 10 : 12, weight: isNext ? .semibold : .regular))
                .monospacedDigit()
                .foregroundStyle(isNext ? AnyShapeStyle(.tint) : AnyShapeStyle(.primary))
        }
        .opacity(isPast && !isNext ? 0.4 : 1)
    }
}

private struct PlaceholderBody: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            Image(systemName: "moon.stars")
                .font(.system(size: 16))
                .foregroundStyle(.secondary)
            Text("Open mySolat")
                .font(.system(size: 11, weight: .medium))
            Text("Pick your zone to load prayer times.")
                .font(.system(size: 9))
                .foregroundStyle(.secondary)
                .lineLimit(2)
        }
    }
}
