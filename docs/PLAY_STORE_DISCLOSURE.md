# Google Play policy preparation

## Core purpose

DataLens is an on-device data-usage monitor. Its user-visible core purpose is measuring device, network, app-attributed, and aggregate tethering byte counters and warning about unusual or plan-limit usage.

## Sensitive access disclosure

DataLens requests **Usage access** only after an in-app prominent disclosure. The access is used with Android `NetworkStatsManager` to attribute operating-system byte totals to installed apps. DataLens does not inspect payloads, URLs, messages, DNS requests, or browsing history. The records remain in the app's local SQLite database and can be deleted from Settings.

Package visibility is limited to launchable applications. `QUERY_ALL_PACKAGES` is not requested. App labels are resolved only for UIDs returned by Android usage accounting.

## Other permissions

- `POST_NOTIFICATIONS`: monitoring status, live speed, plan limits, and enabled intelligence alerts.
- Foreground service (`specialUse`): user-enabled continuous counter sampling with an ongoing notification and an immediate stop action.
- `SYSTEM_ALERT_WINDOW`: optional floating speed bubble, requested separately and disabled by default.
- `RECEIVE_BOOT_COMPLETED`: restores monitoring only when the user previously enabled it.
- `ACCESS_NETWORK_STATE`: labels the active transport; it does not read traffic content.

## Data safety draft

- Data collected by the app: device/app byte totals, app label/package identifier, alert preferences, data-plan configuration.
- Data shared off device automatically: none. User-initiated CSV exports and JSON backups are written only to the destination the user selects in Android's system document picker.
- Processing: on device only.
- Encryption in transit: not applicable; DataLens has no backend transport.
- Export/backup: user-initiated local document creation; DataLens has no upload destination or backend.
- Deletion: Settings → Delete all local data.
- Retention: user-selectable 30, 90, or 365 days, or forever; default 365 days.

## Release checklist

- Record Play Console declarations for Usage access, foreground-service special use, and package visibility.
- Publish and link the privacy notice in `docs/PRIVACY.md` from the store listing.
- Capture a video showing the disclosure, Usage access flow, monitoring notification, and stop control.
- Replace debug signing with the release keystore.
- Run the physical-device/OEM acceptance matrix in `PRD.md`.
- Verify screenshots and listing copy never imply payload inspection or iOS parity.
