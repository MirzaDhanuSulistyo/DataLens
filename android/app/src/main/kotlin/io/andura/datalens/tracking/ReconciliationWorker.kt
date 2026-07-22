package io.andura.datalens.tracking

import android.content.Context
import androidx.work.CoroutineWorker
import androidx.work.WorkerParameters

class ReconciliationWorker(
    context: Context,
    params: WorkerParameters,
) : CoroutineWorker(context, params) {
    override suspend fun doWork(): Result = try {
        val collector = UsageCollector(applicationContext)
        collector.collectSnapshot()
        collector.reconcile()
        Result.success()
    } catch (_: Exception) {
        Result.retry()
    }
}
