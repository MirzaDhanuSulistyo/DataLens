package io.andura.datalens.tracking

import android.content.Context
import android.net.TetheringManager
import android.os.Build
import androidx.annotation.RequiresApi
import java.lang.reflect.Proxy

/** Records hotspot/tethering sessions while this process is alive. */
class HotspotStateMonitor(context: Context) {
    private val appContext = context.applicationContext
    private val delegate: StateMonitorDelegate? = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.R) {
        Api30StateMonitor(appContext)
    } else {
        null
    }

    fun start() {
        if (delegate == null) {
            UsageDatabase(appContext).recordHotspotState(
                null, System.currentTimeMillis(), "state_api_unavailable",
            )
        } else {
            delegate.start()
        }
    }

    fun stop() = delegate?.stop() ?: Unit
}

private interface StateMonitorDelegate {
    fun start()
    fun stop()
}

/**
 * Android 11+ delivers the current state immediately after registration. A
 * dynamic proxy handles both the older List callback and the newer public Set
 * callback without binding DataLens to an OEM-specific interface name.
 */
@RequiresApi(Build.VERSION_CODES.R)
private class Api30StateMonitor(context: Context) : StateMonitorDelegate {
    private val appContext = context.applicationContext
    private val database = UsageDatabase(appContext)
    private var manager: TetheringManager? = null
    private var callback: TetheringManager.TetheringEventCallback? = null

    override fun start() {
        if (callback != null) return
        try {
            val callbackType = TetheringManager.TetheringEventCallback::class.java
            val listener = Proxy.newProxyInstance(
                callbackType.classLoader,
                arrayOf(callbackType),
            ) { proxy, method, args ->
                when (method.name) {
                    "hashCode" -> System.identityHashCode(proxy)
                    "equals" -> proxy === args?.firstOrNull()
                    "toString" -> "DataLensTetheringEventCallback"
                    "onTetheredInterfacesChanged" -> {
                        val interfaces = args?.firstOrNull() as? Collection<*>
                        database.recordHotspotState(
                            interfaces?.isNotEmpty() == true,
                            System.currentTimeMillis(),
                            "system_callback",
                        )
                        null
                    }
                    else -> null
                }
            } as TetheringManager.TetheringEventCallback
            val tetheringManager = appContext.getSystemService(TetheringManager::class.java)
            tetheringManager.registerTetheringEventCallback(appContext.mainExecutor, listener)
            manager = tetheringManager
            callback = listener
        } catch (_: SecurityException) {
            unavailable("state_permission_unavailable")
        } catch (_: RuntimeException) {
            unavailable("state_oem_unavailable")
        }
    }

    override fun stop() {
        val listener = callback ?: return
        try {
            manager?.unregisterTetheringEventCallback(listener)
        } catch (_: RuntimeException) {
            // The system may already have removed the callback during shutdown.
        }
        callback = null
        manager = null
    }

    private fun unavailable(quality: String) {
        database.recordHotspotState(null, System.currentTimeMillis(), quality)
    }
}
