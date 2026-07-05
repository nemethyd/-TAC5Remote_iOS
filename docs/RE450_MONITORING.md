# RE450 OpenWrt Monitoring

This monitor adds router-side Ethernet L1/L2 and near-L3 visibility around the TAC5 device.

It starts these processes on the RE450 over SSH:

- `tcpdump` ring buffer on the chosen bridge or interface
- periodic `ip neigh show` and `ip route show` snapshots
- `logread -f`
- `ubus listen`
- 5 s Ethernet port sampler for carrier, operstate, drops, and errors
- optional 1 Hz ping probe to the TAC5 device

All artifacts stay under `/tmp/re450_monitor` on the router while the session is running.
When the monitor is stopped, the files are downloaded into the local `captures/` folder.

## Prerequisites

- SSH access to the RE450 OpenWrt device
- `tcpdump` installed on OpenWrt (`tcpdump-mini` is enough)
- local `ssh` and `scp` available in `PATH`

## Start

```powershell
pwsh .\tools\start_re450_monitor.ps1
```

Example with explicit router and bridge:

```powershell
pwsh .\tools\start_re450_monitor.ps1 -RouterHost 192.168.10.52 -Interface br-lan -TargetHost 192.168.10.80
```

Example with explicit Ethernet member ports:

```powershell
pwsh .\tools\start_re450_monitor.ps1 -RouterHost 192.168.10.52 -Interface br-lan -EthernetInterfaces eth0,eth0.1 -TargetHost 192.168.10.80
```

Example with explicit sampling intervals:

```powershell
pwsh .\tools\start_re450_monitor.ps1 -NeighborSampleSeconds 2 -EthernetSampleSeconds 5 -PingIntervalSeconds 1
```

## Stop And Download

```powershell
pwsh .\tools\stop_re450_monitor.ps1
```

## Incident Trigger Watcher

This optional watcher runs on the workstation and auto-captures evidence when TAC5 becomes unreachable.

It does this when consecutive ping failures reach the configured threshold:

- writes outage marker to `captures/incident_markers.log`
- saves local ping and ARP snapshots
- runs a remote RE450 diagnostic snapshot over SSH (link/L3/neighbor state, `free`, `df -h`, `iwinfo wlan0` signal/association info, and a log tail)
- records a short remote pcap (`arp`, `icmp`, TAC5 `tcp/502`, `dhcp`) and downloads it

RE450 is RAM/flash-constrained (observed ~58MB total RAM, ~1.6MB writable overlay), so the watcher also runs a lightweight periodic housekeeping step, independent of outages:

- every `LogPullIntervalSeconds` (default 900s / 15 min), it opens a single short SSH session, saves the current `logread` output to `captures/re450_logs/`, then restarts the RE450 log daemon (`/etc/init.d/log restart`) to free its in-memory ring buffer
- this step is skipped while an outage is in progress, to avoid adding load exactly when the device may already be struggling
- disable it with `-DisableLogPull` if not needed

Start it:

```powershell
pwsh .\tools\start_re450_incident_watch.ps1
```

Example with explicit thresholds and capture duration:

```powershell
pwsh .\tools\start_re450_incident_watch.ps1 -FailThreshold 3 -RecoverThreshold 2 -ProbeIntervalSeconds 2 -RemoteCaptureSeconds 20 -LogPullIntervalSeconds 900
```

Artifacts are stored under:

- `captures/re450_incidents/incident_YYYYMMDD_HHMMSS/`
- `captures/re450_logs/re450_log_YYYYMMDD_HHMMSS.txt` (periodic log pulls, cleared from the router after each pull)

Stop with `Ctrl+C` in the watcher terminal.

## Why This Helps

This setup can distinguish between:

- the TAC5 disappearing from ARP on the router side
- Ethernet carrier loss or LAN port flap on OpenWrt
- Ethernet-side error and drop counter growth before disconnect
- bridge or neighbor table churn on OpenWrt
- user-visible app disconnects that are only symptoms of lower-layer loss
