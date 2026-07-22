package io.andura.datalens.tracking

import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.app.Service
import android.content.Context
import android.content.Intent
import android.os.Handler
import android.os.IBinder
import android.os.Looper
import androidx.core.app.NotificationCompat
import androidx.core.content.ContextCompat
import androidx.work.ExistingPeriodicWorkPolicy
import androidx.work.PeriodicWorkRequestBuilder
import androidx.work.WorkManager
import io.andura.datalens.MainActivity
import java.util.concurrent.TimeUnit
import kotlin.math.max

class MonitoringService : Service() {
    private val handler = Handler(Looper.getMainLooper())
    private lateinit var collector: UsageCollector
    private lateinit var database: UsageDatabase
    private var lastRx = 0L
    private var lastTx = 0L
    private var lastElapsed = 0L
    private var lastPersisted = 0L

    private val tick = object : Runnable {
        override fun run() {
            val counters = collector.liveCounters()
            val rx = counters["rxBytes"] as Long
            val tx = counters["txBytes"] as Long
            val elapsed = counters["monotonicMillis"] as Long
            val seconds = max(0.001, (elapsed - lastElapsed) / 1000.0)
            val down = if (lastElapsed == 0L) 0.0 else max(0L, rx - lastRx) * 8 / seconds
            val up = if (lastElapsed == 0L) 0.0 else max(0L, tx - lastTx) * 8 / seconds
            lastRx = rx; lastTx = tx; lastElapsed = elapsed
            if (elapsed - lastPersisted >= SAMPLE_INTERVAL_MS) {
                collector.collectSnapshot()
                lastPersisted = elapsed
            }
            notificationManager().notify(NOTIFICATION_ID, notification(down, up))
            handler.postDelayed(this, LIVE_INTERVAL_MS)
        }
    }

    override fun onCreate() {
        super.onCreate()
        collector = UsageCollector(this)
        database = UsageDatabase(this)
        notificationManager().createNotificationChannel(NotificationChannel(
            CHANNEL_ID, "Data usage monitoring", NotificationManager.IMPORTANCE_LOW,
        ).apply { description = "Shows live transfer speed while monitoring is enabled" })
    }

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        if (intent?.action == ACTION_STOP) {
            stopMonitoring()
            return START_NOT_STICKY
        }
        database.putSetting("monitoring_enabled", "true")
        startForeground(NOTIFICATION_ID, notification(0.0, 0.0))
        collector.collectSnapshot()
        lastPersisted = android.os.SystemClock.elapsedRealtime()
        handler.removeCallbacks(tick)
        handler.post(tick)
        scheduleReconciliation(this)
        return START_STICKY
    }

    override fun onDestroy() {
        handler.removeCallbacks(tick)
        super.onDestroy()
    }

    override fun onBind(intent: Intent?): IBinder? = null

    private fun stopMonitoring() {
        database.putSetting("monitoring_enabled", "false")
        handler.removeCallbacks(tick)
        WorkManager.getInstance(this).cancelUniqueWork(RECONCILIATION_WORK)
        stopForeground(STOP_FOREGROUND_REMOVE)
        stopSelf()
    }

    private fun notification(downBits: Double, upBits: Double) = NotificationCompat.Builder(this, CHANNEL_ID)
        .setSmallIcon(android.R.drawable.stat_sys_download_done)
        .setContentTitle("DataLens monitoring")
        .setContentText("↓ ${formatRate(downBits)}  ↑ ${formatRate(upBits)}")
        .setContentIntent(PendingIntent.getActivity(
            this, 0, Intent(this, MainActivity::class.java),
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE,
        ))
        .addAction(0, "Stop", PendingIntent.getService(
            this, 1, Intent(this, MonitoringService::class.java).setAction(ACTION_STOP),
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE,
        ))
        .setOngoing(true).setOnlyAlertOnce(true).build()

    private fun notificationManager() = getSystemService(NotificationManager::class.java)

    private fun formatRate(bits: Double): String = when {
        bits >= 1_000_000 -> String.format("%.1f Mbps", bits / 1_000_000)
        bits >= 1_000 -> String.format("%.0f Kbps", bits / 1_000)
        else -> "${bits.toLong()} bps"
    }

    companion object {
        const val CHANNEL_ID = "datalens_monitoring"
        const val NOTIFICATION_ID = 4102
        const val ACTION_STOP = "io.andura.datalens.STOP_MONITORING"
        const val RECONCILIATION_WORK = "datalens_reconciliation"
        private const val LIVE_INTERVAL_MS = 2_000L
        private const val SAMPLE_INTERVAL_MS = 60_000L

        fun start(context: Context) {
            UsageDatabase(context).putSetting("monitoring_enabled", "true")
            ContextCompat.startForegroundService(context, Intent(context, MonitoringService::class.java))
        }

        fun stop(context: Context) {
            UsageDatabase(context).putSetting("monitoring_enabled", "false")
            context.startService(Intent(context, MonitoringService::class.java).setAction(ACTION_STOP))
        }

        fun scheduleReconciliation(context: Context) {
            val request = PeriodicWorkRequestBuilder<ReconciliationWorker>(15, TimeUnit.MINUTES).build()
            WorkManager.getInstance(context).enqueueUniquePeriodicWork(
                RECONCILIATION_WORK, ExistingPeriodicWorkPolicy.UPDATE, request,
            )
        }
    }
}
