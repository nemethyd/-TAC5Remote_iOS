param(
    [string]$TargetHost = "192.168.10.80",
    [int]$Port = 502,
    [string]$Interface = "",
    [string]$CaptureDir = "captures",
    [int]$RingFiles = 24,
    [int]$RingDurationSec = 300,
    [string]$StateFile = "captures/modbus_monitor_state.json"
)

$ErrorActionPreference = "Stop"

function Get-TSharkPath {
    $cmd = Get-Command tshark -ErrorAction SilentlyContinue
    if (-not $cmd) {
        throw "tshark was not found in PATH. Install Wireshark/tshark first."
    }
    return $cmd.Source
}

function Resolve-Interface([string]$Preferred) {
    if ($Preferred -and $Preferred.Trim().Length -gt 0) {
        return $Preferred.Trim()
    }

    $list = & tshark -D 2>$null
    if (-not $list) {
        throw "Could not list interfaces with 'tshark -D'."
    }

    $best = $list | Where-Object { $_ -match "Ethernet|Wi-?Fi|wlan|eth" } | Select-Object -First 1
    if (-not $best) {
        $best = $list | Select-Object -First 1
    }
    if (-not $best) {
        throw "No capture interface found."
    }

    if ($best -match "^(\d+)\.") {
        return $matches[1]
    }

    return $best
}

New-Item -ItemType Directory -Path $CaptureDir -Force | Out-Null

if (Test-Path $StateFile) {
    $existing = Get-Content $StateFile -Raw | ConvertFrom-Json
    if ($existing -and $existing.pid) {
        $proc = Get-Process -Id $existing.pid -ErrorAction SilentlyContinue
        if ($proc) {
            throw "Monitor already running (PID=$($existing.pid)). Stop it first with tools/stop_modbus_monitor.ps1."
        }
    }
}

$tsharkPath = Get-TSharkPath
$iface = Resolve-Interface -Preferred $Interface
$filter = "host $TargetHost and tcp port $Port"
$outFile = Join-Path $CaptureDir "modbus_watch.pcapng"

$args = @(
    "-i", $iface,
    "-n",
    "-f", $filter,
    "-b", "files:$RingFiles",
    "-b", "duration:$RingDurationSec",
    "-w", $outFile
)

$proc = Start-Process -FilePath $tsharkPath -ArgumentList $args -PassThru -WindowStyle Hidden

$state = [pscustomobject]@{
    pid = $proc.Id
    startedAt = (Get-Date).ToString("o")
    host = $TargetHost
    port = $Port
    interface = $iface
    ringFiles = $RingFiles
    ringDurationSec = $RingDurationSec
    outputBase = $outFile
    bpfFilter = $filter
}

$state | ConvertTo-Json | Set-Content -Path $StateFile -Encoding UTF8

Write-Host "Started Modbus monitor"
Write-Host "  PID:      $($proc.Id)"
Write-Host "  Interface:$iface"
Write-Host "  Filter:   $filter"
Write-Host "  Output:   $outFile (ring buffer: $RingFiles files x $RingDurationSec sec)"
Write-Host "State file: $StateFile"
