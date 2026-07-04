param(
    [string]$Capture = "",
    [string]$CaptureDir = "captures",
    [string]$Output = "captures/modbus_disconnect_review.txt"
)

$ErrorActionPreference = "Stop"

$cmd = Get-Command tshark -ErrorAction SilentlyContinue
if (-not $cmd) {
    throw "tshark was not found in PATH. Install Wireshark/tshark first."
}

if (-not $Capture) {
    $Capture = Get-ChildItem -Path $CaptureDir -Filter "modbus_watch*.pcapng" -ErrorAction SilentlyContinue |
        Sort-Object LastWriteTime -Descending |
        Select-Object -First 1 |
        ForEach-Object { $_.FullName }
}

if (-not $Capture -or -not (Test-Path $Capture)) {
    throw "No capture file found. Provide -Capture <path> or ensure modbus_watch*.pcapng exists."
}

$lines = New-Object System.Collections.Generic.List[string]
$lines.Add("Modbus disconnect review")
$lines.Add(("Generated: {0}" -f (Get-Date).ToString("o")))
$lines.Add(("Capture:   {0}" -f $Capture))
$lines.Add("")

$lines.Add("=== TCP connection events (SYN/FIN/RST) ===")
$tcpEvents = & tshark -r $Capture -Y "tcp.flags.syn==1 || tcp.flags.fin==1 || tcp.flags.reset==1" -T fields -E separator=, -e frame.time -e ip.src -e tcp.srcport -e ip.dst -e tcp.dstport -e tcp.flags 2>$null
if ($tcpEvents) { $tcpEvents | ForEach-Object { $lines.Add($_) } } else { $lines.Add("(none)") }
$lines.Add("")

$lines.Add("=== Modbus exceptions ===")
$modbusExc = & tshark -r $Capture -Y "modbus.exception_code" -T fields -E separator=, -e frame.time -e ip.src -e ip.dst -e modbus.func_code -e modbus.exception_code 2>$null
if ($modbusExc) { $modbusExc | ForEach-Object { $lines.Add($_) } } else { $lines.Add("(none)") }
$lines.Add("")

$lines.Add("=== TCP retransmission indicators ===")
$retrans = & tshark -r $Capture -Y "tcp.analysis.retransmission || tcp.analysis.lost_segment || tcp.analysis.duplicate_ack" -T fields -E separator=, -e frame.time -e ip.src -e tcp.srcport -e ip.dst -e tcp.dstport -e tcp.analysis.retransmission -e tcp.analysis.lost_segment -e tcp.analysis.duplicate_ack 2>$null
if ($retrans) { $retrans | ForEach-Object { $lines.Add($_) } } else { $lines.Add("(none)") }
$lines.Add("")

$lines.Add("=== Conversation summary ===")
$conv = & tshark -r $Capture -q -z conv,tcp 2>$null
if ($conv) { $conv | ForEach-Object { $lines.Add($_) } } else { $lines.Add("(none)") }

$lines | Set-Content -Path $Output -Encoding UTF8
Write-Host "Wrote review report: $Output"
