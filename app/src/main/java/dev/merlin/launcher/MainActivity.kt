package dev.merlin.launcher

import android.app.Activity
import android.app.AlertDialog
import android.app.role.RoleManager
import android.content.ComponentName
import android.content.Intent
import android.content.pm.PackageManager
import android.graphics.Color
import android.graphics.Typeface
import android.graphics.drawable.ColorDrawable
import android.graphics.drawable.Drawable
import android.graphics.drawable.GradientDrawable
import android.net.Uri
import android.os.Build
import android.os.Bundle
import android.os.Handler
import android.os.Looper
import android.os.SystemClock
import android.provider.Settings
import android.text.Editable
import android.text.TextWatcher
import android.util.TypedValue
import android.view.Gravity
import android.view.MotionEvent
import android.view.View
import android.view.ViewGroup
import android.view.WindowManager
import android.view.inputmethod.InputMethodManager
import android.widget.AdapterView
import android.widget.BaseAdapter
import android.widget.EditText
import android.widget.FrameLayout
import android.widget.GridView
import android.widget.ImageView
import android.widget.LinearLayout
import android.widget.TextView
import android.widget.Toast
import java.text.Collator
import java.text.SimpleDateFormat
import java.util.Date
import java.util.Locale
import java.util.concurrent.Executors

/** A compact home replacement with no network, tracking, widgets, or background services. */
class MainActivity : Activity() {
    private val background = Color.rgb(11, 17, 24)
    private val surface = Color.rgb(27, 37, 47)
    private val primary = Color.rgb(246, 248, 249)
    private val secondary = Color.rgb(153, 166, 176)
    private val accent = Color.rgb(155, 255, 213)

    private val preferences by lazy { getSharedPreferences("merlin", MODE_PRIVATE) }
    private val worker = Executors.newSingleThreadExecutor()
    private val handler = Handler(Looper.getMainLooper())

    private var installedApps: List<LaunchApp> = emptyList()
    private var lastLoad = 0L
    private var drawerVisible = false
    private var touchDownY = 0f
    private var touchDownX = 0f
    private var gesturesEnabled = true

    private lateinit var home: LinearLayout
    private lateinit var drawer: LinearLayout
    private lateinit var clock: TextView
    private lateinit var date: TextView
    private lateinit var favoritesView: GridView
    private lateinit var allAppsView: GridView
    private lateinit var search: EditText
    private lateinit var favoritesAdapter: LauncherAdapter
    private lateinit var allAdapter: LauncherAdapter

    private val clockUpdate = object : Runnable {
        override fun run() {
            updateClock()
            handler.postDelayed(this, 30_000L)
        }
    }

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        gesturesEnabled = preferences.getBoolean("gestures", true)
        window.statusBarColor = background
        window.navigationBarColor = background
        window.clearFlags(WindowManager.LayoutParams.FLAG_TRANSLUCENT_STATUS)
        window.addFlags(WindowManager.LayoutParams.FLAG_DRAWS_SYSTEM_BAR_BACKGROUNDS)
        constructScreen()
        loadApps()
    }

    override fun onResume() {
        super.onResume()
        handler.removeCallbacks(clockUpdate)
        clockUpdate.run()
        // Back from another app is cheap. Refresh only after enough time has passed.
        if (SystemClock.elapsedRealtime() - lastLoad > 30_000L) loadApps()
    }

    override fun onPause() {
        handler.removeCallbacks(clockUpdate)
        super.onPause()
    }

    override fun onDestroy() {
        worker.shutdownNow()
        super.onDestroy()
    }

    override fun onNewIntent(intent: Intent?) {
        super.onNewIntent(intent)
        // Pressing Home should always return to the light home screen.
        hideDrawer()
    }

    @Deprecated("Retained for reliable Android 12 and MIUI back behavior")
    override fun onBackPressed() {
        if (drawerVisible) hideDrawer() // Do not finish the HOME activity on Back.
    }

    // A single simple swipe on the home screen opens all applications.
    override fun dispatchTouchEvent(ev: MotionEvent): Boolean {
        when (ev.actionMasked) {
            MotionEvent.ACTION_DOWN -> {
                touchDownY = ev.y
                touchDownX = ev.x
            }
            MotionEvent.ACTION_UP -> {
                val deltaY = ev.y - touchDownY
                val deltaX = ev.x - touchDownX
                if (gesturesEnabled && !drawerVisible && deltaY < -dp(100) && kotlin.math.abs(deltaY) > kotlin.math.abs(deltaX) * 1.3f) {
                    showDrawer()
                    return true
                }
                if (gesturesEnabled && drawerVisible && touchDownX < dp(28) && deltaX > dp(90) && kotlin.math.abs(deltaX) > kotlin.math.abs(deltaY) * 1.3f) {
                    hideDrawer()
                    return true
                }
                if (gesturesEnabled && !drawerVisible && deltaY > dp(100) && kotlin.math.abs(deltaY) > kotlin.math.abs(deltaX) * 1.3f) {
                    runCatching { startActivity(Intent(Settings.ACTION_SETTINGS)) }
                    return true
                }
            }
        }
        return super.dispatchTouchEvent(ev)
    }

    private fun constructScreen() {
        val root = FrameLayout(this).apply { setBackgroundColor(this@MainActivity.background) }
        home = LinearLayout(this).apply {
            orientation = LinearLayout.VERTICAL
            setPadding(dp(24), dp(22), dp(24), dp(20))
        }
        drawer = LinearLayout(this).apply {
            orientation = LinearLayout.VERTICAL
            setPadding(dp(18), dp(18), dp(18), dp(12))
            visibility = View.GONE
        }
        root.addView(home, FrameLayout.LayoutParams(-1, -1))
        root.addView(drawer, FrameLayout.LayoutParams(-1, -1))
        setContentView(root)
        constructHome()
        constructDrawer()
    }

    private fun constructHome() {
        home.addView(label("MERLIN  /  LITE", 12f, accent, true).apply { letterSpacing = 0.25f })
        home.addView(spacer(16))
        home.addView(actionButton("Все приложения      ↑", true) { showDrawer() }, LinearLayout.LayoutParams(-1, dp(58)))
        home.addView(spacer(24))
        clock = label("--:--", 64f, primary, false).apply {
            typeface = Typeface.create("sans-serif-light", Typeface.NORMAL)
        }
        home.addView(clock)
        date = label("", 15f, secondary, false)
        home.addView(date)

        // The empty space is intentional: no scrolling news feed, widgets or background content.
        home.addView(View(this), LinearLayout.LayoutParams(1, 0, 1f))
        home.addView(label("ИЗБРАННОЕ", 12f, secondary, true).apply { letterSpacing = 0.15f })
        home.addView(spacer(13))
        favoritesAdapter = LauncherAdapter()
        favoritesView = createGrid(4).apply {
            adapter = favoritesAdapter
            onItemClickListener = AdapterView.OnItemClickListener { _, _, index, _ ->
                launch(favoritesAdapter.getItem(index))
            }
            onItemLongClickListener = AdapterView.OnItemLongClickListener { _, _, index, _ ->
                showAppActions(favoritesAdapter.getItem(index)); true
            }
        }
        home.addView(favoritesView, LinearLayout.LayoutParams(-1, dp(110)))
        home.addView(spacer(18))

        home.addView(actionButton("Диспетчер приложений", false) {
            val intent = packageManager.getLaunchIntentForPackage("dev.merlin.monitor")
            if (intent != null) startActivity(intent) else Toast.makeText(this, "Установите Merlin Monitor", Toast.LENGTH_SHORT).show()
        }, LinearLayout.LayoutParams(-1, dp(52)))
        home.addView(spacer(10))
        home.addView(label("↑ приложения · ↓ настройки · удержание: избранное", 11f, secondary).apply {
            gravity = Gravity.CENTER
        })
    }

    private fun constructDrawer() {
        val header = LinearLayout(this).apply { orientation = LinearLayout.HORIZONTAL; gravity = Gravity.CENTER_VERTICAL }
        val backButton = actionButton("‹", false) { hideDrawer() }.apply {
            textSize = 27f
            contentDescription = "Назад на рабочий стол"
        }
        header.addView(backButton, LinearLayout.LayoutParams(dp(51), dp(49)))
        val title = label("Приложения", 23f, primary, true).apply {
            setPadding(dp(16), 0, 0, 0)
        }
        header.addView(title, LinearLayout.LayoutParams(0, -2, 1f))
        val menuButton = actionButton("⋯", false) { showMenu() }.apply {
            textSize = 26f
            contentDescription = "Настройки лаунчера"
        }
        header.addView(menuButton, LinearLayout.LayoutParams(dp(51), dp(49)))
        drawer.addView(header)
        drawer.addView(spacer(17))

        search = EditText(this).apply {
            hint = "Поиск приложений"
            setHintTextColor(secondary)
            setTextColor(primary)
            textSize = 16f
            setSingleLine(true)
            setPadding(dp(19), 0, dp(17), 0)
            setBackgroundDrawable(rounded(surface, 17f))
            inputType = android.text.InputType.TYPE_CLASS_TEXT
            addTextChangedListener(object : TextWatcher {
                override fun beforeTextChanged(s: CharSequence?, start: Int, count: Int, after: Int) = Unit
                override fun onTextChanged(s: CharSequence?, start: Int, before: Int, count: Int) = filterApps()
                override fun afterTextChanged(s: Editable?) = Unit
            })
        }
        drawer.addView(search, LinearLayout.LayoutParams(-1, dp(53)))
        drawer.addView(spacer(14))
        allAdapter = LauncherAdapter()
        allAppsView = createGrid(4).apply {
            adapter = allAdapter
            onItemClickListener = AdapterView.OnItemClickListener { _, _, index, _ ->
                launch(allAdapter.getItem(index))
            }
            onItemLongClickListener = AdapterView.OnItemLongClickListener { _, _, index, _ ->
                showAppActions(allAdapter.getItem(index)); true
            }
        }
        drawer.addView(allAppsView, LinearLayout.LayoutParams(-1, 0, 1f))
        drawer.addView(label("Удерживай значок: избранное · скрыть · сведения", 11f, secondary).apply {
            gravity = Gravity.CENTER
            setPadding(0, dp(8), 0, 0)
        })
    }

    private fun loadApps() {
        lastLoad = SystemClock.elapsedRealtime()
        worker.execute {
            val pm = packageManager
            val intent = Intent(Intent.ACTION_MAIN).addCategory(Intent.CATEGORY_LAUNCHER)
            @Suppress("DEPRECATION")
            val resolved = pm.queryIntentActivities(intent, 0)
            val unique = LinkedHashMap<String, LaunchApp>()
            for (info in resolved) {
                val activityInfo = info.activityInfo ?: continue
                if (activityInfo.packageName == packageName) continue
                val component = ComponentName(activityInfo.packageName, activityInfo.name)
                val key = component.flattenToString()
                if (key in unique) continue
                val title = runCatching { info.loadLabel(pm).toString() }
                    .getOrDefault(activityInfo.packageName)
                val icon = runCatching { info.loadIcon(pm) }
                    .getOrElse { pm.defaultActivityIcon }
                unique[key] = LaunchApp(key, component, title, icon)
            }
            val localeCollator = Collator.getInstance(Locale.getDefault())
            val result = unique.values.sortedWith { a, b -> localeCollator.compare(a.title, b.title) }
            runOnUiThread {
                if (isFinishing || isDestroyed) return@runOnUiThread
                installedApps = result
                ensureDefaultFavorites()
                displayFavorites()
                filterApps()
            }
        }
    }

    private fun ensureDefaultFavorites() {
        if (preferences.contains(KEY_FAVORITES)) return
        val preferredPackages = listOf(
            "com.google.android.dialer",
            "com.google.android.apps.messaging",
            "com.android.camera",
            "com.android.chrome",
            "com.google.android.contacts"
        )
        val defaults = preferredPackages.mapNotNull { pkg ->
            installedApps.firstOrNull { it.component.packageName == pkg }?.id
        }.take(4)
        preferences.edit().putString(KEY_FAVORITES, defaults.joinToString("|")).apply()
    }

    private fun readFavorites(): MutableList<String> = preferences
        .getString(KEY_FAVORITES, "").orEmpty().split('|').filter { it.isNotEmpty() }.toMutableList()

    private fun readHidden(): Set<String> = preferences.getStringSet(KEY_HIDDEN, emptySet())?.toSet().orEmpty()

    private fun displayFavorites() {
        val pinned = readFavorites().take(8).mapNotNull { key -> installedApps.firstOrNull { it.id == key } }
        favoritesView.layoutParams = (favoritesView.layoutParams as LinearLayout.LayoutParams).apply {
            height = dp(if (pinned.size > 4) 212 else 110)
        }
        favoritesAdapter.submit(pinned)
    }

    private fun filterApps() {
        val query = if (::search.isInitialized) search.text.toString().trim().lowercase(Locale.getDefault()) else ""
        val hidden = readHidden()
        allAdapter.submit(installedApps.filter {
            it.id !in hidden && (query.isEmpty() || it.title.lowercase(Locale.getDefault()).contains(query))
        })
    }

    private fun launch(app: LaunchApp) {
        val launchIntent = Intent.makeMainActivity(app.component).apply {
            addFlags(Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_RESET_TASK_IF_NEEDED)
        }
        runCatching { startActivity(launchIntent) }
            .onFailure { Toast.makeText(this, "Не удалось открыть ${app.title}", Toast.LENGTH_SHORT).show() }
    }

    private fun showAppActions(app: LaunchApp) {
        val pinned = app.id in readFavorites()
        val actions = arrayOf(if (pinned) "Убрать из избранного" else "В избранное", "Скрыть из списка", "Сведения о приложении")
        AlertDialog.Builder(this)
            .setTitle(app.title)
            .setItems(actions) { _, which ->
                when (which) {
                    0 -> {
                        val saved = readFavorites()
                        if (pinned) saved.remove(app.id)
                        else if (saved.size < 8) saved.add(app.id)
                        else { Toast.makeText(this, "Максимум 8 избранных", Toast.LENGTH_SHORT).show(); return@setItems }
                        preferences.edit().putString(KEY_FAVORITES, saved.joinToString("|")).apply()
                        displayFavorites()
                    }
                    1 -> AlertDialog.Builder(this)
                        .setMessage("Скрыть «${app.title}» из меню? Приложение не удалится.")
                        .setNegativeButton("Отмена", null)
                        .setPositiveButton("Скрыть") { _, _ ->
                            val hidden = readHidden().toMutableSet().apply { add(app.id) }
                            preferences.edit().putStringSet(KEY_HIDDEN, hidden).apply()
                            val saved = readFavorites().apply { remove(app.id) }
                            preferences.edit().putString(KEY_FAVORITES, saved.joinToString("|")).apply()
                            displayFavorites()
                            filterApps()
                        }.show()
                    2 -> startActivity(Intent(Settings.ACTION_APPLICATION_DETAILS_SETTINGS,
                        Uri.parse("package:${app.component.packageName}")))
                }
            }.show()
    }

    private fun showMenu() {
        AlertDialog.Builder(this)
            .setTitle("Merlin Launcher Lite")
            .setItems(arrayOf("Сделать основным лаунчером", "Показать скрытые приложения", "Обновить список", "О программе", "Жесты внутри лаунчера", "Системная навигация")) { _, index ->
                when (index) {
                    0 -> requestHomeRole()
                    1 -> showHiddenApps()
                    2 -> loadApps()
                    3 -> AlertDialog.Builder(this)
                        .setTitle("Merlin Launcher Lite 0.2")
                        .setMessage("Быстрый лаунчер без рекламы, сети и фоновых служб. MIUI Home остаётся установленным для безопасного возврата.")
                        .setPositiveButton("ОК", null).show()
                    4 -> AlertDialog.Builder(this).setTitle("Жесты лаунчера")
                        .setMultiChoiceItems(arrayOf("Включить: вверх — приложения; вниз — настройки; от левого края — назад"), booleanArrayOf(gesturesEnabled)) { _, _, checked ->
                            gesturesEnabled = checked
                            preferences.edit().putBoolean("gestures", checked).apply()
                        }.setPositiveButton("Готово", null).show()
                    5 -> runCatching {
                        startActivity(Intent().setComponent(ComponentName("com.android.settings", "com.android.settings.Settings\$NavigationBarSettingsActivity")))
                    }.onFailure { startActivity(Intent(Settings.ACTION_SETTINGS)) }
                }
            }.show()
    }

    private fun showHiddenApps() {
        val hidden = readHidden()
        val entries = installedApps.filter { it.id in hidden }
        if (entries.isEmpty()) {
            Toast.makeText(this, "Скрытых приложений нет", Toast.LENGTH_SHORT).show()
            return
        }
        AlertDialog.Builder(this).setTitle("Показать приложение")
            .setItems(entries.map { it.title }.toTypedArray()) { _, index ->
                val changed = hidden.toMutableSet().apply { remove(entries[index].id) }
                preferences.edit().putStringSet(KEY_HIDDEN, changed).apply()
                filterApps()
            }.setNegativeButton("Закрыть", null).show()
    }

    private fun requestHomeRole() {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
            val roleManager = getSystemService(RoleManager::class.java)
            if (roleManager.isRoleAvailable(RoleManager.ROLE_HOME) && !roleManager.isRoleHeld(RoleManager.ROLE_HOME)) {
                startActivityForResult(roleManager.createRequestRoleIntent(RoleManager.ROLE_HOME), 100)
                return
            }
        }
        runCatching { startActivity(Intent(Settings.ACTION_HOME_SETTINGS)) }
            .onFailure { Toast.makeText(this, "Настройки → Приложения → Приложения по умолчанию → Рабочий стол", Toast.LENGTH_LONG).show() }
    }

    private fun showDrawer() {
        if (drawerVisible) return
        drawerVisible = true
        home.visibility = View.GONE
        drawer.visibility = View.VISIBLE
        search.setText("")
        // Do not auto-open the keyboard; it obscures the app grid.
        search.clearFocus()
    }

    private fun hideDrawer() {
        if (!drawerVisible) return
        drawerVisible = false
        (getSystemService(INPUT_METHOD_SERVICE) as InputMethodManager)
            .hideSoftInputFromWindow(search.windowToken, 0)
        search.clearFocus()
        drawer.visibility = View.GONE
        home.visibility = View.VISIBLE
    }

    private fun updateClock() {
        if (!::clock.isInitialized) return
        val now = Date()
        clock.text = SimpleDateFormat("HH:mm", Locale.getDefault()).format(now)
        date.text = SimpleDateFormat("EEEE, d MMMM", Locale("ru", "RU")).format(now)
    }

    private fun createGrid(columns: Int): GridView = GridView(this).apply {
        numColumns = columns
        verticalSpacing = dp(13)
        horizontalSpacing = dp(3)
        stretchMode = GridView.STRETCH_COLUMN_WIDTH
        selector = ColorDrawable(Color.TRANSPARENT)
        isVerticalScrollBarEnabled = false
        clipToPadding = false
        setPadding(0, dp(4), 0, dp(10))
        setBackgroundColor(Color.TRANSPARENT)
    }

    private fun label(value: String, sp: Float, color: Int, bold: Boolean = false) = TextView(this).apply {
        text = value
        setTextColor(color)
        setTextSize(TypedValue.COMPLEX_UNIT_SP, sp)
        includeFontPadding = false
        if (bold) typeface = Typeface.create("sans-serif-medium", Typeface.NORMAL)
    }

    private fun actionButton(value: String, highlighted: Boolean, onClick: () -> Unit): TextView =
        label(value, 15f, if (highlighted) background else primary, true).apply {
            gravity = Gravity.CENTER
            background = rounded(if (highlighted) accent else surface, 18f)
            setOnClickListener { onClick() }
            isClickable = true
            isFocusable = true
        }

    private fun rounded(color: Int, radiusDp: Float) = GradientDrawable().apply {
        setColor(color)
        cornerRadius = dpF(radiusDp)
    }

    private fun spacer(height: Int) = View(this).apply {
        layoutParams = LinearLayout.LayoutParams(1, dp(height))
    }

    private fun dp(amount: Int): Int = (amount * resources.displayMetrics.density + 0.5f).toInt()
    private fun dpF(amount: Float): Float = amount * resources.displayMetrics.density

    private inner class LauncherAdapter : BaseAdapter() {
        private var content: List<LaunchApp> = emptyList()

        fun submit(items: List<LaunchApp>) {
            content = items
            notifyDataSetChanged()
        }

        override fun getCount(): Int = content.size
        override fun getItem(position: Int): LaunchApp = content[position]
        override fun getItemId(position: Int): Long = getItem(position).id.hashCode().toLong()

        override fun getView(position: Int, convertView: View?, parent: ViewGroup): View {
            val cell: LinearLayout
            val holder: CellHolder
            if (convertView is LinearLayout && convertView.tag is CellHolder) {
                cell = convertView
                holder = cell.tag as CellHolder
            } else {
                cell = LinearLayout(this@MainActivity).apply {
                    orientation = LinearLayout.VERTICAL
                    gravity = Gravity.TOP or Gravity.CENTER_HORIZONTAL
                    setPadding(dp(2), dp(7), dp(2), dp(4))
                    minimumHeight = dp(90)
                }
                val iconView = ImageView(this@MainActivity).apply {
                    scaleType = ImageView.ScaleType.FIT_CENTER
                }
                cell.addView(iconView, LinearLayout.LayoutParams(dp(52), dp(52)))
                cell.addView(View(this@MainActivity), LinearLayout.LayoutParams(1, dp(6)))
                val appLabel = label("", 11.5f, primary).apply {
                    gravity = Gravity.TOP or Gravity.CENTER_HORIZONTAL
                    maxLines = 2
                    ellipsize = android.text.TextUtils.TruncateAt.END
                }
                cell.addView(appLabel, LinearLayout.LayoutParams(-1, dp(34)))
                holder = CellHolder(iconView, appLabel)
                cell.tag = holder
            }
            val app = getItem(position)
            holder.icon.setImageDrawable(app.icon.constantState?.newDrawable(resources) ?: app.icon)
            holder.title.text = app.title
            cell.contentDescription = app.title
            return cell
        }
    }

    private data class CellHolder(val icon: ImageView, val title: TextView)
    private data class LaunchApp(val id: String, val component: ComponentName, val title: String, val icon: Drawable)

    companion object {
        private const val KEY_FAVORITES = "favorite_components"
        private const val KEY_HIDDEN = "hidden_components"
    }
}
