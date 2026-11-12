param([string]$Adb = 'C:\platform-tools\adb.exe', [string]$Serial = '')
$ErrorActionPreference = 'Stop'
$arguments = @()
if ($Serial) { $arguments = @('-s', $Serial) }
$content = @("Снимок процессов: $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')", 'PID / PPID / RSS (КБ) / имя; снимок обновляется только этим скриптом.', '')
$content += & $Adb @arguments shell ps -A -o PID,PPID,RSS,NAME
if ($LASTEXITCODE -ne 0) { throw 'Не удалось получить процессы. Проверьте USB-отладку.' }
$temp = Join-Path ([IO.Path]::GetTempPath()) ('merlin-processes-' + [guid]::NewGuid().ToString() + '.txt')
try {
    [IO.File]::WriteAllLines($temp, $content, [Text.UTF8Encoding]::new($false))
    & $Adb @arguments push $temp /data/local/tmp/merlin-processes.txt
    & $Adb @arguments shell run-as dev.merlin.monitor mkdir -p files
    & $Adb @arguments shell run-as dev.merlin.monitor cp /data/local/tmp/merlin-processes.txt files/processes.txt
    if ($LASTEXITCODE -ne 0) { throw 'Не удалось обновить снимок в Merlin Диспетчер.' }
    Write-Output 'Снимок обновлён. Откройте Merlin Диспетчер → Процессы.'
} finally {
    Remove-Item -LiteralPath $temp -ErrorAction SilentlyContinue
}
