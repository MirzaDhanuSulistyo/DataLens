# DataLens Monetization Plan

## Status and guiding decision

This is a working commercial hypothesis, not a commitment to ship billing in
the first release. DataLens should validate that users will pay for useful,
trustworthy explanations of mobile data usage before adding a payment wall.

The recommended starting model is a useful free core with a one-time Pro
upgrade. A subscription should wait until DataLens provides an ongoing service
such as encrypted cloud backup or cross-device sync.

## Positioning

DataLens should not be marketed as a generic usage dashboard. Android already
provides basic data totals, and carrier applications provide another source of
plan information. DataLens's valuable outcome is:

> Find which app is wasting your data before it causes an overage.

The supporting promise is:

> See what is using your data. Understand unusual activity. Keep the analysis
> on your device.

DataLens must be honest about measurement. It uses operating-system counters and
best-effort foreground/background signals; it does not inspect traffic payloads,
URLs, messages, DNS requests, or browsing history. It cannot guarantee that its
totals exactly match a carrier bill or detect every event before an overage.

Android is the primary commercial platform because it exposes the strongest
per-app and background usage capabilities. iOS should only be marketed around
the capabilities validated through public APIs and approved entitlements. It
must not imply Android-equivalent system-wide or per-app monitoring on iOS.

## Customer segments

### Plan-conscious Android users

These users have a limited, expensive, prepaid, or metered plan. They need
warnings before a data limit becomes an unexpected charge or service reduction.

### Troubleshooters

These users notice sudden data or battery drain and want to identify the app
responsible without sending usage records to a cloud service.

### Travelers and roaming users

These users need network-type breakdowns and timely warnings when mobile or
roaming usage is costly. The product must label unknown or delayed data rather
than presenting false precision.

### Privacy-conscious Android power users

These users value local processing, no mandatory account, no advertising, and
explicit control over retention, export, and deletion.

The initial audience should be Android users with an acute data-cost or
troubleshooting problem. Users who only want a monthly total are unlikely to
pay for a standalone application.

## Recommended business model

### Free tier

The free tier must solve the basic problem and let users verify that monitoring
works on their device:

- Device usage totals
- Mobile, Wi-Fi, and available hotspot breakdowns
- Current billing-cycle progress and data-plan setup
- Basic 7-day history
- Basic 80% and 100% plan alerts
- A limited top-app view for the current period
- Permission and capability diagnostics
- Local-only storage, retention controls, and delete-all-data

Do not hide basic privacy controls or the monitoring status behind Pro. A user
must be able to understand what DataLens measures and stop or delete it without
paying.

### DataLens Pro

Pro should sell deeper diagnosis and convenience, rather than access to the
user's own basic measurements:

- Full per-app history, filters, and historical comparisons
- Unusual-usage alerts after baseline learning
- Background-usage and new-app alerts where Android supplies a usable signal
- Custom alert thresholds, sensitivity, and app exclusions
- Longer or configurable history beyond the free retention period
- Home-screen widgets
- Optional floating live-speed overlay
- CSV export and backup/restore workflows
- Advanced usage reports and reconciliation details

Per-app attribution is a best-effort Android capability, not a carrier-grade
accounting guarantee. Pro copy must show data quality, stale state, and
uncertainty when the operating system cannot provide a complete result.

### Pricing progression

Use staged one-time pricing while the product has no backend or recurring
infrastructure:

- Private beta founder offer: `$9.99-$14.99` one-time
- Initial public launch: approximately `$19.99` for Pro
- Mature Android product with reliable intelligence and widgets: approximately
  `$29.99`

The founder offer should be limited and used to measure willingness to pay, not
as evidence that every future user will accept the same price. Avoid promising
unlimited support or every future major version until maintenance and support
costs are understood. Major versions can be sold separately if a substantial
new product is released.

Do not add a family plan in v1. DataLens does not support family sharing or
multi-device aggregation in the current product scope.

### When a subscription becomes justified

Consider recurring pricing only if DataLens adds a continuing service with
ongoing cost or value, such as:

- End-to-end encrypted cross-device sync
- Encrypted cloud backup and recovery
- Family sharing
- Continuous breach or plan intelligence supplied by a service

A subscription is difficult to justify for a local monitor that has no account,
backend, or recurring cloud feature.

## Product strategy

The product should monetize the diagnosis loop:

1. DataLens notices an unusual or costly pattern.
2. The user can see the app, amount, period, network, comparison, and confidence.
3. The user takes an action, such as changing the app's settings or monitoring
   the next billing cycle.

Charts and counters support this loop but are not the primary paid value. The
paid experience must help answer what happened and what the user can do next.

Do not market the following as guarantees:

- Exact carrier-bill accuracy
- Guaranteed detection before an overage
- Definitive causes of background traffic
- Truly live home-screen widgets
- Android-level per-app monitoring on iOS

Do not use advertising, sell usage data, or add affiliate recommendations that
weaken the privacy promise. Analytics and crash reporting, if ever introduced,
must be opt-in and must exclude usage records, package lists, and byte history.

## Technical feasibility boundaries

The paid plan depends on features that are feasible, but each has a clear
boundary:

- **Per-app attribution:** Android `NetworkStatsManager` and usage access can
  provide UID-level accounting, with OEM, permission, and unattributed-traffic
  gaps.
- **Unusual-usage alerts:** Baselines can become useful after at least 7 days
  and more reliable around 14 days; robust thresholds and cooldowns are needed
  to control false positives.
- **Background explanations:** Android usage events can provide a best-effort
  foreground/background correlation, but cannot prove why an app transferred
  data.
- **Plan warnings:** Local cycle calculations and notifications are feasible,
  but warnings can be delayed by OS restrictions and may differ from carrier
  accounting.
- **Battery impact:** A foreground service and sampling strategy can target low
  overhead, but the result must be measured across reference devices and OEMs.
- **Widgets and live monitoring:** Android widgets are snapshot surfaces with
  OS refresh limits; the persistent notification and in-app screen are the
  appropriate live surfaces.
- **Local privacy:** No account, ads, backend, or automatic usage upload is
  required. User-created exports and backups still need explicit security copy
  and, preferably, encryption.

## Validation plan

Before investing in a large paid feature set or cloud service:

1. Create a landing page using the message: "Find what is wasting your data
   before it causes an overage."
2. Recruit 20-30 Android users across stock Android and major OEM devices.
3. Run a private beta for at least two billing cycles where possible.
4. Offer a founder Pro purchase at `$9.99-$14.99`.
5. Measure monitoring activation, data-plan setup, weekly usage, alert opens,
   useful/not-useful feedback, retention, battery impact, reconciliation, and
   purchase conversion.
6. Interview users who decline payment and users who disable alerts.

The first success target is repeated user action and willingness to pay, not
feature count. If users do not trust the measurements or do not act on alerts,
additional charts and settings will not make the product sellable.

## Release requirements before charging

DataLens handles sensitive usage information and requests sensitive Android
access. Before commercial release:

- Verify per-app attribution and reconciliation on the agreed physical-device
  and OEM matrix.
- Document that OS counters are measured totals and may differ from carrier
  accounting.
- Demonstrate that unusual-usage alerts avoid duplicate, noisy, and misleading
  notifications.
- Benchmark battery and storage impact for foreground monitoring and recovery
  after process death, reboot, and permission changes.
- Confirm that the free tier works after optional permissions are denied.
- Complete Google Play disclosures for Usage Access, foreground service,
  package visibility, notifications, and overlay behavior.
- Publish a privacy notice, security model, retention policy, support channel,
  and clear platform limitations.
- Encrypt exported backups or make their unencrypted nature unmistakable and
  provide safe handling guidance before presenting backup as a Pro benefit.
- Test purchase, restore, entitlement, refund, and device migration flows.
- Test iOS capabilities and App Review requirements before charging for any
  iOS-specific monitoring claim.
- Use release signing, release CI, crash-handling procedures, and a process for
  responding to Android OS and OEM changes.

## Success metrics

Track only aggregate, privacy-safe metrics with explicit consent:

- Onboarding completion
- Monitoring activation
- Data-plan configuration
- Seven-day and thirty-day retention
- Alert open and useful/not-useful rates
- Widget and overlay adoption
- Successful sample freshness
- Battery benchmark results
- Reconciliation error against Android system totals
- Pro purchase conversion and refund rate

The commercial gate should require all of the following before expanding the
paid feature set:

- Users repeatedly return to investigate usage.
- Medium-sensitivity alerts are considered useful by most active testers.
- Monitoring meets the agreed freshness and battery targets on supported
  devices.
- The product has a clear Android audience willing to pay.
- Support and policy obligations are understood.

## Summary

DataLens is not likely to sell as a generic charting utility. Its viable niche
is Android users who need to prevent data overages or investigate unexpected
usage and who prefer local processing.

The best first model is a free, trustworthy monitoring core with a `$19.99`
one-time Pro upgrade, preceded by a lower-priced founder beta. Pro should focus
on diagnosis, alerts, history, and glance surfaces. Subscriptions should wait
for a real ongoing service, and all commercial claims must remain limited to
what Android and iOS can actually measure.
