package dev.merlin.launcher

import android.accessibilityservice.AccessibilityService
import android.app.KeyguardManager
import android.graphics.Color
import android.graphics.PixelFormat
import android.os.SystemClock
import android.view.Gravity
import android.view.MotionEvent
import android.view.View
import android.view.WindowManager
import android.view.accessibility.AccessibilityEvent

/** User-enabled global navigation; no access to window contents. */
class GestureService : AccessibilityService() {
    private val handles = mutableListOf<View>()
    private lateinit var manager: WindowManager
    private fun dp(n: Int) = (n * resources.displayMetrics.density + .5f).toInt()
    override fun onServiceConnected() {
        manager = getSystemService(WINDOW_SERVICE) as WindowManager
        clearHandles()
        addHandle(Gravity.BOTTOM or Gravity.CENTER_HORIZONTAL, dp(190), dp(22), true)
        addHandle(Gravity.LEFT or Gravity.CENTER_VERTICAL, dp(14), dp(220), false)
        addHandle(Gravity.RIGHT or Gravity.CENTER_VERTICAL, dp(14), dp(220), false)
    }
    private fun addHandle(gravity: Int, width: Int, height: Int, bottom: Boolean) {
        val view = View(this).apply {
            setBackgroundColor(Color.argb(28,255,255,255))
            contentDescription = if(bottom) "Умная Точка: вверх — Домой, вверх с удержанием — Недавние" else "Умная Точка: от края — Назад"
        }
        var x = 0f; var y = 0f; var start = 0L
        view.setOnTouchListener { _, event ->
            if (getSystemService(KeyguardManager::class.java).isKeyguardLocked) return@setOnTouchListener false
            when(event.actionMasked) {
                MotionEvent.ACTION_DOWN -> { x=event.rawX; y=event.rawY; start=SystemClock.uptimeMillis(); true }
                MotionEvent.ACTION_UP -> {
                    val dx=event.rawX-x; val dy=event.rawY-y
                    if(bottom && dy < -dp(60)) performGlobalAction(if(SystemClock.uptimeMillis()-start>650) GLOBAL_ACTION_RECENTS else GLOBAL_ACTION_HOME)
                    else if(!bottom && kotlin.math.abs(dx)>dp(60) && kotlin.math.abs(dx)>kotlin.math.abs(dy)) performGlobalAction(GLOBAL_ACTION_BACK)
                    true
                }
                else -> true
            }
        }
        val params=WindowManager.LayoutParams(width,height,WindowManager.LayoutParams.TYPE_ACCESSIBILITY_OVERLAY,
            WindowManager.LayoutParams.FLAG_NOT_FOCUSABLE or WindowManager.LayoutParams.FLAG_NOT_TOUCH_MODAL,
            PixelFormat.TRANSLUCENT).apply { this.gravity=gravity }
        runCatching { manager.addView(view,params);handles.add(view) }
    }
    private fun clearHandles(){ if(::manager.isInitialized) handles.forEach{runCatching{manager.removeView(it)}};handles.clear() }
    override fun onDestroy(){clearHandles();super.onDestroy()}
    override fun onInterrupt(){}
    override fun onAccessibilityEvent(event: AccessibilityEvent?){}
}
