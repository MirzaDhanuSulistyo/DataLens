# DataLens

A privacy-first Flutter data-usage monitor. Android is the primary platform; unsupported iOS counters are never presented as measured data.

## Current milestone: Phase 2 — Android foundation

Implemented:

- Android 10+ app target and narrow package visibility
- Usage-access and notification permission diagnostics
- `TrafficStats` device snapshots with reset/reboot protection
- One-minute foreground-service persistence and live notification speed
- WorkManager reconciliation using `NetworkStatsManager`
- Local SQLite schema for snapshots, deltas, app identities, plans, and alerts
- Device totals, per-app ranking, seven-day history, and live speed UI
- Billing-cycle plans with deduplicated 80% and 100% alerts
- Monitoring restart after reboot, local delete controls, and capability-aware states

Android totals and OEM behavior still require the physical-device acceptance matrix described in [`PRD.md`](PRD.md). Per-app results depend on usage access and OEM support. DataLens stores counters and app labels only; it does not inspect traffic payloads, URLs, or messages.

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
4. Configure **Data plan & billing cycle** to enable threshold alerts.

## Verification

```sh
flutter analyze
flutter test
flutter build apk --debug
```

The debug APK is written to `build/app/outputs/flutter-apk/app-debug.apk`.
