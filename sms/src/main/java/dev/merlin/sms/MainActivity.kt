package dev.merlin.sms

import android.Manifest
import android.app.*
import android.app.role.RoleManager
import android.content.*
import android.content.pm.PackageManager
import android.net.Uri
import android.os.*
import android.provider.Telephony
import android.telephony.SmsManager
import android.widget.EditText
import java.util.concurrent.Executors

open class MainActivity : MerlinActivity() {
    private val worker=Executors.newSingleThreadExecutor()
    override fun onCreate(state:Bundle?){super.onCreate(state);render()}
    override fun onResume(){super.onResume();render()}
    override fun onDestroy(){worker.shutdownNow();super.onDestroy()}
    private fun render(){
        screen("SMS","Текстовые SMS. MMS и RCS пока не поддерживаются. Отправка оплачивается по тарифу оператора.")
        button("Написать SMS"){compose()}
        val isDefault=Telephony.Sms.getDefaultSmsPackage(this)==packageName
        if(!isDefault) button("Выбрать Merlin приложением SMS"){
            AlertDialog.Builder(this).setTitle("Только текстовые SMS")
                .setMessage("После выбора Merlin будет принимать SMS. MMS и RCS в этой версии недоступны. Можно вернуться к Google Messages через системные настройки приложений.")
                .setNegativeButton("Отмена",null).setPositiveButton("Продолжить"){_,_->
                    if(Build.VERSION.SDK_INT>=29) startActivityForResult(getSystemService(RoleManager::class.java).createRequestRoleIntent(RoleManager.ROLE_SMS),10)
                    else startActivity(Intent(Telephony.Sms.Intents.ACTION_CHANGE_DEFAULT).putExtra(Telephony.Sms.Intents.EXTRA_PACKAGE_NAME,packageName))
                }.show()
        }
        if(checkSelfPermission(Manifest.permission.READ_SMS)!=PackageManager.PERMISSION_GRANTED){
            button("Разрешить чтение SMS"){
                if(!isDefault)message("Сначала выберите приложение SMS")
                else requestPermissions(arrayOf(Manifest.permission.READ_SMS,Manifest.permission.RECEIVE_SMS,Manifest.permission.SEND_SMS),11)
            };return
        }
        button("Обновить входящие"){render()}
        val rows=android.widget.LinearLayout(this).apply{orientation=1}
        page.addView(rows)
        worker.execute {
            val messages=runCatching {
                val result=mutableListOf<Triple<String,String,String>>()
                contentResolver.query(Telephony.Sms.CONTENT_URI,arrayOf("address","body","date","type"),null,null,"date DESC")?.use{c->
                    while(c.moveToNext() && result.size<200){
                        val address=c.getString(0).orEmpty()
                        val kind=when(c.getInt(3)){1->"Входящее";2->"Отправлено";4->"Отправляется";5->"Ошибка отправки";else->"SMS"}
                        result.add(Triple(address,c.getString(1).orEmpty(),"$kind · ${java.text.DateFormat.getDateTimeInstance().format(java.util.Date(c.getLong(2)))}"))
                    }
                };result
            }
            runOnUiThread{
                if(isDestroyed || rows.parent==null)return@runOnUiThread
                messages.onSuccess{list->
                    if(list.isEmpty()) rows.addView(android.widget.TextView(this).apply{text="Сообщений пока нет";setTextColor(ink)})
                    list.forEach{(address,body,date)->rows.addView(android.widget.TextView(this).apply{
                        text="$address\n$body\n$date";setTextColor(ink);textSize=16f;setPadding(0,dp(14),0,dp(14))
                        setOnClickListener{compose(address)}
                    })}
                }.onFailure{message("Чтение SMS недоступно: ${it.localizedMessage}")}
            }
        }
        if(intent.data!=null){val address=intent.data?.schemeSpecificPart.orEmpty();intent.data=null;compose(address,intent.getStringExtra("sms_body").orEmpty())}
    }
    private fun compose(address:String="",body:String=""){
        val box=android.widget.LinearLayout(this).apply{orientation=1;setPadding(dp(20),0,dp(20),0)}
        val to=EditText(this).apply{hint="Номер";inputType=android.text.InputType.TYPE_CLASS_PHONE;setText(address)}
        val content=EditText(this).apply{hint="Сообщение";minLines=3;setText(body)}
        box.addView(to);box.addView(content)
        val dialog=AlertDialog.Builder(this).setTitle("Новое SMS").setView(box).setNegativeButton("Отмена",null).setPositiveButton("Далее",null).create()
        dialog.setOnShowListener{dialog.getButton(AlertDialog.BUTTON_POSITIVE).setOnClickListener{
            val target=to.text.toString().trim();val value=content.text.toString()
            if(target.isEmpty() || value.isBlank()){message("Введите номер и текст");return@setOnClickListener}
            if(Telephony.Sms.getDefaultSmsPackage(this)!=packageName){message("Для отправки выберите Merlin приложением SMS");return@setOnClickListener}
            if(checkSelfPermission(Manifest.permission.SEND_SMS)!=PackageManager.PERMISSION_GRANTED){requestPermissions(arrayOf(Manifest.permission.SEND_SMS),12);return@setOnClickListener}
            val manager=SmsManager.getDefault()
            val parts=manager.divideMessage(value)
            AlertDialog.Builder(this).setTitle("Отправить на $target?")
                .setMessage("Количество частей: ${parts.size}. Тариф оператора применяется к каждой части. Используется SIM для SMS по умолчанию.")
                .setNegativeButton("Отмена",null).setPositiveButton("Отправить"){_,_->
                    runCatching{
                        val values=ContentValues().apply{put("address",target);put("body",value);put("date",System.currentTimeMillis());put("type",4);put("read",1)}
                        val uri=contentResolver.insert(Telephony.Sms.CONTENT_URI,values) ?: error("Не удалось сохранить SMS")
                        val id=ContentUris.parseId(uri)
                        val pending=ArrayList<PendingIntent>()
                        parts.indices.forEach{i->pending.add(PendingIntent.getBroadcast(this,(id*100+i).toInt(),Intent(this,SentReceiver::class.java).setData(uri).putExtra("last",i==parts.lastIndex),PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE))}
                        manager.sendMultipartTextMessage(target,null,parts,pending,null)
                        message("Передано оператору. Статус обновится после отправки.");dialog.dismiss()
                    }.onFailure{message("SMS не отправлено: ${it.localizedMessage}")}
                }.show()
        }}
        dialog.show()
    }
}
class ComposeActivity:MainActivity()
class SmsReceiver:BroadcastReceiver(){
    override fun onReceive(context:Context,intent:Intent){
        val pending=goAsync()
        Thread{
            try{
                val parts=Telephony.Sms.Intents.getMessagesFromIntent(intent)
                if(parts.isNotEmpty()){
                    val values=ContentValues().apply{
                        put("address",parts[0].originatingAddress);put("body",parts.joinToString(""){it.messageBody.orEmpty()})
                        put("date",System.currentTimeMillis());put("date_sent",parts[0].timestampMillis);put("read",0);put("type",1)
                        put("sub_id",intent.getIntExtra("subscription",-1))
                    }
                    context.contentResolver.insert(Telephony.Sms.Inbox.CONTENT_URI,values)
                    val nm=context.getSystemService(NotificationManager::class.java)
                    nm.createNotificationChannel(NotificationChannel("sms","Новые SMS",NotificationManager.IMPORTANCE_HIGH))
                    val pi=PendingIntent.getActivity(context,0,Intent(context,MainActivity::class.java),PendingIntent.FLAG_IMMUTABLE or PendingIntent.FLAG_UPDATE_CURRENT)
                    nm.notify(1,Notification.Builder(context,"sms").setSmallIcon(android.R.drawable.sym_action_email).setContentTitle("Новое SMS")
                        .setContentText("Откройте Merlin SMS для чтения").setVisibility(Notification.VISIBILITY_PRIVATE).setContentIntent(pi).setAutoCancel(true).build())
                }
            }finally{pending.finish()}
        }.start()
    }
}
class SentReceiver:BroadcastReceiver(){
    override fun onReceive(context:Context,intent:Intent){
        val uri=intent.data ?: return
        // Any failed part marks the whole message failed; success never overwrites failure.
        if(resultCode!=Activity.RESULT_OK){context.contentResolver.update(uri,ContentValues().apply{put("type",5)},null,null)}
        else if(intent.getBooleanExtra("last",false)) context.contentResolver.update(uri,ContentValues().apply{put("type",2)},"type != ?",arrayOf("5"))
    }
}
class MmsReceiver:BroadcastReceiver(){
    override fun onReceive(context:Context,intent:Intent){
        val dir=java.io.File(context.filesDir,"pending-mms").apply{mkdirs()}
        intent.getByteArrayExtra("data")?.let{java.io.File(dir,"${System.currentTimeMillis()}.pdu").writeBytes(it)}
        val nm=context.getSystemService(NotificationManager::class.java)
        nm.createNotificationChannel(NotificationChannel("sms","Новые SMS",NotificationManager.IMPORTANCE_HIGH))
        nm.notify(2,Notification.Builder(context,"sms").setSmallIcon(android.R.drawable.sym_action_email).setContentTitle("Получено уведомление MMS")
            .setContentText("Merlin не загружает MMS. Для MMS вернитесь к Google Messages.").build())
    }
}
class RespondService:Service(){
    override fun onBind(intent:Intent?) : IBinder? = null
    override fun onStartCommand(intent:Intent?,flags:Int,id:Int):Int{
        // Open the editor for explicit confirmation; never send automatically.
        startActivity(Intent(this,ComposeActivity::class.java).setData(intent?.data).putExtra("sms_body",intent?.getStringExtra(Intent.EXTRA_TEXT)).addFlags(Intent.FLAG_ACTIVITY_NEW_TASK))
        stopSelf();return START_NOT_STICKY
    }
}
