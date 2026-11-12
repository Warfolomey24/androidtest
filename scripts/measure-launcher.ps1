param(
    [ValidateSet('com.miui.home', 'dev.merlin.launcher')]
    [string]$Package = 'com.miui.home',
    [string]$Adb = 'C:\platform-tools\adb.exe'
)
$ErrorActionPreference = 'Stop'
if (!(Test-Path $Adb)) { throw "ADB not found: $Adb" }
$device = (& $Adb get-state 2>&1 | Out-String).Trim()
if ($device -ne 'device') { throw "Device must be connected and authorized; status: $device" }
$stamp = Get-Date -Format 'yyyy-MM-dd_HH-mm-ss'
$outputDir = Join-Path (Get-Location) 'measurements'
New-Item -ItemType Directory -Force -Path $outputDir | Out-Null
$safeName = $Package.Replace('.', '-')
$prefix = Join-Path $outputDir "$safeName-$stamp"
& $Adb shell dumpsys meminfo $Package | Out-File -FilePath "$prefix-meminfo.txt" -Encoding utf8
& $Adb shell dumpsys gfxinfo $Package framestats | Out-File -FilePath "$prefix-gfxinfo.txt" -Encoding utf8
& $Adb shell dumpsys activity activities | Out-File -FilePath "$prefix-activity.txt" -Encoding utf8
Write-Host "Saved diagnostics: $prefix-*.txt"
Write-Host 'Read only. Compare after a warm-up and with the same app setup.'
