package dev.merlin.phone

import android.Manifest
import android.app.AlertDialog
import android.app.role.RoleManager
import android.content.Intent
import android.content.pm.PackageManager
import android.net.Uri
import android.os.Build
import android.os.Bundle
import android.provider.CallLog
import android.provider.ContactsContract
import android.telecom.TelecomManager
import android.widget.*
import java.util.concurrent.Executors

open class MainActivity : MerlinActivity() {
    private lateinit var number: EditText
    private val worker = Executors.newSingleThreadExecutor()
    override fun onCreate(state: Bundle?) {
        super.onCreate(state)
        screen("Звонки","Набор номера и контакты. Звонок начинается только после нажатия кнопки.")
        number = field("Номер телефона",android.text.InputType.TYPE_CLASS_PHONE)
        number.setText(intent.data?.schemeSpecificPart.orEmpty())
        listOf("123","456","789","*0#").forEach { digits ->
            val row = LinearLayout(this)
            page.addView(row)
            digits.forEach { digit ->
                val key = Button(this).apply { text=digit.toString(); textSize=27f; setOnClickListener { number.append(digit.toString()) } }
                if(digit=='0') key.setOnLongClickListener { number.append("+"); true }
                row.addView(key,LinearLayout.LayoutParams(0,dp(64),1f))
            }
        }
        button("⌫ Удалить цифру") { if(number.text.isNotEmpty()) number.text.delete(number.text.length-1,number.text.length) }
        button("Позвонить") { confirmCall() }
        button("Контакты") { contacts() }
        button("Журнал звонков") { history() }
        button("Сделать приложением звонков") {
            if(Build.VERSION.SDK_INT>=29) {
                val manager=getSystemService(RoleManager::class.java)
                startActivityForResult(manager.createRequestRoleIntent(RoleManager.ROLE_DIALER),10)
            } else startActivity(Intent(TelecomManager.ACTION_CHANGE_DEFAULT_DIALER).putExtra(TelecomManager.EXTRA_CHANGE_DEFAULT_DIALER_PACKAGE_NAME,packageName))
        }
    }
    override fun onDestroy(){ worker.shutdownNow(); super.onDestroy() }
    private fun confirmCall() {
        val digits=number.text.toString().trim()
        if(digits.isBlank()) { message("Введите номер"); return }
        AlertDialog.Builder(this).setTitle("Позвонить $digits?").setNegativeButton("Отмена",null).setPositiveButton("Позвонить") { _,_ ->
            if(checkSelfPermission(Manifest.permission.CALL_PHONE)!=PackageManager.PERMISSION_GRANTED) {
                requestPermissions(arrayOf(Manifest.permission.CALL_PHONE),11)
                message("После выдачи разрешения нажмите «Позвонить» ещё раз")
            } else runCatching {
                getSystemService(TelecomManager::class.java).placeCall(Uri.fromParts("tel",digits,null),Bundle())
            }.onFailure { message("Не удалось начать звонок: ${it.localizedMessage}") }
        }.show()
    }
    private fun contacts() {
        if(checkSelfPermission(Manifest.permission.READ_CONTACTS)!=PackageManager.PERMISSION_GRANTED) {
            requestPermissions(arrayOf(Manifest.permission.READ_CONTACTS),12); return
        }
        worker.execute {
            val items=runCatching {
                val out=mutableListOf<Pair<String,String>>()
                contentResolver.query(ContactsContract.CommonDataKinds.Phone.CONTENT_URI,arrayOf("display_name","data1"),null,null,"display_name COLLATE LOCALIZED ASC")?.use { c ->
                    while(c.moveToNext()) out.add(c.getString(0).orEmpty() to c.getString(1).orEmpty())
                }; out
            }
            runOnUiThread {
                if(isDestroyed) return@runOnUiThread
                val values=items.getOrNull() ?: run { message("Контакты недоступны"); return@runOnUiThread }
                if(values.isEmpty()) {message("Контактов нет"); return@runOnUiThread}
                val search=EditText(this).apply { hint="Поиск имени или номера" }
                val list=ListView(this)
                var shown=values
                fun filter(){ shown=values.filter { (it.first+it.second).contains(search.text.toString(),true) }; list.adapter=ArrayAdapter(this,android.R.layout.simple_list_item_1,shown.map { "${it.first}\n${it.second}" }) }
                search.addTextChangedListener(object:android.text.TextWatcher {
                    override fun beforeTextChanged(s:CharSequence?,st:Int,c:Int,a:Int){}
                    override fun onTextChanged(s:CharSequence?,st:Int,b:Int,c:Int){filter()}
                    override fun afterTextChanged(s:android.text.Editable?){}
                })
                val box=LinearLayout(this).apply {orientation=1;addView(search);addView(list,LinearLayout.LayoutParams(-1,dp(400)))}
                val dialog=AlertDialog.Builder(this).setTitle("Контакты").setView(box).setNegativeButton("Закрыть",null).create()
                list.setOnItemClickListener { _,_,pos,_ -> number.setText(shown[pos].second);dialog.dismiss() }
                filter();dialog.show()
            }
        }
    }
    private fun history() {
        if(checkSelfPermission(Manifest.permission.READ_CALL_LOG)!=PackageManager.PERMISSION_GRANTED) {
            requestPermissions(arrayOf(Manifest.permission.READ_CALL_LOG),13); message("Для журнала назначьте Merlin приложением звонков"); return
        }
        worker.execute {
            val result=runCatching {
                val list=mutableListOf<Pair<String,String>>()
                contentResolver.query(CallLog.Calls.CONTENT_URI,arrayOf("number","date","type"),null,null,"date DESC")?.use { c ->
                    while(c.moveToNext() && list.size<100) {
                        val n=c.getString(0).orEmpty()
                        val type=when(c.getInt(2)){1->"Входящий";2->"Исходящий";3->"Пропущен";else->"Звонок"}
                        list.add(n to "$n · $type\n${java.text.DateFormat.getDateTimeInstance().format(java.util.Date(c.getLong(1)))}")
                    }
                };list
            }
            runOnUiThread {
                if(isDestroyed) return@runOnUiThread
                val list=result.getOrNull() ?: run {message("Журнал недоступен");return@runOnUiThread}
                AlertDialog.Builder(this).setTitle("Журнал").setItems(list.map{it.second}.toTypedArray()){_,i->number.setText(list[i].first)}.setNegativeButton("Закрыть",null).show()
            }
        }
    }
}
class DialActivity : MainActivity()
