# DataLens — Product Requirements Document

**Status:** Draft 1.0  
**Platforms:** Android and iOS  
**Client:** Flutter  
**Design system:** [Andura UI](../andura-ui) (`packages/flutter`)  
**Primary launch platform:** Android  

## 1. Product summary

DataLens is a privacy-first mobile data-usage monitor that helps people understand which apps use network data, see current transfer speed, stay within a monthly data plan, and catch abnormal or unexpected background usage.

Android receives the complete monitoring experience. iOS receives the strongest experience allowed by Apple’s public APIs and granted entitlements; the product must never imply that standard iOS APIs can provide Android-equivalent per-app usage.

## 2. Problem

Mobile operating systems expose network totals in fragmented ways, make historical comparisons difficult, and often hide costly background activity. Users need one glanceable place to answer:

- How much mobile and Wi-Fi data have I used today and this billing cycle?
- Which app used it?
- Is data being consumed right now, and at what speed?
- Is an app behaving unusually or using data in the background?
- Am I close to my plan limit?

## 3. Goals

1. Reliably log network usage without requiring the app to remain open.
2. Separate upload/download and mobile/Wi-Fi/roaming usage where platform APIs permit.
3. Provide actionable per-app insights and anomaly alerts on Android.
4. Show live speed and useful daily, weekly, monthly, and billing-cycle history.
5. Keep all usage history and baseline analysis on device by default.
6. Offer home/lock-screen glance surfaces and deep links into relevant details.
7. Be explicit about platform limitations and permission impact.

## 4. Non-goals

- Inspecting payload contents, URLs, messages, or browsing history.
- Blocking apps or enforcing a hard operating-system data limit.
- Claiming byte-perfect accuracy against carrier billing; carrier accounting may differ.
- Circumventing iOS sandbox or App Store policy.
- Cloud sync, family plans, or multi-device aggregation in the first release.
- Shipping a desktop or web client.

## 5. Target users

- **Plan-conscious user:** has a metered plan and wants billing-cycle alerts.
- **Troubleshooter:** wants to identify the app causing sudden battery/data drain.
- **Privacy-conscious user:** wants visibility into unexpected background transfers without sending telemetry to a server.
- **Power user:** wants live speed, persistent indicators, widgets, and detailed filtering.

## 6. Product principles

- **Honest by platform:** unavailable data is labeled “Not available,” never estimated and presented as measured.
- **Local first:** raw usage data, app inventory, and learned baselines remain on device.
- **Explain every alert:** identify the app/source, interval, amount, comparison, and network type.
- **Low overhead:** monitoring should not materially increase battery or data usage.
- **Progressive permissioning:** request a permission only when its related feature is introduced.

## 7. Platform capability contract

| Capability | Android | iOS |
|---|---|---|
| Device totals | `TrafficStats` for live deltas; `NetworkStatsManager` for historical totals | Aggregate app-observed/tunnel traffic only; no public system-wide counter |
| Per-app/UID usage | Supported through `NetworkStatsManager`/usage access where OEM and OS allow | Not available through normal public APIs; a packet-tunnel provider does not guarantee reliable source-app attribution |
| Mobile vs Wi-Fi | Supported | Supported only for traffic visible to the app/tunnel, using `NWPathMonitor` path state |
| Roaming | Best effort; tag current mobile state and surface “unknown” when unavailable | Best effort for tunnel-visible traffic; may be unknown |
| Background logging | Foreground service plus scheduled reconciliation | OS-scheduled background work is opportunistic; continuous collection requires an approved Network Extension use case/entitlement |
| Live speed | Supported; app, foreground service notification, optional overlay | In-app/tunnel-visible speed only; no true floating overlay or continuously refreshing widget |
| Installed/new app detection | Supported with package visibility constraints and store-policy review | Unsupported for other installed apps |
| Foreground/background app state | Best effort via usage events/access | Unsupported for other apps |
| Home-screen widget | Supported | Supported with WidgetKit refresh limits |
| Lock-screen surface | Device/API-dependent | WidgetKit on iOS 16+, subject to timeline limits |

### iOS release gate

Before committing to VPN-based collection, the team must validate Apple Network Extension entitlement eligibility, App Review acceptability, packet-tunnel architecture, user consent copy, and whether the approved implementation provides useful attribution. If entitlement approval is not obtained, iOS launches as a plan tracker for manually entered/carrier-derived totals plus DataLens’s own observed traffic; unsupported per-app and system-wide claims are removed.

## 8. Scope and prioritization

### P0 — Android MVP

- Permission onboarding and capability diagnostics.
- Background snapshots and reconciliation.
- Device and per-app upload/download usage.
- Mobile/Wi-Fi separation; roaming when available.
- Today, 7-day, month, and billing-cycle history.
- In-app live speed and persistent notification.
- Data cap, billing-cycle reset, and 80%/100% alerts.
- Per-app details and foreground/background classification where available.
- Local-only persistence, export/delete controls, and core settings.

### P1 — Android intelligence and glance surfaces

- Baseline learning and configurable spike alerts.
- One-time new-app traffic alerts.
- Floating live-speed overlay, opt-in.
- Small and medium home-screen widgets.
- Android lock-screen equivalent where supported.

### P1 — iOS constrained release

- Capability-aware onboarding.
- Aggregate collection only after entitlement/prototype validation.
- History, data-plan progress, alerts, and widgets for available data.
- Clear “iOS limitation” states instead of empty per-app screens.

### P2

- CSV export and backup/restore.
- Custom alert thresholds and app exclusions.
- Optional app categories.
- More robust OEM-specific setup guidance.

## 9. Functional requirements

### FR-1: Onboarding and permissions

1. Explain the value and privacy impact before every system permission prompt.
2. Android setup may request:
   - Usage access (`PACKAGE_USAGE_STATS`) for per-app network and foreground/background analysis.
   - Notification permission on Android 13+.
   - Foreground service declarations/permissions required by the target SDK.
   - Overlay permission only when the user enables the floating speed bubble.
   - Phone/telephony access only if strictly required for the chosen API path; avoid `READ_PHONE_STATE` when network capabilities provide sufficient information.
3. Package visibility must use the narrowest Play-compliant mechanism; broad installed-app access requires policy review.
4. iOS must explain VPN profile/Network Extension behavior before invoking system setup.
5. A diagnostics screen shows each capability as **Available**, **Limited**, **Permission needed**, or **Unavailable on this platform**.
6. Users can continue with reduced functionality after denying optional permissions.

**Acceptance:** No dashboard screen is blocked by an unexplained permission dialog, and each denied capability has a recovery action.

### FR-2: Data tracking engine

1. Collect cumulative received/sent byte counters and calculate usage from counter deltas.
2. Store snapshots approximately every minute while continuous Android monitoring is active; scheduled reconciliation fills recoverable gaps after process death/reboot.
3. Attribute records to app/UID where supported.
4. Tag records with `mobile`, `wifi`, `roaming`, `vpn`, `other`, or `unknown` and preserve uncertainty.
5. Detect counter reset, reboot, app reinstall/UID changes, clock changes, and negative deltas; never record a negative usage value.
6. Avoid double counting when combining live counters and OS historical buckets.
7. Start monitoring after reboot only when the user previously enabled it and platform policy permits.
8. Display the latest successful sample time and stale status.

**Acceptance:** In controlled Android transfer tests, totals remain within ±10% of OS-reported usage over 24 hours, with no duplicate records across restart/reboot scenarios.

### FR-3: Live speed monitor

1. Compute download and upload speed as positive byte delta divided by monotonic elapsed time.
2. Update the in-app display every 1 second while visible; use smoothing over a short rolling window to reduce jitter.
3. Android persistent notification shows current down/up speed and opens Live Monitor.
4. Android overlay is optional, draggable, dismissible, and never enabled implicitly.
5. If counters are stale or unavailable, show `—` rather than `0`.

**Acceptance:** A controlled transfer appears in the live display within 2 seconds on Android while monitoring is active.

### FR-4: Historical usage

1. Provide daily, weekly, monthly, and billing-cycle views.
2. Provide bar charts for daily totals and line charts for trends.
3. Filter by all/mobile/Wi-Fi/roaming/unknown and upload/download.
4. Rank apps by total usage and show each app’s historical chart.
5. Preserve app label/icon snapshots so removed apps remain understandable in history.
6. Roll up minute/hour data into daily aggregates and apply retention rules.

**Acceptance:** The sum of app rows plus unattributed usage reconciles to the displayed total for the selected interval and filters.

### FR-5: Data plan and limits

1. User sets cap size, unit (MB/GB), and billing-cycle start day (1–31).
2. For short months, a start day beyond the final date resolves to that month’s final date.
3. Show used, remaining, percentage, and days left.
4. Send one alert at 80% and one at 100% per billing cycle by default.
5. Automatically begin a new cycle at local midnight on the resolved cycle date without deleting history.
6. If permission/data gaps reduce confidence, label the estimate as incomplete.

**Acceptance:** Cycle calculations pass timezone, DST, leap-year, and month-length tests.

### FR-6: Unusual usage and new-app alerts

1. Build per-app baselines after at least 7 complete days; improve confidence through day 14.
2. Maintain separate hourly and daily baselines, segmented by network type when sufficient samples exist.
3. Compare current usage with the app’s own baseline and require both a ratio and minimum-byte floor to avoid noisy alerts.
4. Default sensitivity policy:
   - **Off:** no anomaly alerts.
   - **Low:** ≥3× baseline and ≥250 MB/day or ≥100 MB/hour.
   - **Medium:** ≥2.5× baseline and ≥100 MB/day or ≥50 MB/hour.
   - **High:** ≥2× baseline and ≥50 MB/day or ≥20 MB/hour.
5. Use robust statistics (median and median absolute deviation where sample volume allows), not a single global average.
6. Alert once per app/anomaly window, with a cooldown to prevent repeated notifications.
7. New-app detection alerts once when a previously unseen app first records meaningful traffic; app installs with zero traffic do not alert.
8. Background-usage alerts require a reliable foreground/background signal and include confidence/status.
9. Notification format: “Chrome used 450 MB on mobile data in the last hour — 5× its usual rate.”
10. Alert details show actual amount, baseline, comparison period, network, background status, and suggested actions.

**Acceptance:** Baseline state survives restart, sensitivity changes take effect for future evaluations, and identical windows do not generate duplicate notifications.

### FR-7: Widgets and deep links

1. Small widget: today’s total, mobile/Wi-Fi split, and data-cap progress.
2. Medium widget: small content plus last 7 days mini bar chart.
3. Android live-speed widget updates at the fastest policy-compliant cadence; UI must disclose that launcher widgets are not guaranteed every few seconds.
4. iOS lock/home widgets use WidgetKit timelines and show last-updated time; they must not promise live speed.
5. Tapping a metric opens its matching filtered screen via a versioned deep link.
6. Widget data is written to platform shared storage using an atomic, minimal snapshot.

**Acceptance:** Widget tap lands on the expected route, and stale widget data is visibly labeled.

### FR-8: Settings and data controls

- Unit preference: decimal MB/GB by default, with optional binary units if added later.
- Alert sensitivity and per-alert-category switches.
- Data-plan cap and billing-cycle day.
- Widget refresh preference within OS limits.
- System/light/dark theme.
- Persistent notification and overlay controls on Android.
- Retention period and “Delete all data.”
- Permission diagnostics and OS settings shortcuts.
- Privacy explanation and app version.

## 10. Information architecture

Bottom navigation:

1. **Overview** — live speed, today, plan progress, network split, 7-day trend, top apps, active alerts.
2. **Apps** — ranked app list, search/filter, app detail and history.
3. **History** — day/week/month/cycle charts and filters.
4. **Alerts** — anomaly/new-app/background events, read state, detail, dismiss.
5. **Settings** — plan, monitoring, widgets, permissions, appearance, data/privacy.

On iOS, unavailable destinations are replaced by capability-aware aggregate views rather than disabled Android-shaped screens.

### Key empty/error states

- Monitoring not configured.
- Waiting for first sample.
- Permission revoked.
- Baseline learning: “4 of 7 days learned.”
- No activity in selected interval.
- Data unavailable due to OS restriction.
- Partial history/data gap.

## 11. Visual and interaction design

### Andura UI dependency

Use the local package during development:

```yaml
dependencies:
  andura_ui:
    path: ../andura-ui/packages/flutter
```

Pin a release tag for CI/production. Import `package:andura_ui/andura_ui.dart` and apply one product-approved Andura system consistently through `AnduraTheme.forSystem(...)`; do not copy or fork Andura primitives into DataLens.

### Component mapping

| Product need | Andura component |
|---|---|
| Screen scaffold | `AnduraPage`, `AnduraResponsiveContainer` |
| Summary/metric surfaces | `AnduraCard`, `AnduraStat` |
| Cap progress | `AnduraProgress` |
| Network/time filters | `AnduraChip`, `AnduraTabs`, `AnduraSelect` |
| App and alert rows | `AnduraListItem`, `AnduraBadge` |
| Settings | `AnduraSettingsTile`, `AnduraSwitch`, `AnduraChoiceRow` |
| Permission and anomaly messages | `AnduraAlert`, `AnduraDialog`, `AnduraBottomSheet` |
| Loading/empty/error | `AnduraSkeleton`, `AnduraEmptyState`, `AnduraErrorText` |
| Actions | `AnduraButton`, `AnduraIconButton`, `AnduraLink` |
| Layout | `AnduraResponsiveGrid`, `AnduraDivider`, `AnduraSectionHeader` |

Charts, speed gauges, app-icon rows, and widget layouts are product-specific compositions. They must consume `AnduraThemeTokens.of(context)` for semantic color, typography, spacing, radius, motion, and elevation. Do not introduce hard-coded colors or spacing when a token exists.

### Accessibility

- Meet WCAG 2.2 AA contrast for app UI.
- Respect text scaling, reduced motion, screen readers, and 44×44 dp minimum targets.
- Never encode network type or alert severity by color alone.
- Give every chart a textual summary and accessible data table/list alternative.
- Format byte values and dates using locale-aware utilities.
- Announce stale/partial data and progress values semantically.

## 12. Technical architecture

### Flutter application

Use a feature-first structure with presentation, domain, and data boundaries. Recommended modules:

- `core`: time, units, errors, permissions, deep links, Andura theme setup.
- `tracking`: snapshots, attribution, network tagging, reconciliation.
- `live_speed`: stream and smoothing.
- `history`: aggregation, filters, charts.
- `plans`: cycle calculations and thresholds.
- `alerts`: baselines, anomaly evaluation, notification state.
- `apps`: app identity and historical details.
- `widgets`: shared widget snapshots and routes.
- `settings`: preferences, retention, privacy controls.

Use typed platform channels or Pigeon contracts between Dart and native collectors. Keep collection native because Flutter isolates are not a reliable substitute for Android foreground services or iOS extensions.

### Android native layer (Kotlin)

- `TrafficStats` for lightweight current device/UID deltas where applicable.
- `NetworkStatsManager` for authoritative query/reconciliation subject to usage access.
- `ConnectivityManager`/network capabilities for current transport.
- Telephony roaming state only when permission/policy allows; otherwise `unknown`.
- Foreground service for user-enabled continuous monitoring and notification.
- WorkManager for periodic reconciliation/rollup, not one-minute exact scheduling.
- Usage events for best-effort foreground/background classification.
- AppWidget/Glance or native AppWidget integration for widgets.

### iOS native layer (Swift)

- `NWPathMonitor` for current path classification, not system-wide byte totals.
- Network Extension packet tunnel only after entitlement and review validation.
- BGTaskScheduler for opportunistic maintenance.
- WidgetKit with App Group snapshot storage.
- Native provider/app communication through an App Group and minimal aggregate records.

### Persistence

Use one encrypted-at-rest-by-OS local SQLite database accessible to the Flutter app, with Drift or an equivalent typed migration layer. Native collectors write through a narrow repository/channel contract; if extension/process constraints require native stores, synchronize idempotent event batches into the canonical database. Do not split business truth across Room and Core Data unless the prototype proves it necessary.

Suggested entities:

- `usage_snapshot(id, captured_at_utc, monotonic_marker, boot_id, network_type, rx_total, tx_total, source, quality)`
- `usage_delta(id, interval_start_utc, interval_end_utc, app_identity_id?, network_type, foreground_state, rx_bytes, tx_bytes, quality)`
- `daily_usage(local_date, app_identity_id?, network_type, rx_bytes, tx_bytes, completeness)`
- `app_identity(id, platform_key, package_or_bundle_id?, label_snapshot, first_seen_at, last_seen_at)`
- `data_plan(id, cap_bytes, cycle_day, enabled)`
- `baseline(app_identity_id, granularity, network_type, sample_count, center, dispersion, updated_at)`
- `alert_event(id, type, app_identity_id?, window_start, actual_bytes, baseline_bytes?, ratio?, state, dedupe_key)`
- `permission_state(capability, status, checked_at)`
- `settings(key, value)`

Store timestamps in UTC and derive billing/local-day boundaries using the user’s current timezone. Persist a quality/completeness marker with aggregates.

### Retention

- Raw/minute snapshots: 7 days.
- Hourly/app deltas: 90 days.
- Daily aggregates and alert events: until user deletion, with a configurable future policy.
- Rollups must complete transactionally before source rows are purged.

### Privacy and security

- No account or backend is required.
- No raw traffic payload or destination content is stored.
- Analytics/crash reporting, if introduced, is opt-in and must exclude app-usage records, package lists, VPN traffic, and byte histories.
- Exports require explicit action and a platform share sheet.
- Document VPN behavior clearly: routing/measurement is not equivalent to reading content.
- Complete Google Play usage-access, foreground-service, VPN, and package-visibility policy reviews plus Apple Network Extension review before release.

## 13. Non-functional requirements

- **Battery:** target <2% additional battery over 24 hours in typical monitoring use on reference Android devices.
- **CPU:** background average <1% outside active aggregation; no busy polling.
- **Storage:** target <50 MB after 90 days for typical usage.
- **Reliability:** ≥99% crash-free sessions; collector restarts safely after process death.
- **Freshness:** Android live screen ≤2 seconds; overview ≤2 minutes while monitoring; widgets clearly state OS-limited freshness.
- **Startup:** usable shell in <2 seconds on a mid-range reference device, excluding permission/system UI.
- **Offline:** all core features work without internet access.
- **Compatibility:** define exact minimum OS versions during technical discovery; proposed baseline Android 10+ and iOS 16+.

## 14. Analytics and success metrics

Only collect aggregate, privacy-safe product telemetry with explicit consent.

- Onboarding completion rate.
- Percentage enabling usage access/background monitoring.
- 7-day and 30-day retention.
- Percentage configuring a data plan.
- Alert open, dismiss, and “not useful” rates.
- False-positive proxy by sensitivity and alert type.
- Widget adoption.
- Collector freshness/reliability and battery benchmark results.
- Reconciliation error against OS-reported totals in test labs.

**Initial success targets:**

- ≥70% Android onboarding completion.
- ≥50% of activated users configure a plan or enable an alert.
- ≥95% of active Android devices have a successful sample in the prior 15 minutes while monitoring is enabled and the OS permits execution.
- <10% “not useful” feedback on medium-sensitivity alerts after baseline maturity.

## 15. QA and acceptance strategy

Test on stock Android and major OEM variants, multiple API levels, iPhone simulator/device where APIs differ, mobile/Wi-Fi transitions, VPN coexistence, roaming simulation where possible, airplane mode, dual-SIM, reboot, force-stop, app update, permission revoke, DST/timezone changes, and month boundaries.

Required automated coverage:

- Delta, reset, deduplication, and reconciliation logic.
- Billing-cycle boundaries.
- Unit formatting.
- Baseline and sensitivity thresholds.
- Database migrations and rollups.
- Deep-link routing.
- Widget snapshot serialization.
- Capability-based UI states.
- Golden/accessibility tests for principal screens using Andura light/dark themes and large text.

No release may claim iOS system-wide or per-app monitoring without device evidence and entitlement approval.

## 16. Delivery milestones

1. **Discovery/prototype (2–3 weeks):** Android counter accuracy, OEM behavior, power benchmark, iOS entitlement feasibility, data model, Andura-themed shell.
2. **Android foundation (4–6 weeks):** permissions, collector, persistence, overview, apps, history, plan alerts.
3. **Android intelligence (3–4 weeks):** baselines, anomalies, background/new-app signals, notification/overlay.
4. **Widgets and hardening (2–3 weeks):** Android widgets, deep links, retention, accessibility, policy preparation.
5. **iOS constrained implementation (schedule after gate):** implement only validated capabilities and WidgetKit surfaces.

Milestones are directional and require engineering estimation after the prototypes.

## 17. Risks and mitigations

| Risk | Impact | Mitigation |
|---|---|---|
| iOS lacks public per-app/system-wide counters | Core parity impossible | Android-first positioning; entitlement prototype; capability-aware iOS scope |
| Android OEM/API inconsistencies | Missing or inaccurate records | Reconciliation, quality flags, OEM test matrix, diagnostic screen |
| One-minute background cadence drains battery or violates policy | Poor reviews/store rejection | Foreground service only with clear value; adaptive sampling; WorkManager for coarse work |
| Package visibility/usage access policy rejection | Per-app feature blocked | Narrow queries, prominent disclosure, legal/store review before implementation lock |
| Double counting across sources | Incorrect totals | Source precedence rules, boot/session IDs, idempotent intervals, reconciliation tests |
| False-positive anomaly alerts | User disables notifications | Learning period, byte floors, robust baseline, cooldown, sensitivity controls |
| Widgets cannot update every few seconds | Misleading live feature | Platform-specific copy, last-updated label, persistent Android notification for truly live data |
| VPN conflicts or user trust concerns | iOS adoption/review failure | No payload logging, transparent disclosure, easy disable/delete, do not promise attribution |

## 18. Open questions

1. Is Android-only acceptable for the complete v1, with iOS positioned as a limited companion?
2. Does the organization already have, or qualify for, Apple’s Network Extension entitlement?
3. Which exact Andura visual system ID is the product choice, or should DataLens use the default Andura theme?
4. Is 1-minute logging worth the battery/foreground-service tradeoff, or should cadence adapt when the screen is off/idle?
5. Should VPN traffic be shown as its own transport or attributed to the underlying mobile/Wi-Fi path?
6. What retention/export expectations apply to app-level usage data?
7. Which countries/carriers and dual-SIM scenarios must billing-cycle estimates support at launch?
8. Is Play Store distribution required, and has usage-access/package-visibility policy eligibility been reviewed?

## 19. Definition of done for v1

Android v1 is complete when P0 requirements pass acceptance tests on the agreed device matrix, totals reconcile within the defined tolerance, monitoring survives restart/reboot within OS constraints, plan alerts deduplicate correctly, all primary states use Andura UI/tokens, accessibility checks pass, privacy/delete controls work, and store-policy disclosures are approved. iOS is not considered feature-parity scope and ships only after the capability gate documents exactly what is measured.
