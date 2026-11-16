<div align="center">

<img src="Resources/logo.png" width="110" alt="mySolat">

# mySolat

**Malaysian prayer times in your macOS menu bar.**

Waktu solat JAKIM — always visible, works offline, and reminds you before each prayer.

<img src="docs/screenshots/menubar.png" width="150" alt="mySolat in the menu bar">

[![CI](https://github.com/syahrul84/mySolat/actions/workflows/ci.yml/badge.svg)](https://github.com/syahrul84/mySolat/actions/workflows/ci.yml)
[![Mac App Store](https://img.shields.io/badge/Mac%20App%20Store-download-0D96F6?logo=apple&logoColor=white)](https://apps.apple.com/app/mysolat/id6831867566)
[![License](https://img.shields.io/badge/license-MIT-blue.svg)](LICENSE)
[![macOS](https://img.shields.io/badge/macOS-13%2B%20·%20Intel%20%26%20Apple%20silicon-lightgrey)](https://apps.apple.com/app/mysolat/id6831867566)

<a href="https://apps.apple.com/app/mysolat/id6831867566"><b>Download on the Mac App Store</b></a>

</div>

---

## A quick look

<table>
<tr>
<td width="42%" valign="top">

<img src="docs/screenshots/popover.png" alt="mySolat popover showing today's prayer times">

</td>
<td valign="top">

**Click the menu bar item** for the whole day at a glance.

- Live countdown to the next prayer
- The current period highlighted, past times dimmed
- Hijri date for the day
- A bell-slash marks any prayer you've muted
- How many days are stored offline, with a refresh button

The menu bar itself can show the prayer name and time, a countdown, or just the icon.

</td>
</tr>
</table>

### Alerts you'll actually notice

Two moments, two popups: a heads-up before the prayer, and the prayer entering. Each stays put until dismissed (or until a timer you set closes it), floats above other apps including full-screen ones — and never steals focus from what you're typing.

<p>
<img src="docs/screenshots/popup-before.png" width="330" alt="Popup: Asar in 15 minutes">
&nbsp;
<img src="docs/screenshots/popup-entered.png" width="330" alt="Popup: Maghrib has entered">
</p>

**They only appear when you're there.** While the Mac is asleep, locked, or showing a screen saver, alerts are held back rather than fired at a screen you can't see — and, importantly, they aren't marked as delivered either. When you unlock, anything missed inside the catch-up window (30 minutes by default, adjustable from 0 to 180) is shown; past that it's retired rather than announced hours late.

If several alerts come due at once after a long sleep, you get the latest one — announcing "Subuh in 15 minutes" when Subuh entered twenty minutes ago would just be wrong.

### Widgets

Small, medium and large — for the desktop and Notification Center.

<p>
<img src="docs/screenshots/widget-small.png" width="150" alt="Small widget: next prayer">
&nbsp;
<img src="docs/screenshots/widget-medium.png" width="320" alt="Medium widget: today's prayer times in two columns">
</p>

<img src="docs/screenshots/widget-large.png" width="320" alt="Large widget: next prayer card and the full day">

## What it does

- **A popup you can't miss** — a panel that stays on screen until you dismiss it, with a sound of your choosing. Notification banners hide themselves after a few seconds; this doesn't.
- **Menu bar countdown** — the next prayer and when it enters, always in view. Five display styles.
- **Notifications too** — native macOS notifications fire alongside the popup, so alerts still reach you when the app isn't frontmost.
- **A heads-up before each prayer** — anywhere from 1 to 120 minutes, so you have time for wudhu or to head to the masjid.
- **Quiet when you're away** — nothing fires at a locked, sleeping or screen-savered Mac. Miss Subuh because the lid was shut? It shows when you come back, if you're within the catch-up window.
- **Works offline** — at least 30 days of prayer times are stored locally (usually ~45). Fly, commute, lose your Wi-Fi; the times are still there.
- **All 60 JAKIM zones** — pick your district, or let mySolat detect it from your location.
- **Updates through the App Store** — like any other Mac app.
- **Universal** — one build runs natively on Apple silicon and Intel.

## Install

Get mySolat free from the **[Mac App Store](https://apps.apple.com/app/mysolat/id6831867566)**. The same App Store page also has mySolat for iPhone.

> **Used the GitHub version before?** Quit it, delete it from Applications, then install mySolat from the App Store. The GitHub version (1.0.6 and earlier) no longer gets updates, and the two are separate apps, so set your zone and alerts again in the new one.

mySolat has **no Dock icon** — look for the crescent in your menu bar.

**Requirements:** macOS 13 Ventura or later, Apple silicon or Intel.

## Setting it up

<table>
<tr>
<td width="50%" valign="top">
<img src="docs/screenshots/settings-location.png" alt="Location settings with the zone picker">
</td>
<td valign="top">

### Location

Search your state, district or JAKIM code — or press **Detect** to find the nearest zone from your location. Your coordinates are used for that one lookup and never stored.

mySolat downloads about 45 days of times straight away, and the footer tells you how much is cached.

</td>
</tr>
<tr>
<td valign="top">
<img src="docs/screenshots/popup-entered.png" alt="The prayer-time popup">
</td>
<td valign="top">

### Alerts

Two moments — **when the prayer time enters**, and a configurable number of **minutes before** it — each available as an on-screen popup, a notification, or both.

Pick the popup sound from the macOS system sounds, set how long it stays up (0 keeps it until you dismiss it), and choose how late a missed alert may still appear after you unlock.

Toggle each prayer individually. The five obligatory prayers are on by default; Imsak, Syuruk and Dhuha are off. Two **Preview** buttons show exactly what each popup will look and sound like.

</td>
</tr>
<tr>
<td valign="top">
<img src="docs/screenshots/settings-appearance.png" alt="Appearance settings with menu bar style options">
</td>
<td valign="top">

### Appearance

Choose what the menu bar shows, with a live preview. Switch to a 24-hour clock, hide the informational markers, and turn on **Launch at login**.

</td>
</tr>
<tr>
<td valign="top">
<img src="docs/screenshots/settings-about.png" alt="About tab showing version, author and licence">
</td>
<td valign="top">

### About

Version, licence and credits.

</td>
</tr>
</table>

### Adding the widget

Right-click the desktop → **Edit Widgets**, search **mySolat**, then drag the size you want. The widget follows the zone and clock format set in the app.

## How it works

| Concern | Approach |
|---|---|
| **Data source** | [waktusolat.app](https://waktusolat.app), which serves JAKIM times. `GET /v2/solat/{zone}` returns a calendar month of UNIX timestamps. |
| **30-day guarantee** | The API is month-granular, so mySolat fetches enough whole months to cover today + 35 days — two normally, three near a month boundary. Cached as JSON and reused until coverage drops below 30 days. |
| **Timezone** | Days are bucketed in `Asia/Kuala_Lumpur`, never the system timezone. A Mac set to another region still shows the correct Malaysian day, and says so in the popover. |
| **Popup delivery** | Popups are raised by the app itself, so they aren't subject to the notification limit. They're `NSPanel`s with `.nonactivatingPanel`, which is what lets them float above other apps — full-screen ones included — and follow you across Spaces without stealing keyboard focus. |
| **Presence detection** | Lock state is queried via `CGSessionCopyCurrentDictionary` rather than tracked purely from notifications, which don't queue while an app is suspended. Display sleep comes from both the `NSWorkspace` notification and a live `CGDisplayIsAsleep` query, because the notification can arrive before the query flips. |
| **Notification limit** | macOS allows 64 *pending* notifications per app. With 5 prayers × 2 alert kinds that's 10 a day, so mySolat schedules a rolling window (~58 requests) and re-arms it hourly, on wake, and whenever settings change. The cached prayer data is unaffected. |
| **App ↔ widget** | A macOS widget extension is sandboxed, so the two share an App Group container. If that's unavailable the widget falls back to fetching its own month, so it never renders an empty box. |
| **Updates** | Delivered by the Mac App Store. |
| **Sandboxing** | The app and the widget are both sandboxed, as the Mac App Store requires. |

## Building from source

**Xcode is not required to build and test.** The Command Line Tools are enough: the `Makefile` drives `swiftc` directly. `mySolat.xcodeproj` is only used to archive the App Store build.

```bash
git clone https://github.com/syahrul84/mySolat.git
cd mySolat
make run
```

| Command | What it does |
|---|---|
| `make` | Universal (arm64 + x86_64) `build/mySolat.app` |
| `make native` | Host architecture only — faster while iterating |
| `make run` | Build, install to `~/Applications`, relaunch |
| `make test` | Run the test suite |
| `make check` | Type-check the app and widget targets |
| `make screenshots` | Regenerate the widget images in this README |
| `make clean` | Remove `build/` and `dist/` |

Stamp a version onto the bundle:

```bash
make VERSION=1.0.7 BUILD_NUMBER=3
```

`make test` hits the live API. To skip that:

```bash
SOLAT_SKIP_NETWORK=1 make test
```

### Layout

```
Sources/Shared/    models, API client, cache, preferences — compiled into both targets
Sources/App/       menu bar app, settings, notifications
Sources/Widget/    WidgetKit extension
Resources/         Info.plists, entitlements, logo, bundled zone list
Tests/             assertion harness (no XCTest — that needs Xcode)
scripts/           icon and widget rendering helpers
docs/screenshots/  the images in this README
```

The shared sources are compiled into both the app and the widget rather than linked as a library, which keeps the build to two plain `swiftc` invocations per architecture.

The widget and popup images above are generated by `make screenshots`, which renders the real views against the real cached times — so they can't drift from the code.

## Releasing

mySolat ships through the Mac App Store. Bump the version in `mySolat.xcodeproj`, archive it in Xcode (**Product › Archive**), then **Distribute App › App Store Connect** and submit the new version for review. The App Store listing text lives in [docs/app-store.md](docs/app-store.md).

GitHub Releases are no longer published.

## Support

mySolat is free and open source. If it's useful to you:

<a href="https://ko-fi.com/syahrul84"><img src="https://img.shields.io/badge/Buy%20me%20a%20coffee-ko--fi-FF5E5B?logo=ko-fi&logoColor=white" alt="Buy me a coffee on Ko-fi"></a>

## Accuracy

Prayer times come from JAKIM via waktusolat.app and are presented unmodified — mySolat applies no calculation of its own. Always defer to your local masjid.

## License

[MIT](LICENSE) © 2026 Syahrul Farhan. Prayer time data belongs to JAKIM and is not covered by this license.
