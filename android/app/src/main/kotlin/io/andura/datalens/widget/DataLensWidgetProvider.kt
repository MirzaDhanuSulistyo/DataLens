package io.andura.datalens.widget

import android.app.PendingIntent
import android.appwidget.AppWidgetManager
import android.appwidget.AppWidgetProvider
import android.content.ComponentName
import android.content.Context
import android.content.Intent
import android.net.Uri
import android.widget.RemoteViews
import io.andura.datalens.MainActivity
import io.andura.datalens.R
import io.andura.datalens.tracking.UsageDatabase
import java.time.LocalDate
import java.time.ZoneId

class DataLensWidgetProvider : AppWidgetProvider() {
    override fun onUpdate(context: Context, manager: AppWidgetManager, ids: IntArray) {
        ids.forEach { update(context, manager, it) }
    }

    companion object {
        fun updateAll(context: Context) {
            val manager = AppWidgetManager.getInstance(context)
            val component = ComponentName(context, DataLensWidgetProvider::class.java)
            manager.getAppWidgetIds(component).forEach { update(context, manager, it) }
            UsageDatabase(context).putSetting("last_widget_update_at", System.currentTimeMillis().toString())
        }

        fun maybeUpdate(context: Context) {
            val database = UsageDatabase(context)
            val minutes = database.setting("widget_refresh_minutes")?.toLongOrNull() ?: 30L
            val last = database.setting("last_widget_update_at")?.toLongOrNull() ?: 0L
            if (System.currentTimeMillis() - last >= minutes * 60_000L) updateAll(context)
        }

        private fun update(context: Context, manager: AppWidgetManager, id: Int) {
            val database = UsageDatabase(context)
            val now = System.currentTimeMillis()
            val zone = ZoneId.systemDefault()
            val todayStart = LocalDate.now(zone).atStartOfDay(zone).toInstant().toEpochMilli()
            val content = database.setting("widget_content") ?: "today"
            val total: Long
            val label: String
            val detail: String
            if (content == "cycle") {
                val plan = database.plan()
                val cycleDay = plan?.get("cycleDay") as? Int ?: 1
                val start = cycleStart(cycleDay, zone)
                total = database.summary(start, now, "mobile").values.sum()
                val cap = plan?.get("capBytes") as? Long
                label = "THIS BILLING CYCLE"
                detail = if (cap == null || cap <= 0) "Mobile usage" else "of ${formatBytes(cap)} plan"
            } else {
                total = database.summary(todayStart, now, "all").values.sum()
                label = "USED TODAY"
                detail = "Measured on this device"
            }
            val views = RemoteViews(context.packageName, R.layout.datalens_widget).apply {
                setTextViewText(R.id.widget_label, label)
                setTextViewText(R.id.widget_value, formatBytes(total))
                setTextViewText(R.id.widget_detail, detail)
                setTextViewText(R.id.widget_updated, "Updated ${timeLabel()}")
                setContentDescription(R.id.widget_value, "$label ${formatBytes(total)}")
                setOnClickPendingIntent(R.id.widget_root, destinationIntent(context, "overview", id))
                setOnClickPendingIntent(R.id.widget_history, destinationIntent(context, "history", id + 10_000))
            }
            manager.updateAppWidget(id, views)
        }

        private fun destinationIntent(context: Context, destination: String, requestCode: Int): PendingIntent {
            val intent = Intent(context, MainActivity::class.java).apply {
                action = Intent.ACTION_VIEW
                data = Uri.parse("datalens://open/$destination")
                putExtra(MainActivity.EXTRA_DESTINATION, destination)
                flags = Intent.FLAG_ACTIVITY_CLEAR_TOP or Intent.FLAG_ACTIVITY_SINGLE_TOP
            }
            return PendingIntent.getActivity(
                context, requestCode, intent,
                PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE,
            )
        }

        private fun cycleStart(day: Int, zone: ZoneId): Long {
            val today = LocalDate.now(zone)
            fun resolve(date: LocalDate): LocalDate = date.withDayOfMonth(day.coerceIn(1, date.lengthOfMonth()))
            var value = resolve(today.withDayOfMonth(1))
            if (today.isBefore(value)) value = resolve(today.minusMonths(1).withDayOfMonth(1))
            return value.atStartOfDay(zone).toInstant().toEpochMilli()
        }

        private fun formatBytes(bytes: Long): String = when {
            bytes >= 1_000_000_000 -> String.format("%.1f GB", bytes / 1_000_000_000.0)
            bytes >= 1_000_000 -> String.format("%.1f MB", bytes / 1_000_000.0)
            bytes >= 1_000 -> String.format("%.0f KB", bytes / 1_000.0)
            else -> "$bytes B"
        }

        private fun timeLabel(): String {
            val now = java.time.LocalTime.now()
            val hour = if (now.hour % 12 == 0) 12 else now.hour % 12
            return "$hour:${now.minute.toString().padStart(2, '0')} ${if (now.hour < 12) "AM" else "PM"}"
        }
    }
}
