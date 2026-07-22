package io.andura.datalens

import android.Manifest
import android.app.Activity
import android.content.Intent
import android.content.pm.PackageManager
import android.net.Uri
import android.os.Build
import android.os.PowerManager
import android.provider.Settings
import androidx.core.app.ActivityCompat
import androidx.core.content.ContextCompat
import io.andura.datalens.tracking.HotspotStateMonitor
import io.andura.datalens.tracking.MonitoringService
import io.andura.datalens.tracking.UsageCollector
import io.andura.datalens.tracking.UsageDatabase
import io.andura.datalens.widget.DataLensWidgetProvider
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.time.LocalDate
import java.util.Locale
import java.util.concurrent.Executors

class MainActivity : FlutterActivity() {
    private lateinit var database: UsageDatabase
    private lateinit var collector: UsageCollector
    private lateinit var hotspotStateMonitor: HotspotStateMonitor
    private val executor = Executors.newSingleThreadExecutor()
    private var notificationResult: MethodChannel.Result? = null
    private lateinit var methodChannel: MethodChannel
    private var pendingDestination: String? = null
    private var documentResult: MethodChannel.Result? = null

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        database = UsageDatabase(applicationContext)
        executor.execute { database.pruneExpiredData() }
        collector = UsageCollector(applicationContext)
        hotspotStateMonitor = HotspotStateMonitor(applicationContext).also { it.start() }
        // An app update stops running services. Restore monitoring when the user
        // previously enabled it and opens the updated app.
        if (database.setting("monitoring_enabled") == "true") {
            MonitoringService.start(this)
        }
        pendingDestination = destinationFromIntent(intent)
        methodChannel = MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CHANNEL)
        methodChannel.setMethodCallHandler { call, result ->
            when (call.method) {
                "getInitialDestination" -> {
                    result.success(pendingDestination)
                    pendingDestination = null
                }
                "getStatus" -> result.success(status())
                "openUsageAccessSettings" -> {
                    startActivity(UsageCollector.usageSettingsIntent()); result.success(null)
                }
                "openOverlaySettings" -> {
                    startActivity(Intent(
                        Settings.ACTION_MANAGE_OVERLAY_PERMISSION,
                        Uri.parse("package:$packageName"),
                    )); result.success(null)
                }
                "setOverlayEnabled" -> {
                    val enabled = call.arguments as? Boolean ?: false
                    val applied = !enabled || Settings.canDrawOverlays(this)
                    database.putSetting("overlay_enabled", (enabled && applied).toString())
                    if (database.setting("monitoring_enabled") == "true") MonitoringService.start(this)
                    result.success(applied)
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
                "getHourlyUsage" -> {
                    val start = call.argument<Number>("start")!!.toLong()
                    val end = call.argument<Number>("end")!!.toLong()
                    result.success(database.hourlyUsage(start, end, call.argument("network")))
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
                    )
                    DataLensWidgetProvider.updateAll(this)
                    result.success(true)
                }
                "getPlan" -> result.success(database.plan())
                "getAlerts" -> result.success(database.alerts())
                "markAllAlertsRead" -> {
                    database.markAllAlertsRead()
                    result.success(true)
                }
                "setAppExcluded" -> {
                    database.setAppExcluded(
                        call.argument<Number>("appId")!!.toLong(),
                        call.argument<Boolean>("excluded") ?: false,
                    )
                    result.success(true)
                }
                "getAlertPreferences" -> result.success(mapOf(
                    "sensitivity" to (database.setting("alert_sensitivity") ?: "medium"),
                    "anomalyAlerts" to (database.setting("alert_anomaly") != "false"),
                    "newAppAlerts" to (database.setting("alert_new_app") != "false"),
                    "backgroundAlerts" to (database.setting("alert_background") != "false"),
                ))
                "saveAlertPreferences" -> {
                    database.putSetting("alert_sensitivity", call.argument<String>("sensitivity") ?: "medium")
                    database.putSetting("alert_anomaly", (call.argument<Boolean>("anomalyAlerts") ?: true).toString())
                    database.putSetting("alert_new_app", (call.argument<Boolean>("newAppAlerts") ?: true).toString())
                    database.putSetting("alert_background", (call.argument<Boolean>("backgroundAlerts") ?: true).toString())
                    result.success(true)
                }
                "getWidgetPreferences" -> result.success(mapOf(
                    "content" to (database.setting("widget_content") ?: "today"),
                    "refreshMinutes" to (database.setting("widget_refresh_minutes")?.toIntOrNull() ?: 30),
                ))
                "saveWidgetPreferences" -> {
                    val content = call.argument<String>("content")?.takeIf { it == "today" || it == "cycle" } ?: "today"
                    val refresh = call.argument<Number>("refreshMinutes")?.toInt()?.takeIf { it in setOf(15, 30, 60) } ?: 30
                    database.putSetting("widget_content", content)
                    database.putSetting("widget_refresh_minutes", refresh.toString())
                    DataLensWidgetProvider.updateAll(this)
                    result.success(true)
                }
                "getRetentionDays" -> result.success(database.retentionDays())
                "saveRetentionDays" -> {
                    val days = (call.arguments as? Number)?.toInt() ?: 365
                    database.setRetentionDays(days)
                    DataLensWidgetProvider.updateAll(this)
                    result.success(true)
                }
                "getDeviceGuidance" -> result.success(deviceGuidance())
                "openBatterySettings" -> {
                    openBatterySettings()
                    result.success(true)
                }
                "exportCsv" -> createDocument(
                    result,
                    REQUEST_EXPORT_CSV,
                    "text/csv",
                    "datalens-usage-${LocalDate.now()}.csv",
                )
                "createBackup" -> createDocument(
                    result,
                    REQUEST_CREATE_BACKUP,
                    "application/json",
                    "datalens-backup-${LocalDate.now()}.json",
                )
                "restoreBackup" -> openBackup(result)
                "deleteAllData" -> {
                    database.deleteAll()
                    DataLensWidgetProvider.updateAll(this)
                    result.success(true)
                }
                else -> result.notImplemented()
            }
        }
    }

    @Deprecated("Deprecated in Android; required by FlutterActivity's document picker bridge")
    override fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?) {
        super.onActivityResult(requestCode, resultCode, data)
        if (requestCode !in setOf(REQUEST_EXPORT_CSV, REQUEST_CREATE_BACKUP, REQUEST_RESTORE_BACKUP)) return
        val pending = documentResult ?: return
        documentResult = null
        val uri = data?.data
        if (resultCode != Activity.RESULT_OK || uri == null) {
            pending.success(false)
            return
        }
        if (requestCode == REQUEST_RESTORE_BACKUP) MonitoringService.stop(this)
        executor.execute {
            try {
                when (requestCode) {
                    REQUEST_EXPORT_CSV -> contentResolver.openOutputStream(uri, "wt")!!.use(database::writeCsv)
                    REQUEST_CREATE_BACKUP -> contentResolver.openOutputStream(uri, "wt")!!.use(database::writeBackup)
                    REQUEST_RESTORE_BACKUP -> contentResolver.openInputStream(uri)!!.use(database::restoreBackup)
                }
                runOnUiThread {
                    DataLensWidgetProvider.updateAll(this)
                    if (requestCode == REQUEST_RESTORE_BACKUP && database.setting("monitoring_enabled") == "true") {
                        MonitoringService.start(this)
                    }
                    pending.success(true)
                }
            } catch (error: Exception) {
                runOnUiThread {
                    if (requestCode == REQUEST_RESTORE_BACKUP && database.setting("monitoring_enabled") == "true") {
                        MonitoringService.start(this)
                    }
                    pending.error("document_error", error.message ?: "Document operation failed", null)
                }
            }
        }
    }

    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        setIntent(intent)
        val destination = destinationFromIntent(intent) ?: return
        if (::methodChannel.isInitialized) {
            methodChannel.invokeMethod("destinationChanged", destination)
        } else {
            pendingDestination = destination
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

    private fun createDocument(
        result: MethodChannel.Result,
        requestCode: Int,
        mimeType: String,
        fileName: String,
    ) {
        if (documentResult != null) {
            result.error("request_in_progress", "A document picker is already open", null)
            return
        }
        documentResult = result
        try {
            startActivityForResult(Intent(Intent.ACTION_CREATE_DOCUMENT).apply {
                addCategory(Intent.CATEGORY_OPENABLE)
                type = mimeType
                putExtra(Intent.EXTRA_TITLE, fileName)
            }, requestCode)
        } catch (error: Exception) {
            documentResult = null
            result.error("document_picker_unavailable", error.message, null)
        }
    }

    private fun openBackup(result: MethodChannel.Result) {
        if (documentResult != null) {
            result.error("request_in_progress", "A document picker is already open", null)
            return
        }
        documentResult = result
        try {
            startActivityForResult(Intent(Intent.ACTION_OPEN_DOCUMENT).apply {
                addCategory(Intent.CATEGORY_OPENABLE)
                type = "application/json"
            }, REQUEST_RESTORE_BACKUP)
        } catch (error: Exception) {
            documentResult = null
            result.error("document_picker_unavailable", error.message, null)
        }
    }

    private fun deviceGuidance(): Map<String, Any> {
        val manufacturer = Build.MANUFACTURER.replaceFirstChar {
            if (it.isLowerCase()) it.titlecase(Locale.getDefault()) else it.toString()
        }
        val brand = Build.MANUFACTURER.lowercase(Locale.ROOT)
        val (title, steps) = when {
            brand.contains("samsung") -> "Samsung background setup" to listOf(
                "Set DataLens battery usage to Unrestricted in App info → Battery.",
                "Remove DataLens from Sleeping apps and Deep sleeping apps.",
                "Allow the persistent monitoring notification to remain visible.",
            )
            brand.contains("xiaomi") || brand.contains("redmi") || brand.contains("poco") ->
                "Xiaomi background setup" to listOf(
                    "Set Battery saver for DataLens to No restrictions.",
                    "Enable Autostart for DataLens in system settings.",
                    "Lock DataLens in Recents if monitoring is stopped by the device.",
                )
            brand.contains("huawei") || brand.contains("honor") -> "Huawei background setup" to listOf(
                "Open App launch, disable automatic management, and allow all three manual options.",
                "Exclude DataLens from battery optimization.",
            )
            brand.contains("oneplus") || brand.contains("oppo") || brand.contains("realme") ->
                "${manufacturer} background setup" to listOf(
                    "Allow background activity and set battery use to Unrestricted.",
                    "Enable Auto launch when that option is available.",
                )
            brand.contains("vivo") || brand.contains("iqoo") -> "Vivo background setup" to listOf(
                "Enable Autostart and high background power consumption for DataLens.",
                "Exclude DataLens from battery optimization.",
            )
            else -> "Android background setup" to listOf(
                "Allow background battery use for DataLens.",
                "If samples become stale, exclude DataLens from battery optimization.",
            )
        }
        val power = getSystemService(PowerManager::class.java)
        return mapOf(
            "manufacturer" to manufacturer,
            "model" to Build.MODEL,
            "androidVersion" to Build.VERSION.RELEASE,
            "title" to title,
            "steps" to steps,
            "optimizationExempt" to power.isIgnoringBatteryOptimizations(packageName),
        )
    }

    private fun openBatterySettings() {
        val intent = Intent(Settings.ACTION_IGNORE_BATTERY_OPTIMIZATION_SETTINGS)
        try {
            startActivity(intent)
        } catch (_: Exception) {
            startActivity(Intent(Settings.ACTION_APPLICATION_DETAILS_SETTINGS, Uri.parse("package:$packageName")))
        }
    }

    private fun destinationFromIntent(value: Intent?): String? {
        val explicit = value?.getStringExtra(EXTRA_DESTINATION)
        val candidate = explicit ?: value?.data?.pathSegments?.firstOrNull()
        return candidate?.takeIf { it in setOf("overview", "apps", "history", "alerts", "settings") }
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
            "overlayPermission" to Settings.canDrawOverlays(this),
            "overlayEnabled" to (database.setting("overlay_enabled") == "true" && Settings.canDrawOverlays(this)),
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
        const val EXTRA_DESTINATION = "io.andura.datalens.DESTINATION"
        private const val CHANNEL = "io.andura.datalens/usage"
        private const val NOTIFICATION_REQUEST = 4103
        private const val REQUEST_EXPORT_CSV = 4104
        private const val REQUEST_CREATE_BACKUP = 4105
        private const val REQUEST_RESTORE_BACKUP = 4106
    }
}
