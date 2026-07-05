param(
    [string]$RouterHost = "192.168.10.52",
    [string]$RouterUser = "root",
    [int]$RouterPort = 22,
    [string]$TargetHost = "192.168.10.80",
    [string]$Interface = "br-lan",
    [string[]]$EthernetInterfaces = @(),
    [string]$RemoteDir = "/tmp/re450_monitor",
    [string]$CaptureDir = "captures",
    [string]$StateFile = "captures/re450_monitor_state.json",
    [int]$RingFiles = 120,
    [int]$RotateSeconds = 30,
    [ValidateRange(1, 3600)]
    [int]$NeighborSampleSeconds = 2,
    [ValidateRange(1, 3600)]
    [int]$EthernetSampleSeconds = 5,
    [ValidateRange(1, 3600)]
    [int]$PingIntervalSeconds = 1,
    [switch]$ShowRemoteScript,
    [switch]$DisablePingProbe
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

New-Item -ItemType Directory -Path $CaptureDir -Force | Out-Null

if (Test-Path $StateFile) {
    throw "RE450 monitor state file already exists: $StateFile. Stop it first with tools/stop_re450_monitor.ps1."
}

$sshPath = Get-RequiredCommandPath -Name "ssh"
$filter = "arp or icmp or host $TargetHost"
$ethernetInterfaceCsv = (($EthernetInterfaces | Where-Object { $_ -and $_.Trim().Length -gt 0 } | ForEach-Object { $_.Trim() }) -join ",")

$processSpecs = @(
    @{
        Name = "tcpdump"
        Command = ('tcpdump -i "{0}" -n -s 0 -U -G {1} -W {2} -w "{3}/re450_l2_%Y%m%d_%H%M%S.pcap" "{4}"' -f $Interface, $RotateSeconds, $RingFiles, $RemoteDir, $filter)
    },
    @{
        Name = "ip_monitor"
        Command = ('BRIDGE_IF="{0}"; TARGET_HOST="{1}"; REMOTE_DIR="{2}"; SAMPLE_SECS="{3}"; while true; do TS=$(date "+%Y-%m-%dT%H:%M:%S%z"); echo "=== $TS ==="; ip neigh show to $TARGET_HOST dev $BRIDGE_IF 2>/dev/null || ip neigh show dev $BRIDGE_IF 2>/dev/null || ip neigh show 2>/dev/null || true; ip route show 2>/dev/null || true; echo; sleep $SAMPLE_SECS; done > "$REMOTE_DIR/ip_monitor.log" 2>&1' -f $Interface, $TargetHost, $RemoteDir, $NeighborSampleSeconds)
    },
    @{
        Name = "logread"
        Command = ('logread -f > "{0}/logread.log" 2>&1' -f $RemoteDir)
    },
    @{
        Name = "ubus"
        Command = ('ubus listen > "{0}/ubus_listen.jsonl" 2>&1' -f $RemoteDir)
    },
    @{
        Name = "eth_sampler"
        Command = ('BRIDGE_IF="{0}"; REMOTE_DIR="{1}"; SAMPLE_SECS="{2}"; if [ -n "{3}" ]; then IFACES=$(printf %s "{3}" | tr , " " ); elif [ -d /sys/class/net/$BRIDGE_IF/brif ]; then IFACES=$(ls /sys/class/net/$BRIDGE_IF/brif 2>/dev/null); else IFACES=$BRIDGE_IF; fi; while true; do TS=$(date "+%Y-%m-%dT%H:%M:%S%z"); echo "=== $TS ==="; for IFACE in $IFACES; do [ -d /sys/class/net/$IFACE ] || continue; CARRIER=$(cat /sys/class/net/$IFACE/carrier 2>/dev/null || echo n/a); OPERSTATE=$(cat /sys/class/net/$IFACE/operstate 2>/dev/null || echo n/a); RX_BYTES=$(cat /sys/class/net/$IFACE/statistics/rx_bytes 2>/dev/null || echo n/a); TX_BYTES=$(cat /sys/class/net/$IFACE/statistics/tx_bytes 2>/dev/null || echo n/a); RX_ERRORS=$(cat /sys/class/net/$IFACE/statistics/rx_errors 2>/dev/null || echo n/a); TX_ERRORS=$(cat /sys/class/net/$IFACE/statistics/tx_errors 2>/dev/null || echo n/a); RX_DROPPED=$(cat /sys/class/net/$IFACE/statistics/rx_dropped 2>/dev/null || echo n/a); TX_DROPPED=$(cat /sys/class/net/$IFACE/statistics/tx_dropped 2>/dev/null || echo n/a); echo "iface=$IFACE carrier=$CARRIER operstate=$OPERSTATE rx_bytes=$RX_BYTES tx_bytes=$TX_BYTES rx_errors=$RX_ERRORS tx_errors=$TX_ERRORS rx_dropped=$RX_DROPPED tx_dropped=$TX_DROPPED"; done; echo; sleep $SAMPLE_SECS; done > "$REMOTE_DIR/ethernet_ports.log" 2>&1' -f $Interface, $RemoteDir, $EthernetSampleSeconds, $ethernetInterfaceCsv)
    }
)

if (-not $DisablePingProbe) {
    $processSpecs += @{
        Name = "ping_probe"
        Command = ('TARGET_HOST="{0}"; REMOTE_DIR="{1}"; SAMPLE_SECS="{2}"; while true; do date "+%Y-%m-%dT%H:%M:%S%z"; ping -c 1 -W 1 $TARGET_HOST; echo; sleep $SAMPLE_SECS; done > "$REMOTE_DIR/ping_probe.log" 2>&1' -f $TargetHost, $RemoteDir, $PingIntervalSeconds)
    }
}

$processLines = $processSpecs | ForEach-Object {
    "( $($_.Command) ) >/dev/null 2>&1 & echo `"$($_.Name):`$!`""
}

$processSection = $processLines -join "`n"

$remoteScript = @"
set -eu

for cmd in tcpdump ip logread ubus; do
  command -v "`$cmd" >/dev/null 2>&1 || { echo "ERROR:missing-command:`$cmd"; exit 20; }
done

mkdir -p "$RemoteDir"
rm -f "$RemoteDir"/re450_l2_*.pcap "$RemoteDir"/*.log "$RemoteDir"/*.txt "$RemoteDir"/*.jsonl 2>/dev/null || true

{
  date
  echo
  uname -a
  echo
    ip link show 2>&1
  echo
  ip address show 2>&1
  echo
  ip route show 2>&1
  echo
  ip neigh show 2>&1
  echo
  bridge link show 2>&1 || true
  echo
  bridge vlan show 2>&1 || true
    echo
    ls "/sys/class/net/$Interface/brif" 2>&1 || true
} > "$RemoteDir/initial_state.txt" 2>&1

$processSection
"@

$remoteScript = $remoteScript -replace "`r`n", "`n"

if ($ShowRemoteScript) {
    Write-Output $remoteScript
    return
}

$output = ($remoteScript | & $sshPath @sshOptions "-T" "-p" "$RouterPort" "$RouterUser@$RouterHost" "sh") 2>&1

if ($LASTEXITCODE -ne 0) {
    throw "Failed to start RE450 monitor on $RouterHost. ssh exit code: $LASTEXITCODE`n$($output -join "`n")"
}

if ($output -match "^ERROR:") {
    throw ($output -join "`n")
}

$processes = @()
foreach ($line in $output) {
    if ($line -match "^(?<name>[a-z_]+):(?<pid>\d+)$") {
        $processes += [pscustomobject]@{
            name = $matches.name
            pid = [int]$matches.pid
        }
    }
}

if (-not ($processes | Where-Object { $_.name -eq "tcpdump" })) {
    throw "RE450 monitor did not return a tcpdump PID. Output:`n$($output -join "`n")"
}

$state = [pscustomobject]@{
    routerHost = $RouterHost
    routerUser = $RouterUser
    routerPort = $RouterPort
    targetHost = $TargetHost
    interface = $Interface
    ethernetInterfaces = @($EthernetInterfaces)
    remoteDir = $RemoteDir
    captureDir = $CaptureDir
    stateFile = $StateFile
    startedAt = (Get-Date).ToString("o")
    ringFiles = $RingFiles
    rotateSeconds = $RotateSeconds
    neighborSampleSeconds = $NeighborSampleSeconds
    ethernetSampleSeconds = $EthernetSampleSeconds
    pingIntervalSeconds = $PingIntervalSeconds
    bpfFilter = $filter
    pingProbeEnabled = (-not $DisablePingProbe)
    processes = $processes
}

$state | ConvertTo-Json -Depth 5 | Set-Content -Path $StateFile -Encoding UTF8

Write-Host "Started RE450 L1/L2 monitor"
Write-Host "  Router:    $RouterUser@$RouterHost`:$RouterPort"
Write-Host "  Bridge:    $Interface"
if ($EthernetInterfaces.Count -gt 0) {
    Write-Host "  Ethernet:  $($EthernetInterfaces -join ', ')"
} else {
    Write-Host "  Ethernet:  auto-detect bridge member ports"
}
Write-Host "  Filter:    $filter"
Write-Host "  RemoteDir: $RemoteDir"
Write-Host "  Sample(s): neigh=$NeighborSampleSeconds eth=$EthernetSampleSeconds ping=$PingIntervalSeconds"
Write-Host "  Processes:"
$processes | ForEach-Object {
    Write-Host ("    {0}: PID {1}" -f $_.name, $_.pid)
}
Write-Host "State file: $StateFile"