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
import android.net.Uri
import android.os.Process
import android.os.SystemClock
import android.provider.Settings
import androidx.core.app.NotificationCompat
import io.andura.datalens.MainActivity
import io.andura.datalens.widget.DataLensWidgetProvider
import java.io.File
import java.time.Instant
import java.time.LocalDate
import java.time.ZoneId
import kotlin.math.abs
import kotlin.math.max

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
        database.pruneExpiredData()
        DataLensWidgetProvider.maybeUpdate(context)
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
        val newApps = mutableSetOf<Long>()
        var count = 0
        count += queryNetwork(manager, ConnectivityManager.TYPE_WIFI, "wifi", start, now, newApps)
        count += queryNetwork(manager, ConnectivityManager.TYPE_MOBILE, "mobile", start, now, newApps)
        evaluateIntelligence(start, now, newApps)
        database.putSetting("last_reconciled_at", now.toString())
        return count
    }

    private fun queryNetwork(
        manager: NetworkStatsManager, legacyType: Int, network: String, start: Long, end: Long,
        newApps: MutableSet<Long>,
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
                    val identity = database.upsertApp(uid, packageName, label, end)
                    if (identity.isNew) newApps.add(identity.id)
                    database.insertAppDelta(start, end, identity.id, uid, network, state, bytes.rx, bytes.tx)
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

    private fun evaluateIntelligence(dayStart: Long, now: Long, newApps: Set<Long>) {
        val sensitivity = database.setting("alert_sensitivity") ?: "medium"
        val anomalyEnabled = database.setting("alert_anomaly") != "false" && sensitivity != "off"
        val newAppEnabled = database.setting("alert_new_app") != "false"
        val backgroundEnabled = database.setting("alert_background") != "false"
        val policy = when (sensitivity) {
            "low" -> AlertPolicy(3.0, 250_000_000L, 4.0)
            "high" -> AlertPolicy(2.0, 50_000_000L, 2.0)
            else -> AlertPolicy(2.5, 100_000_000L, 3.0)
        }
        val zone = ZoneId.systemDefault()
        val today = LocalDate.now(zone)
        database.intelligenceCandidates(dayStart, now).forEach { candidate ->
            if (newAppEnabled && candidate.appId in newApps && candidate.actualBytes >= NEW_APP_FLOOR_BYTES) {
                if (database.insertIntelligenceAlert(
                    "new_app", candidate.appId, dayStart, now, candidate.actualBytes,
                    null, null, candidate.network, "unknown",
                )) notifyIntelligenceAlert(
                    "New app using data",
                    "${candidate.label} used ${formatBytes(candidate.actualBytes)} on ${candidate.network}.",
                    "new_app:${candidate.appId}:${candidate.network}",
                )
            }

            val firstSeenDate = Instant.ofEpochMilli(database.appFirstSeen(candidate.appId))
                .atZone(zone).toLocalDate()
            val samples = mutableListOf<Long>()
            for (daysAgo in 14 downTo 1) {
                val date = today.minusDays(daysAgo.toLong())
                // The install/first-traffic day is incomplete and cannot train a baseline.
                if (!date.isAfter(firstSeenDate)) continue
                val start = date.atStartOfDay(zone).toInstant().toEpochMilli()
                val end = date.plusDays(1).atStartOfDay(zone).toInstant().toEpochMilli()
                if (database.dayIsComplete(start, end)) {
                    samples.add(database.appTotal(candidate.appId, start, end, candidate.network))
                }
            }
            if (samples.isEmpty()) return@forEach
            val center = median(samples)
            val dispersion = median(samples.map { abs(it - center.toLong()).toLong() })
            database.saveBaseline(
                candidate.appId, candidate.network, samples.size, center, dispersion, now,
            )
            if (samples.size < 7) return@forEach
            val comparison = max(center, 1_000_000.0)
            val ratio = candidate.actualBytes / comparison
            val robustUpper = center + policy.dispersionMultiplier * 1.4826 * dispersion
            if (anomalyEnabled && candidate.actualBytes >= policy.minimumBytes &&
                ratio >= policy.ratio && candidate.actualBytes >= robustUpper) {
                if (database.insertIntelligenceAlert(
                    "anomaly_daily", candidate.appId, dayStart, now, candidate.actualBytes,
                    center.toLong(), ratio, candidate.network,
                    if (candidate.backgroundBytes > 0) "background observed" else "unknown",
                )) notifyIntelligenceAlert(
                    "Unusual data usage",
                    "${candidate.label} used ${formatBytes(candidate.actualBytes)} — ${String.format("%.1f", ratio)}× its usual rate.",
                    "anomaly:${candidate.appId}:${candidate.network}:$dayStart",
                )
            }
            if (backgroundEnabled && candidate.backgroundBytes >= policy.minimumBytes &&
                candidate.backgroundBytes * 2 >= candidate.actualBytes) {
                if (database.insertIntelligenceAlert(
                    "background_usage", candidate.appId, dayStart, now,
                    candidate.backgroundBytes, center.toLong(),
                    candidate.backgroundBytes / comparison, candidate.network, "background",
                )) notifyIntelligenceAlert(
                    "Background data usage",
                    "${candidate.label} used ${formatBytes(candidate.backgroundBytes)} in the background.",
                    "background:${candidate.appId}:${candidate.network}:$dayStart",
                )
            }
        }
    }

    private data class AlertPolicy(
        val ratio: Double, val minimumBytes: Long, val dispersionMultiplier: Double,
    )

    private fun median(values: List<Long>): Double {
        val sorted = values.sorted()
        val middle = sorted.size / 2
        return if (sorted.size % 2 == 1) sorted[middle].toDouble()
        else (sorted[middle - 1] + sorted[middle]) / 2.0
    }

    private fun notifyIntelligenceAlert(title: String, body: String, key: String) {
        val manager = context.getSystemService(NotificationManager::class.java)
        manager.createNotificationChannel(NotificationChannel(
            INTELLIGENCE_CHANNEL, "Usage intelligence alerts", NotificationManager.IMPORTANCE_DEFAULT,
        ).apply { description = "Unusual, new-app, and background data usage" })
        val intent = openDestination("alerts", 4201)
        manager.notify(key.hashCode(), NotificationCompat.Builder(context, INTELLIGENCE_CHANNEL)
            .setSmallIcon(android.R.drawable.stat_notify_error)
            .setContentTitle(title).setContentText(body).setStyle(NotificationCompat.BigTextStyle().bigText(body))
            .setContentIntent(intent).setAutoCancel(true).build())
    }

    private fun formatBytes(bytes: Long): String = when {
        bytes >= 1_000_000_000 -> String.format("%.1f GB", bytes / 1_000_000_000.0)
        bytes >= 1_000_000 -> String.format("%.1f MB", bytes / 1_000_000.0)
        else -> String.format("%.0f KB", bytes / 1_000.0)
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
        val intent = openDestination("alerts", 4202)
        manager.notify(type.hashCode(), NotificationCompat.Builder(context, ALERT_CHANNEL)
            .setSmallIcon(android.R.drawable.stat_notify_error)
            .setContentTitle(title).setContentText(body).setContentIntent(intent)
            .setAutoCancel(true).build())
    }

    private fun openDestination(destination: String, requestCode: Int): PendingIntent =
        PendingIntent.getActivity(
            context,
            requestCode,
            Intent(context, MainActivity::class.java).apply {
                action = Intent.ACTION_VIEW
                data = Uri.parse("datalens://open/$destination")
                putExtra(MainActivity.EXTRA_DESTINATION, destination)
                flags = Intent.FLAG_ACTIVITY_CLEAR_TOP or Intent.FLAG_ACTIVITY_SINGLE_TOP
            },
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE,
        )

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
        const val INTELLIGENCE_CHANNEL = "datalens_intelligence_alerts"
        private const val NEW_APP_FLOOR_BYTES = 1_000_000L

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
