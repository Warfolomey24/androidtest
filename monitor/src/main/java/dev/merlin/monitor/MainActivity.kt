package dev.merlin.monitor

import android.app.AppOpsManager
import android.app.ActivityManager
import android.app.usage.UsageStatsManager
import android.content.Intent
import android.net.Uri
import android.os.Bundle
import android.os.Process
import android.provider.Settings
import java.text.SimpleDateFormat
import java.util.*
import java.util.concurrent.Executors

class MainActivity : MerlinActivity() {
    private val worker = Executors.newSingleThreadExecutor()
    private var generation = 0
    override fun onCreate(state: Bundle?) { super.onCreate(state); showUsage() }
    override fun onDestroy() { generation++; worker.shutdownNow(); super.onDestroy() }
    private fun header(title: String) {
        generation++
        screen(title,"Данные остаются на телефоне. Без рекламы и интернета.")
        button("Использование за 24 часа") { showUsage() }
        button("Процессы: снимок с компьютера") { showProcesses() }
        val mem = ActivityManager.MemoryInfo()
        (getSystemService(ACTIVITY_SERVICE) as ActivityManager).getMemoryInfo(mem)
        text("ОЗУ: доступно ${mem.availMem / 1048576} из ${mem.totalMem / 1048576} МБ",14,muted)
    }
    private fun showUsage() {
        header("Активность приложений")
        text("Это история использования, а не список процессов, работающих сейчас.",14,muted)
        val ops = getSystemService(APP_OPS_SERVICE) as AppOpsManager
        if (ops.checkOpNoThrow(AppOpsManager.OPSTR_GET_USAGE_STATS, Process.myUid(), packageName) != AppOpsManager.MODE_ALLOWED) {
            button("Разрешить доступ к статистике") { startActivity(Intent(Settings.ACTION_USAGE_ACCESS_SETTINGS, Uri.parse("package:$packageName"))) }
            button("Проверить разрешение / обновить") { showUsage() }
            return
        }
        button("Обновить") { showUsage() }
        val loading = text("Загрузка…",14,muted)
        val ticket = generation
        worker.execute {
            val now = System.currentTimeMillis()
            val result = runCatching {
                (getSystemService(USAGE_STATS_SERVICE) as UsageStatsManager)
                    .queryAndAggregateUsageStats(now-86400000L, now).values
                    .filter { it.lastTimeUsed > now-86400000L }.sortedByDescending { it.lastTimeUsed }
                    .map { stat ->
                        val label = runCatching { packageManager.getApplicationLabel(packageManager.getApplicationInfo(stat.packageName,0)).toString() }.getOrDefault(stat.packageName)
                        Triple(stat.packageName,label,"${stat.totalTimeInForeground/60000} мин · ${SimpleDateFormat("HH:mm",Locale.getDefault()).format(Date(stat.lastTimeUsed))}")
                    }
            }
            runOnUiThread {
                if (isDestroyed || ticket != generation) return@runOnUiThread
                loading.text = if (result.isFailure) "Статистика недоступна: ${result.exceptionOrNull()?.localizedMessage}" else "Последний запуск · время на экране"
                result.getOrNull()?.forEach { (pkg,label,detail) ->
                    text("$label\n$detail\n$pkg",15).setOnClickListener {
                        startActivity(Intent(Settings.ACTION_APPLICATION_DETAILS_SETTINGS,Uri.parse("package:$pkg")))
                    }
                }
            }
        }
    }
    private fun showProcesses() {
        header("Запущенные процессы")
        text("Снимок ps с компьютера через USB. Это не постоянное наблюдение. Для свежих данных запустите scripts/refresh-processes.ps1 на ПК.",14,muted)
        button("Прочитать обновлённый снимок") { showProcesses() }
        val file = java.io.File(filesDir,"processes.txt")
        text(if(file.exists()) file.readText() else "Снимка пока нет. Подключите USB и запустите скрипт обновления.",12).apply {
            typeface = android.graphics.Typeface.MONOSPACE
            setTextIsSelectable(true)
        }
        button("Системные службы: управление вручную") {
            runCatching { startActivity(Intent(Settings.ACTION_APPLICATION_DEVELOPMENT_SETTINGS)) }
                .onFailure { startActivity(Intent(Settings.ACTION_SETTINGS)) }
        }
    }
}
