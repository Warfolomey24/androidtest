param([string]$Apk = "app\build\outputs\apk\debug\app-debug.apk")
$adb = "C:\platform-tools\adb.exe"
if (!(Test-Path $adb)) { throw "ADB not found at $adb" }
if (!(Test-Path $Apk)) { throw "APK not found at $Apk" }
& $adb devices
& $adb install -r $Apk
Write-Host 'Installed. On the phone: Settings -> Apps -> Default apps -> Launcher.'
Write-Host 'Do NOT disable com.miui.home.'
