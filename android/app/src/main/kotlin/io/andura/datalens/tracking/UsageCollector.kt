package io.andura.datalens.tracking

import android.app.AppOpsManager
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.app.usage.NetworkStats
import android.app.usage.NetworkStatsManager
import android.content.Context
import android.content.Intent
import android.net.ConnectivityManager
import android.net.NetworkCapabilities
import android.net.TrafficStats
import android.os.Process
import android.os.SystemClock
import android.provider.Settings
import androidx.core.app.NotificationCompat
import io.andura.datalens.MainActivity
import java.io.File
import java.time.Instant
import java.time.LocalDate
import java.time.ZoneId

class UsageCollector(private val context: Context) {
    private val database = UsageDatabase(context)

    fun liveCounters(): Map<String, Any> = mapOf(
        "rxBytes" to safeCounter(TrafficStats.getTotalRxBytes()),
        "txBytes" to safeCounter(TrafficStats.getTotalTxBytes()),
        "monotonicMillis" to SystemClock.elapsedRealtime(),
        "networkType" to currentNetworkType(),
    )

    fun collectSnapshot(): UsageDatabase.Snapshot {
        val now = UsageDatabase.Snapshot(
            capturedAt = System.currentTimeMillis(),
            monotonic = SystemClock.elapsedRealtime(),
            bootId = bootId(),
            networkType = currentNetworkType(),
            rxTotal = safeCounter(TrafficStats.getTotalRxBytes()),
            txTotal = safeCounter(TrafficStats.getTotalTxBytes()),
            quality = "measured",
        )
        val previous = database.latestSnapshot()
        if (previous != null) database.insertDeviceDelta(previous, now)
        database.insertSnapshot(now)
        evaluatePlanAlerts()
        return now
    }

    fun reconcile(): Int {
        if (!hasUsageAccess(context)) return 0
        val now = System.currentTimeMillis()
        // Re-read the complete local day. Android can publish UID accounting late,
        // so querying only since the previous run can permanently miss an app.
        val start = LocalDate.now(ZoneId.systemDefault())
            .atStartOfDay(ZoneId.systemDefault()).toInstant().toEpochMilli()
        val manager = context.getSystemService(NetworkStatsManager::class.java)
        var count = 0
        count += queryNetwork(manager, ConnectivityManager.TYPE_WIFI, "wifi", start, now)
        count += queryNetwork(manager, ConnectivityManager.TYPE_MOBILE, "mobile", start, now)
        database.putSetting("last_reconciled_at", now.toString())
        return count
    }

    private fun queryNetwork(
        manager: NetworkStatsManager, legacyType: Int, network: String, start: Long, end: Long,
    ): Int {
        var stats: NetworkStats? = null
        return try {
            stats = manager.querySummary(legacyType, null, start, end)
            val bucket = NetworkStats.Bucket()
            val totals = linkedMapOf<Pair<Int, String>, AppBytes>()
            while (stats.hasNextBucket()) {
                stats.getNextBucket(bucket)
                val uid = bucket.uid
                val tethering = uid == NetworkStats.Bucket.UID_TETHERING
                if ((!tethering && uid <= 0) || bucket.rxBytes + bucket.txBytes <= 0) continue
                val state = if (tethering) "unknown" else when (bucket.state) {
                    NetworkStats.Bucket.STATE_FOREGROUND -> "foreground"
                    NetworkStats.Bucket.STATE_DEFAULT -> "background"
                    else -> "unknown"
                }
                val value = totals.getOrPut(uid to state) { AppBytes() }
                value.rx += bucket.rxBytes
                value.tx += bucket.txBytes
            }

            // Replace the previous daily reconciliation instead of adding an
            // overlapping cumulative query and double-counting usage.
            database.clearAppDeltas(start, end, network)
            totals.forEach { (key, bytes) ->
                val (uid, state) = key
                if (uid == NetworkStats.Bucket.UID_TETHERING) {
                    val appId = database.upsertTethering(end)
                    database.insertAppDelta(start, end, appId, uid, network, "unknown", bytes.rx, bytes.tx)
                } else {
                    val packageName = context.packageManager.getPackagesForUid(uid)?.firstOrNull()
                    val label = packageName?.let {
                        runCatching {
                            val info = context.packageManager.getApplicationInfo(it, 0)
                            context.packageManager.getApplicationLabel(info).toString()
                        }.getOrNull()
                    } ?: "UID $uid"
                    val appId = database.upsertApp(uid, packageName, label, end)
                    database.insertAppDelta(start, end, appId, uid, network, state, bytes.rx, bytes.tx)
                }
            }
            totals.size
        } catch (_: SecurityException) {
            0
        } catch (_: RuntimeException) {
            0
        } finally {
            stats?.close()
        }
    }

    fun hotspotUsage(start: Long, end: Long, network: String?): Map<String, Any?> {
        val state = database.hotspotState()
        if (!hasUsageAccess(context)) return mapOf(
            "state" to state["state"],
            "stateQuality" to state["quality"],
            "sessionStartedAt" to state["startedAt"],
            "lastUpdatedAt" to state["observedAt"],
            "usageAvailable" to false,
            "rxBytes" to 0L, "txBytes" to 0L,
            "monthRxBytes" to 0L, "monthTxBytes" to 0L,
            "sessionRxBytes" to 0L, "sessionTxBytes" to 0L,
        )

        val total = queryTetheringTotals(start, end, network)
        val monthStart = LocalDate.now(ZoneId.systemDefault()).withDayOfMonth(1)
            .atStartOfDay(ZoneId.systemDefault()).toInstant().toEpochMilli()
        val month = queryTetheringTotals(monthStart, end, network)
        val sessionStart = state["startedAt"] as? Long
        val session = if (state["state"] == "active" && sessionStart != null)
            queryTetheringTotals(sessionStart, end, network) else AppBytes()
        database.putSetting("last_hotspot_usage_at", end.toString())
        return mapOf(
            "state" to state["state"],
            "stateQuality" to state["quality"],
            "sessionStartedAt" to sessionStart,
            "lastUpdatedAt" to end,
            "usageAvailable" to total.queried,
            "rxBytes" to total.rx, "txBytes" to total.tx,
            "monthRxBytes" to month.rx, "monthTxBytes" to month.tx,
            "sessionRxBytes" to session.rx, "sessionTxBytes" to session.tx,
        )
    }

    private fun queryTetheringTotals(start: Long, end: Long, network: String?): AppBytes {
        val total = AppBytes()
        if (network == null || network == "all" || network == "hotspot" || network == "wifi") {
            addTetheringTotal(total, ConnectivityManager.TYPE_WIFI, start, end)
        }
        if (network == null || network == "all" || network == "hotspot" || network == "mobile") {
            addTetheringTotal(total, ConnectivityManager.TYPE_MOBILE, start, end)
        }
        return total
    }

    private fun addTetheringTotal(total: AppBytes, legacyType: Int, start: Long, end: Long) {
        var stats: NetworkStats? = null
        try {
            val manager = context.getSystemService(NetworkStatsManager::class.java)
            stats = manager.querySummary(legacyType, null, start, end)
            total.queried = true
            val bucket = NetworkStats.Bucket()
            while (stats.hasNextBucket()) {
                stats.getNextBucket(bucket)
                if (bucket.uid == NetworkStats.Bucket.UID_TETHERING) {
                    total.rx += bucket.rxBytes.coerceAtLeast(0)
                    total.tx += bucket.txBytes.coerceAtLeast(0)
                }
            }
        } catch (_: SecurityException) {
            // Usage access or this transport's counters are unavailable.
        } catch (_: RuntimeException) {
            // OEM NetworkStats implementations can reject an individual transport.
        } finally {
            stats?.close()
        }
    }

    private data class AppBytes(
        var rx: Long = 0, var tx: Long = 0, var queried: Boolean = false,
    )

    private fun evaluatePlanAlerts() {
        val plan = database.plan() ?: return
        if (plan["enabled"] != true) return
        val cap = plan["capBytes"] as Long
        if (cap <= 0) return
        val cycleDay = plan["cycleDay"] as Int
        val start = cycleStart(cycleDay)
        val used = database.summary(start, System.currentTimeMillis(), "mobile")
            .values.sum()
        when {
            used >= cap -> notifyPlanAlert("plan_100", start, used, "Data plan reached", "You have used 100% of your mobile data plan.")
            used >= (cap * 0.8).toLong() -> notifyPlanAlert("plan_80", start, used, "Data plan at 80%", "You are nearing your mobile data limit.")
        }
    }

    private fun notifyPlanAlert(type: String, cycleStart: Long, used: Long, title: String, body: String) {
        if (!database.insertPlanAlert(type, cycleStart, used)) return
        val manager = context.getSystemService(NotificationManager::class.java)
        manager.createNotificationChannel(NotificationChannel(
            ALERT_CHANNEL, "Data plan alerts", NotificationManager.IMPORTANCE_DEFAULT
        ))
        val intent = PendingIntent.getActivity(
            context, 0, Intent(context, MainActivity::class.java),
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE,
        )
        manager.notify(type.hashCode(), NotificationCompat.Builder(context, ALERT_CHANNEL)
            .setSmallIcon(android.R.drawable.stat_notify_error)
            .setContentTitle(title).setContentText(body).setContentIntent(intent)
            .setAutoCancel(true).build())
    }

    private fun cycleStart(day: Int): Long {
        val zone = ZoneId.systemDefault()
        val today = LocalDate.now(zone)
        fun resolved(year: Int, month: Int): LocalDate {
            val first = LocalDate.of(year, month, 1)
            return first.withDayOfMonth(day.coerceAtMost(first.lengthOfMonth()))
        }
        var candidate = resolved(today.year, today.monthValue)
        if (today.isBefore(candidate)) {
            val previous = today.minusMonths(1)
            candidate = resolved(previous.year, previous.monthValue)
        }
        return candidate.atStartOfDay(zone).toInstant().toEpochMilli()
    }

    private fun currentNetworkType(): String {
        val manager = context.getSystemService(ConnectivityManager::class.java)
        val capabilities = manager.getNetworkCapabilities(manager.activeNetwork) ?: return "unknown"
        return when {
            capabilities.hasTransport(NetworkCapabilities.TRANSPORT_VPN) -> "vpn"
            capabilities.hasTransport(NetworkCapabilities.TRANSPORT_WIFI) -> "wifi"
            capabilities.hasTransport(NetworkCapabilities.TRANSPORT_CELLULAR) -> "mobile"
            capabilities.hasTransport(NetworkCapabilities.TRANSPORT_ETHERNET) -> "other"
            else -> "unknown"
        }
    }

    private fun bootId(): String = runCatching {
        File("/proc/sys/kernel/random/boot_id").readText().trim()
    }.getOrElse { (Instant.now().toEpochMilli() - SystemClock.elapsedRealtime()).toString() }

    private fun safeCounter(value: Long): Long = if (value == TrafficStats.UNSUPPORTED.toLong() || value < 0) 0 else value

    companion object {
        const val ALERT_CHANNEL = "datalens_plan_alerts"

        fun hasUsageAccess(context: Context): Boolean {
            val appOps = context.getSystemService(AppOpsManager::class.java)
            val mode = appOps.unsafeCheckOpNoThrow(
                AppOpsManager.OPSTR_GET_USAGE_STATS, Process.myUid(), context.packageName,
            )
            return mode == AppOpsManager.MODE_ALLOWED
        }

        fun usageSettingsIntent(): Intent = Intent(Settings.ACTION_USAGE_ACCESS_SETTINGS)
    }
}
