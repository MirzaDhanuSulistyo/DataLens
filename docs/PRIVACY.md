# DataLens privacy notice

DataLens measures data usage using counters supplied by the operating system. On supported Android devices, this can include device totals, network type, app labels and identifiers, foreground/background accounting, and aggregate hotspot or tethering totals.

DataLens does **not** inspect or store network payloads, URLs, messages, DNS requests, or browsing history. It has no analytics SDK and sends no usage records to a DataLens server.

Usage records, alert preferences, app-alert exclusions, and data-plan settings are stored locally on the device. History retention is configurable in the app. The user can stop monitoring, revoke Android permissions, or delete all local data at any time from Settings.

CSV export and JSON backup are user-initiated. DataLens writes the selected file directly through Android's system document picker; it does not upload the file or choose its destination. A backup contains local usage history, app labels and package identifiers, plans, alerts, preferences, and exclusions. Backup files are not encrypted by DataLens, so users should store and share them securely. Restoring a backup replaces the app's current local data.

The optional home-screen widget reads only the same local aggregate counters. The optional floating overlay shows live transfer speed and requires Android's display-over-other-apps permission.

This notice must be reviewed and supplied with publisher contact details before public release.
