package io.andura.datalens.tracking

import android.content.ContentValues
import android.content.Context
import android.database.sqlite.SQLiteDatabase
import android.database.sqlite.SQLiteOpenHelper
import android.util.JsonReader
import android.util.JsonToken
import android.util.JsonWriter
import java.io.InputStream
import java.io.OutputStream
import java.io.OutputStreamWriter
import java.time.Instant

class UsageDatabase(context: Context) :
    SQLiteOpenHelper(context, "datalens.db", null, VERSION) {

    override fun onConfigure(db: SQLiteDatabase) {
        db.setForeignKeyConstraintsEnabled(true)
        db.enableWriteAheadLogging()
    }

    override fun onCreate(db: SQLiteDatabase) {
        db.execSQL(
            """CREATE TABLE usage_snapshot(
                id INTEGER PRIMARY KEY AUTOINCREMENT,
                captured_at_utc INTEGER NOT NULL,
                monotonic_marker INTEGER NOT NULL,
                boot_id TEXT NOT NULL,
                network_type TEXT NOT NULL,
                rx_total INTEGER NOT NULL,
                tx_total INTEGER NOT NULL,
                source TEXT NOT NULL,
                quality TEXT NOT NULL
            )"""
        )
        db.execSQL(
            """CREATE TABLE app_identity(
                id INTEGER PRIMARY KEY AUTOINCREMENT,
                platform_key TEXT NOT NULL UNIQUE,
                package_or_bundle_id TEXT,
                label_snapshot TEXT NOT NULL,
                first_seen_at INTEGER NOT NULL,
                last_seen_at INTEGER NOT NULL,
                excluded_from_alerts INTEGER NOT NULL DEFAULT 0
            )"""
        )
        db.execSQL(
            """CREATE TABLE usage_delta(
                id INTEGER PRIMARY KEY AUTOINCREMENT,
                interval_start_utc INTEGER NOT NULL,
                interval_end_utc INTEGER NOT NULL,
                app_identity_id INTEGER,
                network_type TEXT NOT NULL,
                foreground_state TEXT NOT NULL DEFAULT 'unknown',
                rx_bytes INTEGER NOT NULL CHECK(rx_bytes >= 0),
                tx_bytes INTEGER NOT NULL CHECK(tx_bytes >= 0),
                quality TEXT NOT NULL,
                dedupe_key TEXT NOT NULL UNIQUE,
                FOREIGN KEY(app_identity_id) REFERENCES app_identity(id)
            )"""
        )
        db.execSQL(
            """CREATE TABLE data_plan(
                id INTEGER PRIMARY KEY CHECK(id = 1),
                cap_bytes INTEGER NOT NULL,
                cycle_day INTEGER NOT NULL CHECK(cycle_day BETWEEN 1 AND 31),
                enabled INTEGER NOT NULL DEFAULT 1
            )"""
        )
        db.execSQL(
            """CREATE TABLE alert_event(
                id INTEGER PRIMARY KEY AUTOINCREMENT,
                type TEXT NOT NULL,
                window_start INTEGER NOT NULL,
                window_end INTEGER,
                app_identity_id INTEGER,
                actual_bytes INTEGER NOT NULL,
                baseline_bytes INTEGER,
                ratio REAL,
                network_type TEXT,
                foreground_state TEXT,
                state TEXT NOT NULL DEFAULT 'unread',
                dedupe_key TEXT NOT NULL UNIQUE,
                created_at INTEGER NOT NULL,
                FOREIGN KEY(app_identity_id) REFERENCES app_identity(id)
            )"""
        )
        createBaselineTable(db)
        db.execSQL("CREATE TABLE settings(key TEXT PRIMARY KEY, value TEXT NOT NULL)")
        createHotspotSessionTable(db)
        db.execSQL("CREATE INDEX delta_time_idx ON usage_delta(interval_end_utc)")
        db.execSQL("CREATE INDEX delta_app_idx ON usage_delta(app_identity_id, interval_end_utc)")
    }

    override fun onUpgrade(db: SQLiteDatabase, oldVersion: Int, newVersion: Int) {
        if (oldVersion < 2) createHotspotSessionTable(db)
        if (oldVersion < 3) {
            db.execSQL("ALTER TABLE alert_event ADD COLUMN window_end INTEGER")
            db.execSQL("ALTER TABLE alert_event ADD COLUMN app_identity_id INTEGER REFERENCES app_identity(id)")
            db.execSQL("ALTER TABLE alert_event ADD COLUMN baseline_bytes INTEGER")
            db.execSQL("ALTER TABLE alert_event ADD COLUMN ratio REAL")
            db.execSQL("ALTER TABLE alert_event ADD COLUMN network_type TEXT")
            db.execSQL("ALTER TABLE alert_event ADD COLUMN foreground_state TEXT")
            createBaselineTable(db)
        }
        if (oldVersion < 4) {
            db.execSQL("ALTER TABLE app_identity ADD COLUMN excluded_from_alerts INTEGER NOT NULL DEFAULT 0")
        }
    }

    private fun createBaselineTable(db: SQLiteDatabase) {
        db.execSQL(
            """CREATE TABLE IF NOT EXISTS baseline(
                app_identity_id INTEGER NOT NULL,
                granularity TEXT NOT NULL,
                network_type TEXT NOT NULL,
                sample_count INTEGER NOT NULL,
                center REAL NOT NULL,
                dispersion REAL NOT NULL,
                updated_at INTEGER NOT NULL,
                PRIMARY KEY(app_identity_id, granularity, network_type),
                FOREIGN KEY(app_identity_id) REFERENCES app_identity(id)
            )"""
        )
    }

    private fun createHotspotSessionTable(db: SQLiteDatabase) {
        db.execSQL(
            """CREATE TABLE IF NOT EXISTS hotspot_session(
                id INTEGER PRIMARY KEY AUTOINCREMENT,
                started_at_utc INTEGER NOT NULL,
                ended_at_utc INTEGER,
                detection_quality TEXT NOT NULL,
                open_marker INTEGER UNIQUE CHECK(open_marker IS NULL OR open_marker = 1)
            )"""
        )
        db.execSQL(
            "CREATE INDEX IF NOT EXISTS hotspot_session_time_idx ON hotspot_session(started_at_utc, ended_at_utc)"
        )
    }

    @Synchronized
    fun putSetting(key: String, value: String) {
        writableDatabase.insertWithOnConflict(
            "settings",
            null,
            ContentValues().apply { put("key", key); put("value", value) },
            SQLiteDatabase.CONFLICT_REPLACE,
        )
    }

    @Synchronized
    fun setting(key: String): String? = readableDatabase.rawQuery(
        "SELECT value FROM settings WHERE key = ?", arrayOf(key)
    ).use { if (it.moveToFirst()) it.getString(0) else null }

    @Synchronized
    fun latestSnapshot(): Snapshot? = readableDatabase.rawQuery(
        """SELECT captured_at_utc, monotonic_marker, boot_id, network_type,
                  rx_total, tx_total, quality
           FROM usage_snapshot ORDER BY id DESC LIMIT 1""", null
    ).use {
        if (!it.moveToFirst()) null else Snapshot(
            capturedAt = it.getLong(0), monotonic = it.getLong(1), bootId = it.getString(2),
            networkType = it.getString(3), rxTotal = it.getLong(4), txTotal = it.getLong(5),
            quality = it.getString(6),
        )
    }

    @Synchronized
    fun insertSnapshot(snapshot: Snapshot) {
        writableDatabase.insertOrThrow("usage_snapshot", null, ContentValues().apply {
            put("captured_at_utc", snapshot.capturedAt)
            put("monotonic_marker", snapshot.monotonic)
            put("boot_id", snapshot.bootId)
            put("network_type", snapshot.networkType)
            put("rx_total", snapshot.rxTotal)
            put("tx_total", snapshot.txTotal)
            put("source", "traffic_stats")
            put("quality", snapshot.quality)
        })
    }

    @Synchronized
    fun insertDeviceDelta(previous: Snapshot, current: Snapshot) {
        if (previous.bootId != current.bootId || current.monotonic <= previous.monotonic) return
        val rx = current.rxTotal - previous.rxTotal
        val tx = current.txTotal - previous.txTotal
        if (rx < 0 || tx < 0) return
        val network = if (previous.networkType == current.networkType) current.networkType else "unknown"
        val key = "device:${previous.capturedAt}:${current.capturedAt}"
        writableDatabase.insertWithOnConflict("usage_delta", null, ContentValues().apply {
            put("interval_start_utc", previous.capturedAt)
            put("interval_end_utc", current.capturedAt)
            putNull("app_identity_id")
            put("network_type", network)
            put("foreground_state", "unknown")
            put("rx_bytes", rx)
            put("tx_bytes", tx)
            put("quality", if (network == "unknown") "partial" else "measured")
            put("dedupe_key", key)
        }, SQLiteDatabase.CONFLICT_IGNORE)
    }

    @Synchronized
    fun upsertApp(uid: Int, packageName: String?, label: String, now: Long): IdentityResult =
        upsertIdentity("android:$uid:${packageName ?: "unknown"}", packageName, label, now)

    @Synchronized
    fun upsertTethering(now: Long): Long =
        upsertIdentity(TETHERING_PLATFORM_KEY, null, "Hotspot & tethering", now).id

    private fun upsertIdentity(
        platformKey: String, packageName: String?, label: String, now: Long,
    ): IdentityResult {
        val inserted = writableDatabase.insertWithOnConflict("app_identity", null, ContentValues().apply {
            put("platform_key", platformKey)
            put("package_or_bundle_id", packageName)
            put("label_snapshot", label)
            put("first_seen_at", now)
            put("last_seen_at", now)
        }, SQLiteDatabase.CONFLICT_IGNORE)
        writableDatabase.update("app_identity", ContentValues().apply {
            put("label_snapshot", label); put("last_seen_at", now)
        }, "platform_key = ?", arrayOf(platformKey))
        val id = readableDatabase.rawQuery(
            "SELECT id FROM app_identity WHERE platform_key = ?", arrayOf(platformKey)
        ).use { it.moveToFirst(); it.getLong(0) }
        return IdentityResult(id, inserted != -1L)
    }

    @Synchronized
    fun clearAppDeltas(start: Long, end: Long, network: String) {
        writableDatabase.delete(
            "usage_delta",
            "app_identity_id IS NOT NULL AND interval_end_utc > ? AND interval_start_utc < ? AND network_type = ?",
            arrayOf(start.toString(), end.toString(), network),
        )
    }

    @Synchronized
    fun insertAppDelta(
        start: Long, end: Long, appId: Long, uid: Int, network: String,
        foreground: String, rx: Long, tx: Long,
    ) {
        if (rx < 0 || tx < 0 || rx + tx == 0L) return
        val key = "os:$start:$end:$network:$uid:$foreground"
        writableDatabase.insertWithOnConflict("usage_delta", null, ContentValues().apply {
            put("interval_start_utc", start); put("interval_end_utc", end)
            put("app_identity_id", appId); put("network_type", network)
            put("foreground_state", foreground); put("rx_bytes", rx); put("tx_bytes", tx)
            put("quality", "os_reconciled"); put("dedupe_key", key)
        }, SQLiteDatabase.CONFLICT_IGNORE)
    }

    @Synchronized
    fun summary(start: Long, end: Long, network: String? = null): Map<String, Long> {
        if (network == "hotspot") return hotspotSummary(start, end)
        val filter = if (network == null || network == "all") "" else " AND network_type = ?"
        val args = mutableListOf(start.toString(), end.toString())
        if (filter.isNotEmpty()) args.add(network!!)
        return readableDatabase.rawQuery(
            """SELECT COALESCE(SUM(rx_bytes), 0), COALESCE(SUM(tx_bytes), 0)
               FROM usage_delta WHERE app_identity_id IS NULL
               AND interval_end_utc > ? AND interval_start_utc < ?$filter""",
            args.toTypedArray(),
        ).use {
            it.moveToFirst(); mapOf("rxBytes" to it.getLong(0), "txBytes" to it.getLong(1))
        }
    }

    @Synchronized
    fun hotspotSummary(
        start: Long, end: Long, network: String? = null,
    ): Map<String, Long> {
        val filter = if (network == null || network == "all" || network == "hotspot") ""
            else " AND d.network_type = ?"
        val args = mutableListOf(TETHERING_PLATFORM_KEY, start.toString(), end.toString())
        if (filter.isNotEmpty()) args.add(network!!)
        return readableDatabase.rawQuery(
            """SELECT COALESCE(SUM(d.rx_bytes), 0), COALESCE(SUM(d.tx_bytes), 0)
               FROM usage_delta d JOIN app_identity a ON a.id = d.app_identity_id
               WHERE a.platform_key = ? AND d.interval_end_utc > ?
               AND d.interval_start_utc < ?$filter""", args.toTypedArray(),
        ).use {
            it.moveToFirst(); mapOf("rxBytes" to it.getLong(0), "txBytes" to it.getLong(1))
        }
    }

    @Synchronized
    fun appUsage(start: Long, end: Long, network: String? = null): List<Map<String, Any?>> {
        val filter = if (network == null || network == "all") "" else " AND d.network_type = ?"
        val args = mutableListOf(start.toString(), end.toString())
        if (filter.isNotEmpty()) args.add(network!!)
        return readableDatabase.rawQuery(
            """SELECT a.id, a.label_snapshot, a.package_or_bundle_id,
                      SUM(d.rx_bytes), SUM(d.tx_bytes),
                      CASE WHEN SUM(CASE WHEN d.foreground_state = 'background' THEN d.rx_bytes + d.tx_bytes ELSE 0 END) > 0
                           THEN 'background activity' ELSE 'state unavailable' END,
                      COALESCE((SELECT MAX(b.sample_count) FROM baseline b
                          WHERE b.app_identity_id = a.id), 0),
                      (SELECT SUM(b.center) FROM baseline b WHERE b.app_identity_id = a.id),
                      a.excluded_from_alerts
               FROM usage_delta d JOIN app_identity a ON a.id = d.app_identity_id
               WHERE d.interval_end_utc > ? AND d.interval_start_utc < ?$filter
               AND a.platform_key != '$TETHERING_PLATFORM_KEY'
               GROUP BY a.id ORDER BY SUM(d.rx_bytes + d.tx_bytes) DESC""",
            args.toTypedArray(),
        ).use { cursor ->
            buildList {
                while (cursor.moveToNext()) add(mapOf(
                    "id" to cursor.getLong(0), "label" to cursor.getString(1),
                    "packageName" to cursor.getString(2), "rxBytes" to cursor.getLong(3),
                    "txBytes" to cursor.getLong(4), "foregroundState" to cursor.getString(5),
                    "baselineSampleCount" to cursor.getInt(6),
                    "baselineBytes" to cursor.nullableLong(7),
                    "excludedFromAlerts" to (cursor.getInt(8) == 1),
                ))
            }
        }
    }

    @Synchronized
    fun dailyUsage(start: Long, end: Long, network: String? = null): List<Map<String, Any>> {
        val hotspot = network == "hotspot"
        val filter = if (network == null || network == "all" || hotspot) "" else " AND d.network_type = ?"
        val args = mutableListOf<String>()
        if (hotspot) args.add(TETHERING_PLATFORM_KEY)
        args.add(start.toString()); args.add(end.toString())
        if (filter.isNotEmpty()) args.add(network!!)
        val source = if (hotspot)
            "usage_delta d JOIN app_identity a ON a.id = d.app_identity_id"
        else "usage_delta d"
        val attribution = if (hotspot) "a.platform_key = ?" else "d.app_identity_id IS NULL"
        return readableDatabase.rawQuery(
            """SELECT strftime('%Y-%m-%d', d.interval_end_utc / 1000, 'unixepoch', 'localtime') day,
                      SUM(d.rx_bytes), SUM(d.tx_bytes)
               FROM $source WHERE $attribution
               AND d.interval_end_utc > ? AND d.interval_start_utc < ?$filter
               GROUP BY day ORDER BY day""", args.toTypedArray()
        ).use { cursor ->
            buildList { while (cursor.moveToNext()) add(mapOf(
                "date" to cursor.getString(0), "rxBytes" to cursor.getLong(1), "txBytes" to cursor.getLong(2)
            )) }
        }
    }

    @Synchronized
    fun hourlyUsage(start: Long, end: Long, network: String? = null): List<Map<String, Any>> {
        val hotspot = network == "hotspot"
        val filter = if (network == null || network == "all" || hotspot) "" else " AND d.network_type = ?"
        val args = mutableListOf<String>()
        if (hotspot) args.add(TETHERING_PLATFORM_KEY)
        args.add(start.toString()); args.add(end.toString())
        if (filter.isNotEmpty()) args.add(network!!)
        val source = if (hotspot)
            "usage_delta d JOIN app_identity a ON a.id = d.app_identity_id"
        else "usage_delta d"
        val attribution = if (hotspot) "a.platform_key = ?" else "d.app_identity_id IS NULL"
        return readableDatabase.rawQuery(
            """SELECT strftime('%Y-%m-%dT%H:00:00', d.interval_end_utc / 1000, 'unixepoch', 'localtime') hour,
                      SUM(d.rx_bytes), SUM(d.tx_bytes)
               FROM $source WHERE $attribution
               AND d.interval_end_utc > ? AND d.interval_start_utc < ?$filter
               GROUP BY hour ORDER BY hour""", args.toTypedArray()
        ).use { cursor ->
            buildList { while (cursor.moveToNext()) add(mapOf(
                "hour" to cursor.getString(0), "rxBytes" to cursor.getLong(1), "txBytes" to cursor.getLong(2)
            )) }
        }
    }

    @Synchronized
    fun recordHotspotState(active: Boolean?, observedAt: Long, quality: String) {
        val state = when (active) { true -> "active"; false -> "inactive"; null -> "unknown" }
        val openSession = readableDatabase.rawQuery(
            "SELECT id FROM hotspot_session WHERE ended_at_utc IS NULL ORDER BY id DESC LIMIT 1", null
        ).use { if (it.moveToFirst()) it.getLong(0) else null }
        when {
            active == true && openSession == null -> writableDatabase.insertWithOnConflict(
                "hotspot_session", null, ContentValues().apply {
                    put("started_at_utc", observedAt); put("detection_quality", quality)
                    put("open_marker", 1)
                }, SQLiteDatabase.CONFLICT_IGNORE,
            )
            active != true && openSession != null -> writableDatabase.update(
                "hotspot_session", ContentValues().apply {
                    put("ended_at_utc", observedAt); putNull("open_marker")
                },
                "id = ?", arrayOf(openSession.toString()),
            )
        }
        putSetting("hotspot_state", state)
        putSetting("hotspot_state_observed_at", observedAt.toString())
        putSetting("hotspot_state_quality", quality)
    }

    @Synchronized
    fun hotspotState(): Map<String, Any?> {
        val state = setting("hotspot_state") ?: "unknown"
        val openStart = if (state == "active") readableDatabase.rawQuery(
            "SELECT started_at_utc FROM hotspot_session WHERE ended_at_utc IS NULL ORDER BY id DESC LIMIT 1", null
        ).use { if (it.moveToFirst()) it.getLong(0) else null } else null
        return mapOf(
            "state" to state,
            "startedAt" to openStart,
            "observedAt" to setting("hotspot_state_observed_at")?.toLongOrNull(),
            "quality" to (setting("hotspot_state_quality") ?: "unavailable"),
        )
    }

    @Synchronized
    fun savePlan(capBytes: Long, cycleDay: Int, enabled: Boolean) {
        writableDatabase.insertWithOnConflict("data_plan", null, ContentValues().apply {
            put("id", 1); put("cap_bytes", capBytes); put("cycle_day", cycleDay)
            put("enabled", if (enabled) 1 else 0)
        }, SQLiteDatabase.CONFLICT_REPLACE)
    }

    @Synchronized
    fun plan(): Map<String, Any>? = readableDatabase.rawQuery(
        "SELECT cap_bytes, cycle_day, enabled FROM data_plan WHERE id = 1", null
    ).use { if (!it.moveToFirst()) null else mapOf(
        "capBytes" to it.getLong(0), "cycleDay" to it.getInt(1), "enabled" to (it.getInt(2) == 1)
    ) }

    @Synchronized
    fun alerts(): List<Map<String, Any?>> = readableDatabase.rawQuery(
        """SELECT e.id, e.type, e.actual_bytes, e.state, e.created_at,
                  a.label_snapshot, e.baseline_bytes, e.ratio, e.network_type,
                  e.foreground_state
           FROM alert_event e LEFT JOIN app_identity a ON a.id = e.app_identity_id
           ORDER BY e.created_at DESC""", null
    ).use { cursor -> buildList { while (cursor.moveToNext()) add(mapOf(
        "id" to cursor.getLong(0), "type" to cursor.getString(1),
        "actualBytes" to cursor.getLong(2), "state" to cursor.getString(3),
        "createdAt" to cursor.getLong(4), "appLabel" to cursor.nullableString(5),
        "baselineBytes" to cursor.nullableLong(6), "ratio" to cursor.nullableDouble(7),
        "networkType" to cursor.nullableString(8),
        "foregroundState" to cursor.nullableString(9),
    )) } }

    @Synchronized
    fun intelligenceCandidates(start: Long, end: Long): List<IntelligenceCandidate> =
        readableDatabase.rawQuery(
            """SELECT d.app_identity_id, a.label_snapshot, d.network_type,
                      SUM(d.rx_bytes + d.tx_bytes),
                      SUM(CASE WHEN d.foreground_state = 'background'
                          THEN d.rx_bytes + d.tx_bytes ELSE 0 END),
                      a.excluded_from_alerts
               FROM usage_delta d JOIN app_identity a ON a.id = d.app_identity_id
               WHERE d.interval_end_utc > ? AND d.interval_start_utc < ?
               AND a.platform_key != ?
               GROUP BY d.app_identity_id, d.network_type""",
            arrayOf(start.toString(), end.toString(), TETHERING_PLATFORM_KEY),
        ).use { cursor -> buildList { while (cursor.moveToNext()) add(IntelligenceCandidate(
            appId = cursor.getLong(0), label = cursor.getString(1),
            network = cursor.getString(2), actualBytes = cursor.getLong(3),
            backgroundBytes = cursor.getLong(4), excludedFromAlerts = cursor.getInt(5) == 1,
        )) } }

    @Synchronized
    fun appFirstSeen(appId: Long): Long = readableDatabase.rawQuery(
        "SELECT first_seen_at FROM app_identity WHERE id = ?", arrayOf(appId.toString())
    ).use { if (it.moveToFirst()) it.getLong(0) else Long.MAX_VALUE }

    @Synchronized
    fun dayIsComplete(start: Long, end: Long): Boolean = readableDatabase.rawQuery(
        """SELECT MIN(captured_at_utc), MAX(captured_at_utc), COUNT(*)
           FROM usage_snapshot WHERE captured_at_utc >= ? AND captured_at_utc < ?""",
        arrayOf(start.toString(), end.toString()),
    ).use {
        if (!it.moveToFirst() || it.getLong(2) < 20) false
        else it.getLong(0) <= start + 2 * 60 * 60 * 1000L &&
            it.getLong(1) >= end - 2 * 60 * 60 * 1000L
    }

    @Synchronized
    fun appTotal(appId: Long, start: Long, end: Long, network: String): Long =
        readableDatabase.rawQuery(
            """SELECT COALESCE(SUM(rx_bytes + tx_bytes), 0) FROM usage_delta
               WHERE app_identity_id = ? AND interval_end_utc > ?
               AND interval_start_utc < ? AND network_type = ?""",
            arrayOf(appId.toString(), start.toString(), end.toString(), network),
        ).use { it.moveToFirst(); it.getLong(0) }

    @Synchronized
    fun saveBaseline(appId: Long, network: String, samples: Int, center: Double, dispersion: Double, now: Long) {
        writableDatabase.insertWithOnConflict("baseline", null, ContentValues().apply {
            put("app_identity_id", appId); put("granularity", "daily")
            put("network_type", network); put("sample_count", samples)
            put("center", center); put("dispersion", dispersion); put("updated_at", now)
        }, SQLiteDatabase.CONFLICT_REPLACE)
    }

    @Synchronized
    fun insertIntelligenceAlert(
        type: String, appId: Long, start: Long, end: Long, actualBytes: Long,
        baselineBytes: Long?, ratio: Double?, network: String, foreground: String,
    ): Boolean {
        val key = if (type == "new_app") "$type:$appId" else "$type:$appId:$start:$network"
        val result = writableDatabase.insertWithOnConflict("alert_event", null, ContentValues().apply {
            put("type", type); put("window_start", start); put("window_end", end)
            put("app_identity_id", appId); put("actual_bytes", actualBytes)
            if (baselineBytes == null) putNull("baseline_bytes") else put("baseline_bytes", baselineBytes)
            if (ratio == null) putNull("ratio") else put("ratio", ratio)
            put("network_type", network); put("foreground_state", foreground)
            put("state", "unread"); put("dedupe_key", key); put("created_at", System.currentTimeMillis())
        }, SQLiteDatabase.CONFLICT_IGNORE)
        return result != -1L
    }

    @Synchronized
    fun insertPlanAlert(type: String, cycleStart: Long, actualBytes: Long): Boolean {
        val result = writableDatabase.insertWithOnConflict("alert_event", null, ContentValues().apply {
            put("type", type); put("window_start", cycleStart); put("actual_bytes", actualBytes)
            put("state", "unread"); put("dedupe_key", "$type:$cycleStart")
            put("created_at", System.currentTimeMillis())
        }, SQLiteDatabase.CONFLICT_IGNORE)
        return result != -1L
    }

    @Synchronized
    fun setAppExcluded(appId: Long, excluded: Boolean) {
        writableDatabase.update(
            "app_identity",
            ContentValues().apply { put("excluded_from_alerts", if (excluded) 1 else 0) },
            "id = ?",
            arrayOf(appId.toString()),
        )
    }

    @Synchronized
    fun retentionDays(): Int = setting("retention_days")?.toIntOrNull() ?: 365

    @Synchronized
    fun setRetentionDays(days: Int) {
        require(days == -1 || days in setOf(30, 90, 365))
        putSetting("retention_days", days.toString())
        pruneExpiredData(force = true)
    }

    @Synchronized
    fun pruneExpiredData(force: Boolean = false) {
        val now = System.currentTimeMillis()
        val lastPrune = setting("last_retention_prune_at")?.toLongOrNull() ?: 0L
        if (!force && now - lastPrune < 24 * 60 * 60 * 1000L) return
        val days = retentionDays()
        if (days < 0) {
            putSetting("last_retention_prune_at", now.toString())
            return
        }
        val cutoff = now - days * 24 * 60 * 60 * 1000L
        writableDatabase.beginTransaction()
        try {
            writableDatabase.delete("alert_event", "created_at < ?", arrayOf(cutoff.toString()))
            writableDatabase.delete("usage_delta", "interval_end_utc < ?", arrayOf(cutoff.toString()))
            writableDatabase.delete("usage_snapshot", "captured_at_utc < ?", arrayOf(cutoff.toString()))
            writableDatabase.delete(
                "hotspot_session",
                "ended_at_utc IS NOT NULL AND ended_at_utc < ?",
                arrayOf(cutoff.toString()),
            )
            writableDatabase.setTransactionSuccessful()
        } finally {
            writableDatabase.endTransaction()
        }
        putSetting("last_retention_prune_at", now.toString())
    }

    @Synchronized
    fun writeCsv(output: OutputStream) {
        val writer = OutputStreamWriter(output, Charsets.UTF_8)
        writer.append("interval_start_utc,interval_end_utc,scope,app_label,package_id,network,activity_state,download_bytes,upload_bytes,quality\n")
        readableDatabase.rawQuery(
            """SELECT d.interval_start_utc, d.interval_end_utc,
                      CASE WHEN d.app_identity_id IS NULL THEN 'device' ELSE 'app' END,
                      a.label_snapshot, a.package_or_bundle_id, d.network_type,
                      d.foreground_state, d.rx_bytes, d.tx_bytes, d.quality
               FROM usage_delta d LEFT JOIN app_identity a ON a.id = d.app_identity_id
               ORDER BY d.interval_end_utc, d.id""",
            null,
        ).use { cursor ->
            while (cursor.moveToNext()) {
                val values = listOf(
                    Instant.ofEpochMilli(cursor.getLong(0)).toString(),
                    Instant.ofEpochMilli(cursor.getLong(1)).toString(),
                    cursor.getString(2),
                    cursor.nullableString(3) ?: "",
                    cursor.nullableString(4) ?: "",
                    cursor.getString(5),
                    cursor.getString(6),
                    cursor.getLong(7).toString(),
                    cursor.getLong(8).toString(),
                    cursor.getString(9),
                )
                writer.append(values.joinToString(",") { csvField(it) }).append('\n')
            }
        }
        writer.flush()
    }

    @Synchronized
    fun writeBackup(output: OutputStream) {
        val writer = JsonWriter(OutputStreamWriter(output, Charsets.UTF_8)).apply { setIndent("  ") }
        writer.beginObject()
        writer.name("format").value(BACKUP_FORMAT)
        writer.name("version").value(BACKUP_VERSION.toLong())
        writer.name("createdAt").value(System.currentTimeMillis())
        writer.name("tables").beginObject()
        backupSchemas.forEach { (table, _) ->
            writer.name(table).beginArray()
            readableDatabase.query(table, null, null, null, null, null, null).use { cursor ->
                while (cursor.moveToNext()) {
                    writer.beginObject()
                    cursor.columnNames.forEachIndexed { index, column ->
                        writer.name(column)
                        when (cursor.getType(index)) {
                            android.database.Cursor.FIELD_TYPE_NULL -> writer.nullValue()
                            android.database.Cursor.FIELD_TYPE_INTEGER -> writer.value(cursor.getLong(index))
                            android.database.Cursor.FIELD_TYPE_FLOAT -> writer.value(cursor.getDouble(index))
                            android.database.Cursor.FIELD_TYPE_STRING -> writer.value(cursor.getString(index))
                            else -> throw IllegalStateException("Unsupported backup value in $table.$column")
                        }
                    }
                    writer.endObject()
                }
            }
            writer.endArray()
        }
        writer.endObject()
        writer.endObject()
        writer.close()
    }

    @Synchronized
    fun restoreBackup(input: InputStream) {
        val reader = JsonReader(input.bufferedReader(Charsets.UTF_8))
        var format: String? = null
        var version: Int? = null
        var restoredTables = false
        writableDatabase.beginTransaction()
        try {
            reader.beginObject()
            while (reader.hasNext()) {
                when (reader.nextName()) {
                    "format" -> format = reader.nextString()
                    "version" -> version = reader.nextInt()
                    "createdAt" -> reader.skipValue()
                    "tables" -> {
                        require(format == BACKUP_FORMAT) { "This is not a DataLens backup" }
                        require(version == BACKUP_VERSION) { "Unsupported DataLens backup version" }
                        clearTables(writableDatabase)
                        reader.beginObject()
                        while (reader.hasNext()) {
                            val table = reader.nextName()
                            val schema = backupSchemas[table]
                                ?: throw IllegalArgumentException("Unknown backup table: $table")
                            reader.beginArray()
                            while (reader.hasNext()) {
                                val values = readBackupRow(reader, schema)
                                writableDatabase.insertOrThrow(table, null, values)
                            }
                            reader.endArray()
                        }
                        reader.endObject()
                        restoredTables = true
                    }
                    else -> reader.skipValue()
                }
            }
            reader.endObject()
            require(restoredTables) { "Backup contains no DataLens data" }
            writableDatabase.setTransactionSuccessful()
        } finally {
            writableDatabase.endTransaction()
            reader.close()
        }
    }

    private fun readBackupRow(reader: JsonReader, schema: Map<String, ValueType>): ContentValues {
        val values = ContentValues()
        reader.beginObject()
        while (reader.hasNext()) {
            val column = reader.nextName()
            val type = schema[column] ?: throw IllegalArgumentException("Unknown backup column: $column")
            if (reader.peek() == JsonToken.NULL) {
                reader.nextNull()
                values.putNull(column)
            } else when (type) {
                ValueType.INTEGER -> values.put(column, reader.nextLong())
                ValueType.REAL -> values.put(column, reader.nextDouble())
                ValueType.TEXT -> values.put(column, reader.nextString())
            }
        }
        reader.endObject()
        return values
    }

    private fun clearTables(db: SQLiteDatabase) {
        listOf("baseline", "usage_delta", "usage_snapshot", "hotspot_session", "alert_event", "app_identity", "data_plan", "settings")
            .forEach { db.delete(it, null, null) }
    }

    @Synchronized
    fun deleteAll() {
        writableDatabase.beginTransaction()
        try {
            clearTables(writableDatabase)
            writableDatabase.setTransactionSuccessful()
        } finally { writableDatabase.endTransaction() }
    }

    private fun csvField(value: String): String =
        if (value.any { it == ',' || it == '"' || it == '\n' || it == '\r' })
            "\"${value.replace("\"", "\"\"")}\"" else value

    private enum class ValueType { INTEGER, REAL, TEXT }

    data class Snapshot(
        val capturedAt: Long, val monotonic: Long, val bootId: String,
        val networkType: String, val rxTotal: Long, val txTotal: Long, val quality: String,
    )

    data class IdentityResult(val id: Long, val isNew: Boolean)

    data class IntelligenceCandidate(
        val appId: Long, val label: String, val network: String,
        val actualBytes: Long, val backgroundBytes: Long, val excludedFromAlerts: Boolean,
    )

    private fun android.database.Cursor.nullableString(index: Int): String? =
        if (isNull(index)) null else getString(index)
    private fun android.database.Cursor.nullableLong(index: Int): Long? =
        if (isNull(index)) null else getLong(index)
    private fun android.database.Cursor.nullableDouble(index: Int): Double? =
        if (isNull(index)) null else getDouble(index)

    companion object {
        const val TETHERING_PLATFORM_KEY = "android:tethering"
        private const val VERSION = 4
        private const val BACKUP_FORMAT = "io.andura.datalens.backup"
        private const val BACKUP_VERSION = 1

        private val backupSchemas = linkedMapOf(
            "app_identity" to linkedMapOf(
                "id" to ValueType.INTEGER, "platform_key" to ValueType.TEXT,
                "package_or_bundle_id" to ValueType.TEXT, "label_snapshot" to ValueType.TEXT,
                "first_seen_at" to ValueType.INTEGER, "last_seen_at" to ValueType.INTEGER,
                "excluded_from_alerts" to ValueType.INTEGER,
            ),
            "usage_snapshot" to linkedMapOf(
                "id" to ValueType.INTEGER, "captured_at_utc" to ValueType.INTEGER,
                "monotonic_marker" to ValueType.INTEGER, "boot_id" to ValueType.TEXT,
                "network_type" to ValueType.TEXT, "rx_total" to ValueType.INTEGER,
                "tx_total" to ValueType.INTEGER, "source" to ValueType.TEXT,
                "quality" to ValueType.TEXT,
            ),
            "usage_delta" to linkedMapOf(
                "id" to ValueType.INTEGER, "interval_start_utc" to ValueType.INTEGER,
                "interval_end_utc" to ValueType.INTEGER, "app_identity_id" to ValueType.INTEGER,
                "network_type" to ValueType.TEXT, "foreground_state" to ValueType.TEXT,
                "rx_bytes" to ValueType.INTEGER, "tx_bytes" to ValueType.INTEGER,
                "quality" to ValueType.TEXT, "dedupe_key" to ValueType.TEXT,
            ),
            "data_plan" to linkedMapOf(
                "id" to ValueType.INTEGER, "cap_bytes" to ValueType.INTEGER,
                "cycle_day" to ValueType.INTEGER, "enabled" to ValueType.INTEGER,
            ),
            "alert_event" to linkedMapOf(
                "id" to ValueType.INTEGER, "type" to ValueType.TEXT,
                "window_start" to ValueType.INTEGER, "window_end" to ValueType.INTEGER,
                "app_identity_id" to ValueType.INTEGER, "actual_bytes" to ValueType.INTEGER,
                "baseline_bytes" to ValueType.INTEGER, "ratio" to ValueType.REAL,
                "network_type" to ValueType.TEXT, "foreground_state" to ValueType.TEXT,
                "state" to ValueType.TEXT, "dedupe_key" to ValueType.TEXT,
                "created_at" to ValueType.INTEGER,
            ),
            "baseline" to linkedMapOf(
                "app_identity_id" to ValueType.INTEGER, "granularity" to ValueType.TEXT,
                "network_type" to ValueType.TEXT, "sample_count" to ValueType.INTEGER,
                "center" to ValueType.REAL, "dispersion" to ValueType.REAL,
                "updated_at" to ValueType.INTEGER,
            ),
            "settings" to linkedMapOf("key" to ValueType.TEXT, "value" to ValueType.TEXT),
            "hotspot_session" to linkedMapOf(
                "id" to ValueType.INTEGER, "started_at_utc" to ValueType.INTEGER,
                "ended_at_utc" to ValueType.INTEGER, "detection_quality" to ValueType.TEXT,
                "open_marker" to ValueType.INTEGER,
            ),
        )
    }
}
