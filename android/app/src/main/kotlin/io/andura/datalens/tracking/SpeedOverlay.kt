package io.andura.datalens.tracking

import android.content.Context
import android.graphics.PixelFormat
import android.graphics.Typeface
import android.provider.Settings
import android.view.Gravity
import android.view.MotionEvent
import android.view.View
import android.view.WindowManager
import android.widget.LinearLayout
import android.widget.TextView
import kotlin.math.roundToInt

/** Small, explicitly enabled system overlay. It never intercepts traffic. */
class SpeedOverlay(private val context: Context, private val onDismiss: () -> Unit) {
    private val windowManager = context.getSystemService(WindowManager::class.java)
    private var root: LinearLayout? = null
    private var speedText: TextView? = null
    private var params: WindowManager.LayoutParams? = null

    fun update(down: String, up: String, enabled: Boolean) {
        if (!enabled || !Settings.canDrawOverlays(context)) {
            hide()
            return
        }
        if (root == null) show()
        speedText?.text = "↓ $down  ↑ $up"
    }

    fun hide() {
        root?.let { runCatching { windowManager.removeView(it) } }
        root = null
        speedText = null
        params = null
    }

    private fun show() {
        val density = context.resources.displayMetrics.density
        val container = LinearLayout(context).apply {
            orientation = LinearLayout.HORIZONTAL
            gravity = Gravity.CENTER_VERTICAL
            setPadding((12 * density).roundToInt(), (8 * density).roundToInt(),
                (6 * density).roundToInt(), (8 * density).roundToInt())
            setBackgroundColor(0xE6222630.toInt())
            contentDescription = "DataLens live network speed. Drag to move."
        }
        val speedLabel = TextView(context).apply {
            setTextColor(0xFFFFFFFF.toInt())
            textSize = 13f
            typeface = Typeface.DEFAULT_BOLD
            text = "↓ —  ↑ —"
        }
        val close = TextView(context).apply {
            setTextColor(0xFFCBD0DC.toInt())
            textSize = 18f
            text = "  ×  "
            contentDescription = "Dismiss live speed overlay"
            gravity = Gravity.CENTER
            setOnClickListener {
                UsageDatabase(context).putSetting("overlay_enabled", "false")
                hide()
                onDismiss()
            }
        }
        container.addView(speedLabel)
        container.addView(close)
        val layout = WindowManager.LayoutParams(
            WindowManager.LayoutParams.WRAP_CONTENT,
            WindowManager.LayoutParams.WRAP_CONTENT,
            WindowManager.LayoutParams.TYPE_APPLICATION_OVERLAY,
            WindowManager.LayoutParams.FLAG_NOT_FOCUSABLE or
                WindowManager.LayoutParams.FLAG_LAYOUT_NO_LIMITS,
            PixelFormat.TRANSLUCENT,
        ).apply {
            gravity = Gravity.TOP or Gravity.START
            x = UsageDatabase(context).setting("overlay_x")?.toIntOrNull() ?: (16 * density).roundToInt()
            y = UsageDatabase(context).setting("overlay_y")?.toIntOrNull() ?: (120 * density).roundToInt()
        }
        addDragListener(container, layout)
        windowManager.addView(container, layout)
        root = container
        speedText = speedLabel
        params = layout
    }

    private fun addDragListener(view: View, layout: WindowManager.LayoutParams) {
        var initialX = 0
        var initialY = 0
        var touchX = 0f
        var touchY = 0f
        view.setOnTouchListener { _, event ->
            when (event.action) {
                MotionEvent.ACTION_DOWN -> {
                    initialX = layout.x; initialY = layout.y
                    touchX = event.rawX; touchY = event.rawY
                    true
                }
                MotionEvent.ACTION_MOVE -> {
                    layout.x = initialX + (event.rawX - touchX).roundToInt()
                    layout.y = initialY + (event.rawY - touchY).roundToInt()
                    root?.let { windowManager.updateViewLayout(it, layout) }
                    true
                }
                MotionEvent.ACTION_UP -> {
                    UsageDatabase(context).putSetting("overlay_x", layout.x.toString())
                    UsageDatabase(context).putSetting("overlay_y", layout.y.toString())
                    false
                }
                else -> false
            }
        }
    }
}
