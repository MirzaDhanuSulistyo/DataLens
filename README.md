# DataLens

A privacy-first Flutter data-usage monitor. Android is the primary platform; unsupported iOS counters are never presented as measured data.

## Current milestone: Phase 4 — Widgets and hardening

Implemented:

- Android 10+ app target and narrow package visibility
- Usage-access and notification permission diagnostics
- `TrafficStats` device snapshots with reset/reboot protection
- One-minute foreground-service persistence and live notification speed
- WorkManager reconciliation using `NetworkStatsManager`
- Local SQLite schema for snapshots, deltas, app identities, plans, and alerts
- Device totals, per-app ranking, 24-hour and seven-day history, and live speed UI
- Aggregate hotspot/tethering totals, sessions, history, and separate category UI
- Billing-cycle plans with deduplicated 80% and 100% alerts
- Per-app daily baselines using median/MAD after seven complete learning days
- Configurable unusual-usage, new-app, and background-usage alerts with deduplication
- Opt-in draggable/dismissible Android live-speed overlay
- Monitoring restart after reboot, local delete controls, and capability-aware states
- Configurable Android home-screen widget for today or billing-cycle usage
- Widget, notification, and `datalens://open/<screen>` deep links
- Automatic 30/90/365-day or forever retention controls
- Prominent usage-access disclosure, accessibility semantics, and Play policy documentation

Android totals and OEM behavior still require the physical-device acceptance matrix described in [`PRD.md`](PRD.md). Per-app and tethering results depend on usage access and OEM support. Hotspot traffic is aggregate: Android does not identify apps used on connected devices. DataLens stores counters and app labels only; it does not inspect traffic payloads, URLs, or messages.

## Run

The local Andura UI package must exist at `../andura-ui/packages/flutter`.

```sh
flutter pub get
flutter test
flutter run -d <android-device>
```

In the app:

1. Open **Settings → Grant usage access** and enable DataLens.
2. Enable **Background monitoring**.
3. Use **Reconcile app usage now** after generating mobile or Wi-Fi traffic.
4. Turn on Android hotspot/tethering and select the **Hotspot** filter to see aggregate usage and daily history.
5. Configure **Data plan & billing cycle** to enable threshold alerts.
6. Add the **DataLens** home-screen widget from the Android widget picker and configure it in Settings.

Deep links support `overview`, `apps`, `history`, `alerts`, and `settings`, for example `datalens://open/history`.

Release policy drafts are in [`docs/PLAY_STORE_DISCLOSURE.md`](docs/PLAY_STORE_DISCLOSURE.md) and [`docs/PRIVACY.md`](docs/PRIVACY.md).

## Verification

```sh
flutter analyze
flutter test
flutter build apk --debug
```

The debug APK is written to `build/app/outputs/flutter-apk/app-debug.apk`.
