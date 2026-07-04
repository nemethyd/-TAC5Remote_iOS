param(
    [string]$StateFile = "captures/modbus_monitor_state.json"
)

$ErrorActionPreference = "Stop"

if (-not (Test-Path $StateFile)) {
    throw "State file not found: $StateFile"
}

$state = Get-Content $StateFile -Raw | ConvertFrom-Json
if (-not $state.pid) {
    throw "State file does not contain a PID."
}

$proc = Get-Process -Id $state.pid -ErrorAction SilentlyContinue
if ($proc) {
    Stop-Process -Id $state.pid -Force
    Write-Host "Stopped monitor process PID=$($state.pid)"
} else {
    Write-Host "Monitor process PID=$($state.pid) was not running."
}

$dir = Split-Path -Parent $state.outputBase
$base = [System.IO.Path]::GetFileNameWithoutExtension($state.outputBase)
$captures = Get-ChildItem -Path $dir -Filter "$base*.pcapng" -ErrorAction SilentlyContinue |
    Sort-Object LastWriteTime -Descending |
    Select-Object -First 10

if ($captures) {
    Write-Host "Latest capture files:"
    $captures | ForEach-Object {
        Write-Host ("  {0}  {1} KB" -f $_.FullName, [int]($_.Length / 1KB))
    }
}

Remove-Item $StateFile -Force
Write-Host "Removed state file: $StateFile"
