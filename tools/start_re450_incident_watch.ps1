param(
    [string]$RouterHost = "192.168.10.52",
    [string]$RouterUser = "root",
    [int]$RouterPort = 22,
    [string]$TargetHost = "192.168.10.80",
    [string]$Interface = "br-lan",
    [string]$IncidentRoot = "captures/re450_incidents",
    [string]$IncidentMarkersFile = "captures/incident_markers.log",
    [ValidateRange(1, 60)]
    [int]$ProbeIntervalSeconds = 2,
    [ValidateRange(1, 20)]
    [int]$FailThreshold = 3,
    [ValidateRange(1, 20)]
    [int]$RecoverThreshold = 2,
    [ValidateRange(5, 120)]
    [int]$RemoteCaptureSeconds = 20,
    [string]$LogPullDir = "captures/re450_logs",
    [ValidateRange(60, 3600)]
    [int]$LogPullIntervalSeconds = 900,
    [switch]$DisableLogPull
)

$ErrorActionPreference = "Stop"

$sshOptions = @(
    "-o", "BatchMode=yes",
    "-o", "ConnectTimeout=5",
    "-o", "HostKeyAlgorithms=+ssh-rsa",
    "-o", "PubkeyAcceptedAlgorithms=+ssh-rsa"
)

function Get-RequiredCommandPath([string]$Name) {
    $command = Get-Command $Name -ErrorAction SilentlyContinue
    if (-not $command) {
        throw "$Name was not found in PATH. Install OpenSSH client tools first."
    }

    return $command.Source
}

function Initialize-IncidentMarkersFile([string]$Path) {
    $dir = Split-Path -Parent $Path
    if ($dir) {
        New-Item -ItemType Directory -Path $dir -Force | Out-Null
    }

    if (-not (Test-Path $Path)) {
        "timestamp,event,notes" | Set-Content -Path $Path -Encoding UTF8
    }
}

function Add-IncidentMarker([string]$Path, [string]$EventName, [string]$Notes) {
    $timestamp = (Get-Date).ToString("yyyy-MM-ddTHH:mm:sszzz")
    $safeNotes = $Notes.Replace(",", ";")
    Add-Content -Path $Path -Value "$timestamp,$EventName,$safeNotes"
}

function New-IncidentCapture(
    [string]$sshPath,
    [string]$scpPath,
    [string[]]$sshOpts,
    [string]$RouterHost,
    [string]$RouterUser,
    [int]$RouterPort,
    [string]$TargetHost,
    [string]$Interface,
    [int]$RemoteCaptureSeconds,
    [string]$IncidentRoot,
    [string]$IncidentMarkersFile
) {
    $stamp = Get-Date -Format "yyyyMMdd_HHmmss"
    $incidentDir = Join-Path $IncidentRoot "incident_$stamp"
    New-Item -ItemType Directory -Path $incidentDir -Force | Out-Null

    $pingPath = Join-Path $incidentDir "local_ping_to_target.txt"
    $arpPath = Join-Path $incidentDir "local_arp.txt"
    $remoteDiagPath = Join-Path $incidentDir "re450_diag.txt"

    "Timestamp: $((Get-Date).ToString("o"))" | Set-Content -Path $pingPath -Encoding UTF8
    Test-Connection -TargetName $TargetHost -Count 6 -ErrorAction SilentlyContinue |
        Format-Table -AutoSize |
        Out-String |
        Add-Content -Path $pingPath

    arp -a | Out-String | Set-Content -Path $arpPath -Encoding UTF8

    $remoteCaptureBase = "/tmp/re450_incident_$stamp"
    $remotePcap = "$remoteCaptureBase.pcap"

    $remoteScript = @"
set -eu

echo "TIME="
date

echo "=== link ==="
cat /sys/class/net/eth0/carrier 2>/dev/null || true
cat /sys/class/net/eth0/operstate 2>/dev/null || true
ip link show eth0 2>/dev/null || true
ip link show $Interface 2>/dev/null || true

echo "=== l3 ==="
ip -4 addr show 2>/dev/null || true
ip route show 2>/dev/null || true

echo "=== neigh ==="
ip neigh show dev $Interface nud all 2>/dev/null || ip neigh show dev $Interface 2>/dev/null || true

echo "=== ping target ==="
ping -c 4 -W 1 $TargetHost 2>/dev/null || true

echo "=== memory ==="
free 2>/dev/null || true

echo "=== disk ==="
df -h 2>/dev/null || true

echo "=== wireless uplink ==="
iwinfo wlan0 info 2>/dev/null || true
iwinfo wlan0 assoclist 2>/dev/null || true

echo "=== log tail ==="
logread | tail -n 500 2>/dev/null || true

echo "=== capture start ==="
rm -f "$remotePcap" 2>/dev/null || true
(tcpdump -ni $Interface -s 0 -U -w "$remotePcap" "arp or icmp or (host $TargetHost and tcp port 502) or (udp and (port 67 or 68))" >/dev/null 2>&1 &) 
TPID=$!
sleep $RemoteCaptureSeconds
kill "$TPID" 2>/dev/null || true
sync
ls -l "$remotePcap" 2>/dev/null || true
"@

    $remoteScript = $remoteScript -replace "`r`n", "`n"
    $diagOutput = ($remoteScript | & $sshPath @sshOpts "-T" "-p" "$RouterPort" "$RouterUser@$RouterHost" "sh") 2>&1

    $diagOutput -join "`n" | Set-Content -Path $remoteDiagPath -Encoding UTF8

    $remoteSpec = "{0}@{1}:{2}" -f $RouterUser, $RouterHost, $remotePcap
    & $scpPath "-O" @sshOpts "-P" "$RouterPort" $remoteSpec $incidentDir | Out-Null

    if ($LASTEXITCODE -ne 0) {
        Add-Content -Path $remoteDiagPath -Value "`n[WARN] Failed to download remote pcap from $remotePcap"
    }

    & $sshPath @sshOpts "-p" "$RouterPort" "$RouterUser@$RouterHost" "rm -f '$remotePcap'" | Out-Null

    Add-IncidentMarker -Path $IncidentMarkersFile -EventName "AUTO_INCIDENT_CAPTURE" -Notes "Triggered by ping loss to $TargetHost; artifacts in $incidentDir"

    Write-Host "[incident] captured -> $incidentDir"
}

function Invoke-RE450LogPullAndClear(
    [string]$sshPath,
    [string[]]$sshOpts,
    [string]$RouterHost,
    [string]$RouterUser,
    [int]$RouterPort,
    [string]$LogPullDir,
    [string]$IncidentMarkersFile
) {
    New-Item -ItemType Directory -Path $LogPullDir -Force | Out-Null
    $stamp = Get-Date -Format "yyyyMMdd_HHmmss"
    $logPath = Join-Path $LogPullDir "re450_log_$stamp.txt"

    # Single short-lived SSH session: pull the current log, then restart the log
    # daemon so its in-memory ring buffer is freed. This keeps our own monitoring's
    # footprint on this RAM/flash-constrained device as small as possible.
    $remoteScript = @"
logread
"@
    $output = ($remoteScript | & $sshPath @sshOpts "-T" "-p" "$RouterPort" "$RouterUser@$RouterHost" "sh") 2>&1
    $output -join "`n" | Set-Content -Path $logPath -Encoding UTF8

    & $sshPath @sshOpts "-p" "$RouterPort" "$RouterUser@$RouterHost" "/etc/init.d/log restart >/dev/null 2>&1 || true" | Out-Null

    Add-IncidentMarker -Path $IncidentMarkersFile -EventName "AUTO_LOG_PULL_CLEAR" -Notes "Pulled logread output to $logPath and restarted RE450 log daemon to free its ring buffer"
    Write-Host "[log-pull] saved $logPath and cleared RE450 log buffer"
}

$sshPath = Get-RequiredCommandPath -Name "ssh"
$scpPath = Get-RequiredCommandPath -Name "scp"

New-Item -ItemType Directory -Path $IncidentRoot -Force | Out-Null
Initialize-IncidentMarkersFile -Path $IncidentMarkersFile

Write-Host "Started RE450 incident watcher"
Write-Host "  Router:    $RouterUser@$RouterHost`:$RouterPort"
Write-Host "  Target:    $TargetHost"
Write-Host "  Interface: $Interface"
Write-Host "  Probe:     every $ProbeIntervalSeconds s; fail threshold $FailThreshold; recover threshold $RecoverThreshold"
Write-Host "  Capture:   $RemoteCaptureSeconds s remote pcap per incident"
Write-Host "  Output:    $IncidentRoot"
if (-not $DisableLogPull) {
    Write-Host "  Log pull:  every $LogPullIntervalSeconds s, saved to $LogPullDir, then RE450 log buffer cleared"
}
Write-Host "Press Ctrl+C to stop."

$failCount = 0
$successCount = 0
$inFailureState = $false
$lastLogPull = Get-Date

while ($true) {
    $reachable = Test-Connection -TargetName $TargetHost -Count 1 -Quiet -ErrorAction SilentlyContinue

    if ($reachable) {
        $successCount += 1
        $failCount = 0

        if ($inFailureState -and $successCount -ge $RecoverThreshold) {
            $inFailureState = $false
            $msg = "Connectivity recovered to $TargetHost after outage"
            Add-IncidentMarker -Path $IncidentMarkersFile -EventName "AUTO_RECOVERY" -Notes $msg
            Write-Host "[recover] $msg"
        }
    } else {
        $failCount += 1
        $successCount = 0

        if (-not $inFailureState -and $failCount -ge $FailThreshold) {
            $inFailureState = $true
            $msg = "Connectivity loss detected to $TargetHost after $failCount failed probes"
            Add-IncidentMarker -Path $IncidentMarkersFile -EventName "AUTO_OUTAGE" -Notes $msg
            Write-Host "[outage] $msg"

            try {
                New-IncidentCapture -sshPath $sshPath -scpPath $scpPath -sshOpts $sshOptions -RouterHost $RouterHost -RouterUser $RouterUser -RouterPort $RouterPort -TargetHost $TargetHost -Interface $Interface -RemoteCaptureSeconds $RemoteCaptureSeconds -IncidentRoot $IncidentRoot -IncidentMarkersFile $IncidentMarkersFile
            } catch {
                $err = $_.Exception.Message
                Add-IncidentMarker -Path $IncidentMarkersFile -EventName "AUTO_INCIDENT_CAPTURE_ERROR" -Notes $err
                Write-Warning "Incident capture failed: $err"
            }
        }
    }

    if (-not $DisableLogPull -and -not $inFailureState) {
        $sinceLastPull = (Get-Date) - $lastLogPull
        if ($sinceLastPull.TotalSeconds -ge $LogPullIntervalSeconds) {
            try {
                Invoke-RE450LogPullAndClear -sshPath $sshPath -sshOpts $sshOptions -RouterHost $RouterHost -RouterUser $RouterUser -RouterPort $RouterPort -LogPullDir $LogPullDir -IncidentMarkersFile $IncidentMarkersFile
            } catch {
                Write-Warning "Log pull/clear failed: $($_.Exception.Message)"
            }
            $lastLogPull = Get-Date
        }
    }

    Start-Sleep -Seconds $ProbeIntervalSeconds
}
