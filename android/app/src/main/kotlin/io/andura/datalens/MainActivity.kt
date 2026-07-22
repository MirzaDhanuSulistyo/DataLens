package io.andura.datalens

import android.Manifest
import android.content.pm.PackageManager
import android.os.Build
import androidx.core.app.ActivityCompat
import androidx.core.content.ContextCompat
import io.andura.datalens.tracking.HotspotStateMonitor
import io.andura.datalens.tracking.MonitoringService
import io.andura.datalens.tracking.UsageCollector
import io.andura.datalens.tracking.UsageDatabase
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.util.concurrent.Executors

class MainActivity : FlutterActivity() {
    private lateinit var database: UsageDatabase
    private lateinit var collector: UsageCollector
    private lateinit var hotspotStateMonitor: HotspotStateMonitor
    private val executor = Executors.newSingleThreadExecutor()
    private var notificationResult: MethodChannel.Result? = null

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        database = UsageDatabase(applicationContext)
        collector = UsageCollector(applicationContext)
        hotspotStateMonitor = HotspotStateMonitor(applicationContext).also { it.start() }
        // An app update stops running services. Restore monitoring when the user
        // previously enabled it and opens the updated app.
        if (database.setting("monitoring_enabled") == "true") {
            MonitoringService.start(this)
        }
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CHANNEL).setMethodCallHandler { call, result ->
            when (call.method) {
                "getStatus" -> result.success(status())
                "openUsageAccessSettings" -> {
                    startActivity(UsageCollector.usageSettingsIntent()); result.success(null)
                }
                "requestNotificationPermission" -> requestNotificationPermission(result)
                "startMonitoring" -> {
                    MonitoringService.start(this); result.success(true)
                }
                "stopMonitoring" -> {
                    MonitoringService.stop(this); result.success(true)
                }
                "liveCounters" -> result.success(collector.liveCounters())
                "sampleNow" -> runAsync(result) { snapshotMap(collector.collectSnapshot()) }
                "reconcileNow" -> runAsync(result) { collector.reconcile() }
                "getSummary" -> {
                    val start = call.argument<Number>("start")!!.toLong()
                    val end = call.argument<Number>("end")!!.toLong()
                    result.success(database.summary(start, end, call.argument("network")))
                }
                "getApps" -> {
                    val start = call.argument<Number>("start")!!.toLong()
                    val end = call.argument<Number>("end")!!.toLong()
                    result.success(database.appUsage(start, end, call.argument("network")))
                }
                "getDailyUsage" -> {
                    val start = call.argument<Number>("start")!!.toLong()
                    val end = call.argument<Number>("end")!!.toLong()
                    result.success(database.dailyUsage(start, end, call.argument("network")))
                }
                "getHotspotUsage" -> {
                    val start = call.argument<Number>("start")!!.toLong()
                    val end = call.argument<Number>("end")!!.toLong()
                    runAsync(result) { collector.hotspotUsage(start, end, call.argument("network")) }
                }
                "savePlan" -> {
                    database.savePlan(
                        call.argument<Number>("capBytes")!!.toLong(),
                        call.argument<Number>("cycleDay")!!.toInt(),
                        call.argument<Boolean>("enabled") ?: true,
                    ); result.success(true)
                }
                "getPlan" -> result.success(database.plan())
                "getAlerts" -> result.success(database.alerts())
                "deleteAllData" -> { database.deleteAll(); result.success(true) }
                else -> result.notImplemented()
            }
        }
    }

    override fun onResume() {
        super.onResume()
        if (::database.isInitialized) {
            database.putSetting("last_capability_check", System.currentTimeMillis().toString())
        }
    }

    override fun onDestroy() {
        if (::hotspotStateMonitor.isInitialized) hotspotStateMonitor.stop()
        executor.shutdown()
        super.onDestroy()
    }

    private fun status(): Map<String, Any?> {
        val latest = database.latestSnapshot()
        return mapOf(
            "platform" to "android",
            "usageAccess" to UsageCollector.hasUsageAccess(this),
            "notifications" to notificationGranted(),
            "monitoring" to (database.setting("monitoring_enabled") == "true"),
            "latestSampleAt" to latest?.capturedAt,
            "latestQuality" to latest?.quality,
        )
    }

    private fun requestNotificationPermission(result: MethodChannel.Result) {
        if (notificationGranted() || Build.VERSION.SDK_INT < 33) {
            result.success(true); return
        }
        if (notificationResult != null) {
            result.error("request_in_progress", "A permission request is already open", null); return
        }
        notificationResult = result
        ActivityCompat.requestPermissions(this, arrayOf(Manifest.permission.POST_NOTIFICATIONS), NOTIFICATION_REQUEST)
    }

    override fun onRequestPermissionsResult(requestCode: Int, permissions: Array<out String>, grantResults: IntArray) {
        super.onRequestPermissionsResult(requestCode, permissions, grantResults)
        if (requestCode == NOTIFICATION_REQUEST) {
            notificationResult?.success(grantResults.firstOrNull() == PackageManager.PERMISSION_GRANTED)
            notificationResult = null
        }
    }

    private fun notificationGranted(): Boolean = Build.VERSION.SDK_INT < 33 ||
        ContextCompat.checkSelfPermission(this, Manifest.permission.POST_NOTIFICATIONS) == PackageManager.PERMISSION_GRANTED

    private fun snapshotMap(value: UsageDatabase.Snapshot): Map<String, Any> = mapOf(
        "capturedAt" to value.capturedAt, "networkType" to value.networkType,
        "rxTotal" to value.rxTotal, "txTotal" to value.txTotal, "quality" to value.quality,
    )

    private fun runAsync(result: MethodChannel.Result, action: () -> Any?) {
        executor.execute {
            try {
                val value = action()
                runOnUiThread { result.success(value) }
            } catch (error: Exception) {
                runOnUiThread { result.error("native_error", error.message, null) }
            }
        }
    }

    companion object {
        private const val CHANNEL = "io.andura.datalens/usage"
        private const val NOTIFICATION_REQUEST = 4103
    }
}
