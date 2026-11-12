package dev.merlin.camera

import android.Manifest
import android.content.ContentValues
import android.content.Intent
import android.content.pm.PackageManager
import android.hardware.Camera
import android.os.Bundle
import android.provider.MediaStore
import android.view.*
import android.widget.*
import java.text.SimpleDateFormat
import java.util.*
import java.util.concurrent.Executors

@Suppress("DEPRECATION")
class MainActivity:MerlinActivity(),SurfaceHolder.Callback{
    private var camera:Camera?=null
    private lateinit var preview:SurfaceView
    private var cameraId=0
    private var capturing=false
    private var flash=false
    private val writer=Executors.newSingleThreadExecutor()
    private var lastPhoto:android.net.Uri?=null
    override fun onCreate(state:Bundle?){
        super.onCreate(state)
        screen("Камера","Фото без рекламы. Снимки сохраняются в DCIM/Merlin. Видео пока не поддерживается.")
        preview=SurfaceView(this)
        page.addView(preview,LinearLayout.LayoutParams(-1,dp(360)))
        preview.holder.addCallback(this)
        button("Снять фото"){capture()}
        button("Передняя / задняя камера"){
            if(capturing)return@button
            if(Camera.getNumberOfCameras()>1){release();cameraId=(cameraId+1)%Camera.getNumberOfCameras();open()}
        }
        button("Вспышка: вкл / выкл"){
            flash=!flash
            runCatching{camera?.let{val p=it.parameters;val mode=if(flash)Camera.Parameters.FLASH_MODE_ON else Camera.Parameters.FLASH_MODE_OFF
                if(p.supportedFlashModes?.contains(mode)==true){p.flashMode=mode;it.parameters=p}else{flash=false;message("Вспышка недоступна")}}}
        }
        button("Последнее фото"){
            lastPhoto?.let{uri->runCatching{startActivity(Intent(Intent.ACTION_VIEW).setDataAndType(uri,"image/jpeg").addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION))}.onFailure{message("Нет приложения для просмотра")}}
                ?:message("Сначала сделайте фото")
        }
        if(checkSelfPermission(Manifest.permission.CAMERA)!=PackageManager.PERMISSION_GRANTED)requestPermissions(arrayOf(Manifest.permission.CAMERA),1)
    }
    override fun onResume(){super.onResume();if(::preview.isInitialized && preview.holder.surface.isValid)open()}
    override fun onPause(){release();super.onPause()}
    override fun onDestroy(){writer.shutdown();super.onDestroy()}
    override fun onRequestPermissionsResult(code:Int,permissions:Array<out String>,results:IntArray){super.onRequestPermissionsResult(code,permissions,results);if(code==1 && results.firstOrNull()==PackageManager.PERMISSION_GRANTED)open()}
    override fun surfaceCreated(holder:SurfaceHolder){open()}
    override fun surfaceChanged(holder:SurfaceHolder,format:Int,width:Int,height:Int){if(camera!=null){release();open()}}
    override fun surfaceDestroyed(holder:SurfaceHolder){release()}
    private fun release(){runCatching{camera?.stopPreview();camera?.release()};camera=null;capturing=false}
    private fun open(){
        if(camera!=null || !preview.holder.surface.isValid || checkSelfPermission(Manifest.permission.CAMERA)!=PackageManager.PERMISSION_GRANTED)return
        runCatching{
            val c=Camera.open(cameraId);camera=c
            val p=c.parameters
            val photo=p.supportedPictureSizes.filter{it.width.toLong()*it.height<=16000000L}.maxByOrNull{it.width.toLong()*it.height}
                ?:p.supportedPictureSizes.minByOrNull{it.width.toLong()*it.height}
            photo?.let{p.setPictureSize(it.width,it.height)}
            val ratio=photo?.let{it.width.toFloat()/it.height} ?: (4f/3f)
            p.supportedPreviewSizes.filter{it.width<=1920}.minByOrNull{kotlin.math.abs(it.width.toFloat()/it.height-ratio)*10000+kotlin.math.abs(it.width-1280)}?.let{p.setPreviewSize(it.width,it.height)}
            if(p.supportedFocusModes?.contains(Camera.Parameters.FOCUS_MODE_CONTINUOUS_PICTURE)==true)p.focusMode=Camera.Parameters.FOCUS_MODE_CONTINUOUS_PICTURE
            val info=Camera.CameraInfo();Camera.getCameraInfo(cameraId,info)
            val degrees=when(windowManager.defaultDisplay.rotation){Surface.ROTATION_90->90;Surface.ROTATION_180->180;Surface.ROTATION_270->270;else->0}
            val display=if(info.facing==Camera.CameraInfo.CAMERA_FACING_FRONT)(360-(info.orientation+degrees)%360)%360 else (info.orientation-degrees+360)%360
            p.setRotation(if(info.facing==Camera.CameraInfo.CAMERA_FACING_FRONT)(info.orientation-degrees+360)%360 else (info.orientation+degrees)%360)
            c.parameters=p;c.setDisplayOrientation(display);c.setPreviewDisplay(preview.holder);c.startPreview()
            val size=p.previewSize
            preview.post{
                val w=preview.width
                if(w>0)preview.layoutParams=preview.layoutParams.apply{height=if(display==90 || display==270)w*size.width/size.height else w*size.height/size.width}
            }
        }.onFailure{release();message("Камера недоступна: ${it.localizedMessage}")}
    }
    private fun capture(){
        val c=camera ?: run{message("Разрешите доступ к камере");return}
        if(capturing)return
        capturing=true
        runCatching{c.takePicture(null,null){bytes,device->
            runCatching{device.startPreview()};capturing=false
            writer.execute{
                var uri:android.net.Uri?=null
                runCatching{
                    val values=ContentValues().apply{
                        put(MediaStore.Images.Media.DISPLAY_NAME,"Merlin_${SimpleDateFormat("yyyyMMdd_HHmmss_SSS",Locale.US).format(Date())}.jpg")
                        put(MediaStore.Images.Media.MIME_TYPE,"image/jpeg")
                        put(MediaStore.Images.Media.RELATIVE_PATH,"DCIM/Merlin")
                        put(MediaStore.Images.Media.IS_PENDING,1)
                    }
                    uri=contentResolver.insert(MediaStore.Images.Media.EXTERNAL_CONTENT_URI,values) ?: error("Не удалось создать файл")
                    contentResolver.openOutputStream(uri!!)?.use{it.write(bytes)} ?: error("Не удалось записать фото")
                    contentResolver.update(uri!!,ContentValues().apply{put(MediaStore.Images.Media.IS_PENDING,0)},null,null)
                    lastPhoto=uri
                }.onSuccess{runOnUiThread{message("Фото сохранено в DCIM/Merlin")}}
                    .onFailure{error->uri?.let{contentResolver.delete(it,null,null)};runOnUiThread{message("Ошибка сохранения: ${error.localizedMessage}")}}
            }
        }}.onFailure{capturing=false;message("Ошибка съёмки: ${it.localizedMessage}")}
    }
}
