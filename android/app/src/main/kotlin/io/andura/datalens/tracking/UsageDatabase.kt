package io.andura.datalens.tracking

import android.content.ContentValues
import android.content.Context
import android.database.sqlite.SQLiteDatabase
import android.database.sqlite.SQLiteOpenHelper

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
                last_seen_at INTEGER NOT NULL
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
                actual_bytes INTEGER NOT NULL,
                state TEXT NOT NULL DEFAULT 'unread',
                dedupe_key TEXT NOT NULL UNIQUE,
                created_at INTEGER NOT NULL
            )"""
        )
        db.execSQL("CREATE TABLE settings(key TEXT PRIMARY KEY, value TEXT NOT NULL)")
        db.execSQL("CREATE INDEX delta_time_idx ON usage_delta(interval_end_utc)")
        db.execSQL("CREATE INDEX delta_app_idx ON usage_delta(app_identity_id, interval_end_utc)")
    }

    override fun onUpgrade(db: SQLiteDatabase, oldVersion: Int, newVersion: Int) = Unit

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
    fun upsertApp(uid: Int, packageName: String?, label: String, now: Long): Long {
        val key = "android:$uid:${packageName ?: "unknown"}"
        writableDatabase.insertWithOnConflict("app_identity", null, ContentValues().apply {
            put("platform_key", key)
            put("package_or_bundle_id", packageName)
            put("label_snapshot", label)
            put("first_seen_at", now)
            put("last_seen_at", now)
        }, SQLiteDatabase.CONFLICT_IGNORE)
        writableDatabase.update("app_identity", ContentValues().apply {
            put("label_snapshot", label); put("last_seen_at", now)
        }, "platform_key = ?", arrayOf(key))
        return readableDatabase.rawQuery(
            "SELECT id FROM app_identity WHERE platform_key = ?", arrayOf(key)
        ).use { it.moveToFirst(); it.getLong(0) }
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
    fun appUsage(start: Long, end: Long, network: String? = null): List<Map<String, Any?>> {
        val filter = if (network == null || network == "all") "" else " AND d.network_type = ?"
        val args = mutableListOf(start.toString(), end.toString())
        if (filter.isNotEmpty()) args.add(network!!)
        return readableDatabase.rawQuery(
            """SELECT a.id, a.label_snapshot, a.package_or_bundle_id,
                      SUM(d.rx_bytes), SUM(d.tx_bytes),
                      CASE WHEN SUM(CASE WHEN d.foreground_state = 'background' THEN d.rx_bytes + d.tx_bytes ELSE 0 END) > 0
                           THEN 'background activity' ELSE 'state unavailable' END
               FROM usage_delta d JOIN app_identity a ON a.id = d.app_identity_id
               WHERE d.interval_end_utc > ? AND d.interval_start_utc < ?$filter
               GROUP BY a.id ORDER BY SUM(d.rx_bytes + d.tx_bytes) DESC""",
            args.toTypedArray(),
        ).use { cursor ->
            buildList {
                while (cursor.moveToNext()) add(mapOf(
                    "id" to cursor.getLong(0), "label" to cursor.getString(1),
                    "packageName" to cursor.getString(2), "rxBytes" to cursor.getLong(3),
                    "txBytes" to cursor.getLong(4), "foregroundState" to cursor.getString(5),
                ))
            }
        }
    }

    @Synchronized
    fun dailyUsage(start: Long, end: Long, network: String? = null): List<Map<String, Any>> {
        val filter = if (network == null || network == "all") "" else " AND network_type = ?"
        val args = mutableListOf(start.toString(), end.toString())
        if (filter.isNotEmpty()) args.add(network!!)
        return readableDatabase.rawQuery(
            """SELECT strftime('%Y-%m-%d', interval_end_utc / 1000, 'unixepoch', 'localtime') day,
                      SUM(rx_bytes), SUM(tx_bytes)
               FROM usage_delta WHERE app_identity_id IS NULL
               AND interval_end_utc > ? AND interval_start_utc < ?$filter
               GROUP BY day ORDER BY day""", args.toTypedArray()
        ).use { cursor ->
            buildList { while (cursor.moveToNext()) add(mapOf(
                "date" to cursor.getString(0), "rxBytes" to cursor.getLong(1), "txBytes" to cursor.getLong(2)
            )) }
        }
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
    fun alerts(): List<Map<String, Any>> = readableDatabase.rawQuery(
        "SELECT id, type, actual_bytes, state, created_at FROM alert_event ORDER BY created_at DESC", null
    ).use { cursor -> buildList { while (cursor.moveToNext()) add(mapOf(
        "id" to cursor.getLong(0), "type" to cursor.getString(1), "actualBytes" to cursor.getLong(2),
        "state" to cursor.getString(3), "createdAt" to cursor.getLong(4)
    )) } }

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
    fun deleteAll() {
        writableDatabase.beginTransaction()
        try {
            listOf("usage_delta", "usage_snapshot", "app_identity", "alert_event", "data_plan", "settings")
                .forEach { writableDatabase.delete(it, null, null) }
            writableDatabase.setTransactionSuccessful()
        } finally { writableDatabase.endTransaction() }
    }

    data class Snapshot(
        val capturedAt: Long, val monotonic: Long, val bootId: String,
        val networkType: String, val rxTotal: Long, val txTotal: Long, val quality: String,
    )

    companion object { private const val VERSION = 1 }
}
