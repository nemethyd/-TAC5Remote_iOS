param(
    [string]$StateFile = "captures/re450_monitor_state.json",
    [string]$DownloadDir = "",
    [switch]$KeepRemoteFiles
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

if (-not (Test-Path $StateFile)) {
    throw "State file not found: $StateFile"
}

$state = Get-Content $StateFile -Raw | ConvertFrom-Json
$sshPath = Get-RequiredCommandPath -Name "ssh"
$scpPath = Get-RequiredCommandPath -Name "scp"

$startedAt = [DateTimeOffset]::Parse($state.startedAt)
$downloadRoot = if ($DownloadDir -and $DownloadDir.Trim().Length -gt 0) {
    $DownloadDir
} else {
    Join-Path $state.captureDir ("re450_{0}" -f $startedAt.ToString("yyyyMMdd_HHmmss"))
}

New-Item -ItemType Directory -Path $downloadRoot -Force | Out-Null

$pidList = @($state.processes | ForEach-Object { [string]$_.pid })
$pidArgs = $pidList -join " "

$remoteStopScript = @"
set +e
for pid in $pidArgs; do
  kill "`$pid" 2>/dev/null || true
done
sync
ls -1 "$($state.remoteDir)" 2>/dev/null || true
"@

$remoteStopScript = $remoteStopScript -replace "`r`n", "`n"

$stopOutput = ($remoteStopScript | & $sshPath @sshOptions "-T" "-p" "$($state.routerPort)" "$($state.routerUser)@$($state.routerHost)" "sh") 2>&1

if ($LASTEXITCODE -ne 0) {
    throw "Failed to stop RE450 monitor on $($state.routerHost). ssh exit code: $LASTEXITCODE`n$($stopOutput -join "`n")"
}

$remoteSpec = "$($state.routerUser)@$($state.routerHost):$($state.remoteDir)"
& $scpPath "-O" @sshOptions "-P" "$($state.routerPort)" "-r" $remoteSpec $downloadRoot | Out-Null
if ($LASTEXITCODE -ne 0) {
    throw "Failed to download RE450 monitor artifacts from $($state.routerHost). scp exit code: $LASTEXITCODE"
}

$downloadedDir = Join-Path $downloadRoot ([System.IO.Path]::GetFileName($state.remoteDir))

if (-not $KeepRemoteFiles) {
    $cleanupScript = "rm -rf `"$($state.remoteDir)`""
    & $sshPath @sshOptions "-p" "$($state.routerPort)" "$($state.routerUser)@$($state.routerHost)" $cleanupScript | Out-Null
}

Remove-Item $StateFile -Force

Write-Host "Stopped RE450 L1/L2 monitor"
Write-Host "  Router:       $($state.routerUser)@$($state.routerHost):$($state.routerPort)"
Write-Host "  Download root:$downloadRoot"
Write-Host "  Files:"
Get-ChildItem -Path $downloadedDir -File -Recurse -ErrorAction SilentlyContinue |
    Sort-Object LastWriteTime -Descending |
    Select-Object -First 20 |
    ForEach-Object {
        Write-Host ("    {0}  {1} KB" -f $_.FullName, [int]($_.Length / 1KB))
    }

if ($KeepRemoteFiles) {
    Write-Host "Remote files kept in $($state.remoteDir)"
} else {
    Write-Host "Remote files removed from $($state.remoteDir)"
}