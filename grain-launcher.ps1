$ErrorActionPreference = 'Stop'

$root = Split-Path -Parent $MyInvocation.MyCommand.Path
$webDir = Join-Path $root 'build\web'
$port = 8421
$url = "http://localhost:$port/"

if (-not (Test-Path $webDir)) {
    [System.Windows.Forms.MessageBox]::Show("build\web not found. Run a Flutter web build first.", 'Grain') | Out-Null
    exit 1
}

$chromeCandidates = @(
    "$env:ProgramFiles\Google\Chrome\Application\chrome.exe",
    "${env:ProgramFiles(x86)}\Google\Chrome\Application\chrome.exe",
    "$env:LOCALAPPDATA\Google\Chrome\Application\chrome.exe"
)
$chrome = $chromeCandidates | Where-Object { Test-Path $_ } | Select-Object -First 1
if (-not $chrome) {
    Write-Error 'Chrome not found.'
    exit 1
}

$inUse = $false
try {
    $listener = [System.Net.Sockets.TcpListener]::new([System.Net.IPAddress]::Loopback, $port)
    $listener.Start(); $listener.Stop()
} catch { $inUse = $true }

$server = $null
if (-not $inUse) {
    $server = Start-Process -FilePath 'python' -ArgumentList '-m','http.server',$port,'--bind','127.0.0.1' `
        -WorkingDirectory $webDir -WindowStyle Hidden -PassThru
    Start-Sleep -Milliseconds 700
}

$profileDir = Join-Path $env:LOCALAPPDATA 'Grain\ChromeProfile'
New-Item -ItemType Directory -Force -Path $profileDir | Out-Null

$chromeProc = Start-Process -FilePath $chrome `
    -ArgumentList "--app=$url","--user-data-dir=$profileDir","--no-first-run","--no-default-browser-check" `
    -PassThru
$chromeProc.WaitForExit()

if ($server -and -not $server.HasExited) {
    Stop-Process -Id $server.Id -Force -ErrorAction SilentlyContinue
}
