package dev.merlin.camera

import android.app.Activity
import android.graphics.Color
import android.graphics.Typeface
import android.graphics.drawable.GradientDrawable
import android.os.Bundle
import android.view.Gravity
import android.view.View
import android.widget.*

open class MerlinActivity : Activity() {
    protected lateinit var page: LinearLayout
    protected val ink = Color.rgb(246,248,249)
    protected val muted = Color.rgb(153,166,176)
    protected val mint = Color.rgb(155,255,213)
    protected val dark = Color.rgb(11,17,24)
    protected fun dp(n: Int) = (n * resources.displayMetrics.density + .5f).toInt()
    protected fun screen(title: String, subtitle: String = "") {
        window.statusBarColor = dark
        window.navigationBarColor = dark
        val scroll = ScrollView(this).apply { setBackgroundColor(dark); isFillViewport = true }
        page = LinearLayout(this).apply { orientation = 1; setPadding(dp(22), dp(24), dp(22), dp(24)) }
        scroll.addView(page)
        setContentView(scroll)
        text("MERLIN / LITE", 12, mint)
        text(title, 30)
        if (subtitle.isNotEmpty()) text(subtitle, 14, muted)
    }
    protected fun text(value: String, size: Int = 16, color: Int = ink): TextView = TextView(this).apply {
        text = value; textSize = size.toFloat(); setTextColor(color); setPadding(0,dp(8),0,dp(8))
        page.addView(this, LinearLayout.LayoutParams(-1,-2))
    }
    protected fun button(value: String, action: () -> Unit): Button = Button(this).apply {
        text = value; isAllCaps = false; textSize = 16f; setTextColor(dark)
        background = GradientDrawable().apply { setColor(mint); cornerRadius = dp(16).toFloat() }
        page.addView(this, LinearLayout.LayoutParams(-1,dp(54)).apply { topMargin = dp(10) })
        setOnClickListener { action() }
    }
    protected fun field(hintText: String, type: Int = android.text.InputType.TYPE_CLASS_TEXT): EditText = EditText(this).apply {
        hint = hintText; inputType = type; setTextColor(ink); setHintTextColor(muted); textSize = 18f
        page.addView(this, LinearLayout.LayoutParams(-1,-2).apply { topMargin = dp(12) })
    }
    protected fun message(value: String) { Toast.makeText(this, value, Toast.LENGTH_LONG).show() }
}
