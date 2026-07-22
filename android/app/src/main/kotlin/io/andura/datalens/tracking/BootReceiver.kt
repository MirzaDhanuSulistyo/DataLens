package io.andura.datalens.tracking

import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent

class BootReceiver : BroadcastReceiver() {
    override fun onReceive(context: Context, intent: Intent?) {
        if (UsageDatabase(context).setting("monitoring_enabled") == "true") {
            MonitoringService.start(context)
        }
    }
}
