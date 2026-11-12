package dev.merlin.phone

import android.app.*
import android.content.Intent
import android.os.Bundle
import android.telecom.*
import android.view.WindowManager

class CallService : InCallService() {
    private val callbacks=mutableMapOf<Call,Call.Callback>()
    override fun onCallAdded(call:Call) {
        super.onCallAdded(call)
        current=this
        activeCalls.add(call)
        val callback=object:Call.Callback(){ override fun onStateChanged(c:Call,state:Int){notifyCall()} }
        callbacks[call]=callback
        call.registerCallback(callback)
        notifyCall()
        startActivity(Intent(this,CallActivity::class.java).addFlags(Intent.FLAG_ACTIVITY_NEW_TASK))
    }
    override fun onCallRemoved(call:Call) {
        callbacks.remove(call)?.let{call.unregisterCallback(it)}
        activeCalls.remove(call)
        super.onCallRemoved(call)
        if(activeCalls.isEmpty()) { getSystemService(NotificationManager::class.java).cancel(1);current=null }
        else notifyCall()
        changed?.invoke()
    }
    private fun notifyCall() {
        val manager=getSystemService(NotificationManager::class.java)
        manager.createNotificationChannel(NotificationChannel("activeCalls","Звонки",NotificationManager.IMPORTANCE_HIGH))
        val pending=PendingIntent.getActivity(this,0,Intent(this,CallActivity::class.java),PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE)
        val ringing=activeCalls.any{it.state==Call.STATE_RINGING}
        val notification=Notification.Builder(this,"activeCalls").setSmallIcon(android.R.drawable.sym_action_call)
            .setContentTitle(if(ringing) "Входящий звонок" else "Звонок")
            .setContentText(activeCalls.lastOrNull()?.details?.handle?.schemeSpecificPart ?: "Неизвестный номер")
            .setCategory(Notification.CATEGORY_CALL).setOngoing(true).setContentIntent(pending)
        if(ringing) notification.setFullScreenIntent(pending,true)
        manager.notify(1,notification.build())
        changed?.invoke()
    }
    companion object {
        var current:CallService?=null
        val activeCalls=mutableListOf<Call>()
        var changed:(()->Unit)?=null
    }
}
class CallActivity : MerlinActivity() {
    override fun onCreate(state:Bundle?) {
        super.onCreate(state)
        setShowWhenLocked(true); setTurnScreenOn(true)
        window.addFlags(WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON)
    }
    override fun onResume(){super.onResume();CallService.changed={runOnUiThread{render()}};render()}
    override fun onPause(){CallService.changed=null;super.onPause()}
    private fun render(){
        val call=CallService.activeCalls.lastOrNull()
        if(call==null){finish();return}
        screen("Звонок",call.details.handle?.schemeSpecificPart ?: "Неизвестный номер")
        text(when(call.state){Call.STATE_RINGING->"Входящий";Call.STATE_ACTIVE->"Разговор";Call.STATE_HOLDING->"На удержании";Call.STATE_DISCONNECTED->"Завершён";else->"Соединение…"})
        if(call.state==Call.STATE_RINGING) button("Ответить"){call.answer(VideoProfile.STATE_AUDIO_ONLY)}
        button("Завершить / отклонить"){if(call.state==Call.STATE_RINGING)call.reject(false,null) else call.disconnect()}
        button("Микрофон: вкл / выкл") {
            CallService.current?.let{it.setMuted(!(it.callAudioState?.isMuted ?: false))}
        }
        button("Динамик / телефон") {
            CallService.current?.let{it.setAudioRoute(if(it.callAudioState?.route==CallAudioState.ROUTE_SPEAKER)CallAudioState.ROUTE_WIRED_OR_EARPIECE else CallAudioState.ROUTE_SPEAKER)}
        }
        if(call.state==Call.STATE_ACTIVE) button("Удержание"){call.hold()}
        if(call.state==Call.STATE_HOLDING) button("Продолжить"){call.unhold()}
        button("Клавиатура DTMF") {
            val keys=arrayOf("1","2","3","4","5","6","7","8","9","*","0","#")
            AlertDialog.Builder(this).setTitle("Тональный набор").setItems(keys){_,i->
                call.playDtmfTone(keys[i][0]);android.os.Handler(mainLooper).postDelayed({call.stopDtmfTone()},180)
            }.show()
        }
        if(call.state==Call.STATE_SELECT_PHONE_ACCOUNT){
            call.details.intentExtras?.getParcelableArrayList<PhoneAccountHandle>(TelecomManager.EXTRA_PHONE_ACCOUNT_HANDLES)?.forEachIndexed{i,handle->
                button("Использовать SIM ${i+1}"){call.phoneAccountSelected(handle,false)}
            }
        }
    }
}
