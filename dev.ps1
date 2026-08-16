#Requires -Version 5.1
<#
.SYNOPSIS
    Windows entry point for dev.sh.
    On macOS / Linux run:  ./dev.sh
    On Windows       run:  .\dev.ps1   (from PowerShell — recommended)
                      or:  dev          (from cmd.exe — delegates here automatically)

.DESCRIPTION
    Bootstraps a brand-new Windows machine end-to-end:
      1. Installs Git for Windows via winget   (provides Git Bash as a fallback)
      2. Installs WSL2 + Ubuntu                (the Linux runtime, same role as
                                                Apple Hypervisor VM on macOS)
      3. Waits for Ubuntu first-boot to complete
      4. Installs dev tools inside Ubuntu      (Node.js, Podman, podman-compose,
                                                cloudflared, git, python3)
      5. Re-execs dev.sh inside WSL2 Ubuntu    (from here, the Linux path takes
                                                over completely — identical to macOS)

    All steps are idempotent — safe to re-run at any time.

    SYNC FAST-PATH
      .\dev.ps1 sync                Skip the full bootstrap.  WSL2 Ubuntu must
                                    already be installed (run .\dev.ps1 once
                                    first).  Only curl + python3 are verified.
      .\dev.ps1 sync --dry-run      Show what would change, no writes.
      .\dev.ps1 sync --yes          Auto-accept all changes (CI mode).
      .\dev.ps1 sync push           Push template files back for review.
      .\dev.ps1 sync push --dir <p> Use a different local clone path.
#>

param(
    [Parameter(ValueFromRemainingArguments = $true)]
    [string[]]$DevArgs
)

$ErrorActionPreference = 'Stop'
$ROOT_DIR = $PSScriptRoot
if (-not $ROOT_DIR -or $ROOT_DIR -eq '') {
    $ROOT_DIR = Split-Path -Parent (Resolve-Path $MyInvocation.MyCommand.Path)
}

function _step { param($m) Write-Host "  >> $m" -ForegroundColor Cyan   }
function _ok   { param($m) Write-Host "  OK $m" -ForegroundColor Green  }
function _warn { param($m) Write-Host "  !! $m" -ForegroundColor Yellow }
function _fail { param($m) Write-Host "  XX $m" -ForegroundColor Red    }

# ── Helpers ───────────────────────────────────────────────────────────────────
function Test-UbuntuInstalled {
    try {
        $list = (wsl.exe --list --quiet 2>$null) -join '' -replace "`0", ''
        return $list -match 'Ubuntu'
    } catch { return $false }
}

function Get-WslPath {
    param([string]$WinPath)
    $wslPath = $null
    try {
        $wslPath = ((wsl.exe -d Ubuntu -- wslpath -a "$WinPath" 2>$null) -join '' -replace "`r", '').Trim()
    } catch {}
    if (-not $wslPath -or $wslPath -eq '') {
        $drive = $WinPath.Substring(0, 1).ToLower()
        $rest  = $WinPath.Substring(2) -replace '\\', '/'
        $wslPath = "/mnt/$drive$rest"
    }
    return $wslPath
}

function Build-ArgStr {
    param([string[]]$ArgList)
    return ($ArgList | ForEach-Object {
        if ($_ -match '\s') { "'$_'" } else { $_ }
    }) -join ' '
}

function Find-ScrcpyExecutable {
    $wingetPackages = Join-Path $env:LOCALAPPDATA 'Microsoft\WinGet\Packages'
    if (Test-Path $wingetPackages) {
        # Do not recursively scan every winget package; that can take minutes.
        $scrcpyPackages = Get-ChildItem $wingetPackages -Directory -Filter 'Genymobile.scrcpy*' -ErrorAction SilentlyContinue
        foreach ($package in $scrcpyPackages) {
            $match = Get-ChildItem $package.FullName -Recurse -Filter 'scrcpy.exe' -ErrorAction SilentlyContinue |
                Select-Object -First 1
            if ($match) { return $match.FullName }
        }
    }

    $localTools = Join-Path $env:LOCALAPPDATA 'DevTools\scrcpy'
    if (Test-Path $localTools) {
        $match = Get-ChildItem $localTools -Recurse -Filter 'scrcpy.exe' -ErrorAction SilentlyContinue |
            Select-Object -First 1
        if ($match) { return $match.FullName }
    }

    $command = Get-Command scrcpy -ErrorAction SilentlyContinue
    if ($command) { return $command.Source }
    return $null
}

function Install-Scrcpy {
    $winget = Get-Command winget.exe -ErrorAction SilentlyContinue
    if ($winget) {
        _step 'Installing scrcpy with winget...'
        & $winget.Source install --id Genymobile.scrcpy --silent --accept-package-agreements --accept-source-agreements
        $installed = Find-ScrcpyExecutable
        if ($installed) { return $installed }
        _warn 'winget did not make scrcpy available; trying the official release package.'
    } else {
        _warn 'winget is not installed; using the official scrcpy release package.'
    }

    $installRoot = Join-Path $env:LOCALAPPDATA 'DevTools\scrcpy'
    $zipPath = Join-Path $env:TEMP ("devtools-scrcpy-{0}.zip" -f $PID)

    try {
        _step 'Downloading scrcpy from the official Genymobile GitHub release...'
        $headers = @{ 'User-Agent' = 'DevTools-Script' }
        $release = Invoke-RestMethod -Uri 'https://api.github.com/repos/Genymobile/scrcpy/releases/latest' -Headers $headers
        $assetPattern = if ($env:PROCESSOR_ARCHITECTURE -match '^(ARM64|AMD64)$') {
            '^scrcpy-win64-v.*\.zip$'
        } else {
            '^scrcpy-win32-v.*\.zip$'
        }
        $asset = $release.assets | Where-Object { $_.name -match $assetPattern } | Select-Object -First 1
        if (-not $asset) { throw 'No compatible Windows scrcpy package was found in the latest release.' }

        if (Test-Path $zipPath) { Remove-Item -LiteralPath $zipPath -Force }
        Invoke-WebRequest -Uri $asset.browser_download_url -Headers $headers -OutFile $zipPath -UseBasicParsing
        New-Item -ItemType Directory -Path $installRoot -Force | Out-Null
        Expand-Archive -LiteralPath $zipPath -DestinationPath $installRoot -Force

        $installed = Find-ScrcpyExecutable
        if (-not $installed) { throw 'The downloaded package did not contain scrcpy.exe.' }
        _ok "scrcpy installed: $installed"
        return $installed
    } catch {
        _warn "Could not install scrcpy automatically: $($_.Exception.Message)"
        return $null
    } finally {
        if (Test-Path $zipPath) { Remove-Item -LiteralPath $zipPath -Force -ErrorAction SilentlyContinue }
    }
}

# ── sync fast-path ─────────────────────────────────────────────────────────────
# `.\dev.ps1 sync [flags]` skips the full tool bootstrap (podman, cloudflared,
# etc.) and goes directly to WSL2 with only the minimal tools sync needs
# (curl, python3, git, bash — all pre-installed in Ubuntu).
# This makes `.\dev.ps1 sync` as fast as possible: no package manager installs,
# no Podman machine startup, just WSL2 → bash dev.sh sync.
if ($DevArgs.Count -gt 0 -and $DevArgs[0] -eq 'sync') {
    # Get project name dynamically from folder
    $PROJECT_NAME = (Get-Item $ROOT_DIR).Name
    Write-Host ""
    Write-Host "  $PROJECT_NAME — sync" -ForegroundColor Blue
    Write-Host ("  " + ("═" * ($PROJECT_NAME.Length + 8))) -ForegroundColor Blue
    Write-Host ""

    # 1. Verify WSL2 Ubuntu is ready
    if (-not (Test-UbuntuInstalled)) {
        _fail "WSL2 Ubuntu is not installed."
        _fail "Run  .\dev.ps1  first to do the one-time setup, then re-run  .\dev.ps1 sync"
        exit 1
    }

    # 2. Quick readiness check
    try {
        $out = (wsl.exe -d Ubuntu -- bash -c 'echo ready' 2>$null) -join ''
        if ($out -notmatch 'ready') { throw "not ready" }
    } catch {
        _fail "WSL2 Ubuntu is installed but not responding."
        _fail "Try:  wsl -d Ubuntu  to diagnose, then re-run  .\dev.ps1 sync"
        exit 1
    }

    # 3. Ensure minimal tools (curl + python3) are present — idempotent, fast
    _step "Checking sync prerequisites inside Ubuntu..."
    @'
command -v curl    &>/dev/null || { sudo apt-get update -qq && sudo apt-get install -y -qq curl;    }
command -v python3 &>/dev/null || { sudo apt-get update -qq && sudo apt-get install -y -qq python3; }
echo "  OK curl $(curl --version 2>/dev/null | head -1 | awk '{print $2}')"
echo "  OK python3 $(python3 --version 2>/dev/null)"
'@ | wsl.exe -d Ubuntu -- bash -s
    if ($LASTEXITCODE -ne 0) {
        _warn "Prerequisite check had warnings (non-fatal, continuing...)"
    }

    # 4. Convert path and run dev.sh sync inside WSL2
    $wslRoot2 = Get-WslPath $ROOT_DIR
    $argStr2  = Build-ArgStr $DevArgs
    Write-Host ""
    _step "Running dev.sh $argStr2 inside Ubuntu..."
    Write-Host ""
    $tmpScript2    = "/tmp/devtools-sync-$PID.sh"
    $tmpScript2Win = "\\wsl.localhost\Ubuntu\tmp\devtools-sync-$PID.sh"
    $syncContent = "#!/bin/bash`nexport PATH=`"/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin:`$HOME/.local/bin`"`ncd '$wslRoot2'`nsed -i 's/\r//' dev.sh`nexec bash dev.sh $argStr2`n"
    [System.IO.File]::WriteAllText($tmpScript2Win, $syncContent, (New-Object System.Text.UTF8Encoding $false))
    wsl.exe -d Ubuntu -- chmod +x $tmpScript2
    wsl.exe -d Ubuntu -- bash $tmpScript2
    $syncExit = $LASTEXITCODE
    wsl.exe -d Ubuntu -- rm -f $tmpScript2 2>$null | Out-Null
    exit $syncExit
}

# ── full bootstrap (all other commands) ───────────────────────────────────────
# Get project name dynamically from folder
$PROJECT_NAME = (Get-Item $ROOT_DIR).Name
Write-Host ""
Write-Host "  $PROJECT_NAME Windows Bootstrap" -ForegroundColor Blue
Write-Host ("  " + ("═" * ($PROJECT_NAME.Length + 20))) -ForegroundColor Blue
Write-Host ""

# ── 1. Git for Windows ────────────────────────────────────────────────────────
# Git Bash is used as a fallback if someone runs bash dev.sh directly.
# The main path (WSL2) doesn't need it, but it's a useful tool to have.
$BASH = $null
foreach ($p in @(
    "$env:PROGRAMFILES\Git\bin\bash.exe",
    "$env:LOCALAPPDATA\Programs\Git\bin\bash.exe",
    "C:\Program Files\Git\bin\bash.exe"
)) { if (Test-Path $p) { $BASH = $p; break } }

if (-not $BASH) {
    $fc = Get-Command bash.exe -ErrorAction SilentlyContinue
    if ($fc -and $fc.Source -notmatch 'System32') { $BASH = $fc.Source }
}

if (-not $BASH) {
    _step "Git for Windows not found — installing via winget..."

    if (-not (Get-Command winget.exe -ErrorAction SilentlyContinue)) {
        _fail "winget not found. Install App Installer from the Microsoft Store,"
        _fail "then re-run:  .\dev.ps1"
        exit 1
    }

    winget install --id Git.Git --silent --accept-package-agreements --accept-source-agreements --scope machine 2>&1 | Out-Null

    # Refresh PATH
    $env:PATH = [System.Environment]::GetEnvironmentVariable('PATH', 'Machine') + ';' +
                [System.Environment]::GetEnvironmentVariable('PATH', 'User')

    foreach ($p in @(
        "$env:PROGRAMFILES\Git\bin\bash.exe",
        "$env:LOCALAPPDATA\Programs\Git\bin\bash.exe",
        "C:\Program Files\Git\bin\bash.exe"
    )) { if (Test-Path $p) { $BASH = $p; break } }

    if ($BASH) { _ok "Git for Windows installed  ($BASH)" }
    else {
        _warn "Git installed but bash.exe not found in PATH yet."
        _warn "This is fine — WSL2 is the primary runtime. Continuing..."
    }
} else {
    _ok "Git Bash: $BASH"
}

# ── 2. WSL2 + Ubuntu ─────────────────────────────────────────────────────────
_step "Checking WSL2 + Ubuntu..."

$wslOk = Test-UbuntuInstalled

if (-not $wslOk) {
    _step "WSL2 + Ubuntu not found — installing (one-time, ~3-5 min)..."
    _step "A UAC prompt may appear — please accept it."
    Write-Host ""

    # Try without elevation first (works on Win11 22H2+ and Win10 builds with WSL2 pre-enabled)
    try {
        Start-Process wsl.exe -ArgumentList '--install -d Ubuntu --no-launch' -PassThru -Wait -WindowStyle Normal | Out-Null
    } catch {}

    # Wait up to 2 min
    $w = 0
    while ($w -lt 120) {
        Start-Sleep 5; $w += 5
        if (Test-UbuntuInstalled) { $wslOk = $true; break }
        if ($w % 30 -eq 0) { _step "  Still installing WSL2... ($w s)" }
    }

    # Retry with elevation if still not registered
    if (-not $wslOk) {
        _step "Retrying with elevated privileges..."
        try {
            Start-Process powershell.exe `
                -ArgumentList '-NoProfile -NonInteractive -ExecutionPolicy Bypass -Command "wsl --install -d Ubuntu --no-launch"' `
                -Verb RunAs -PassThru -Wait -WindowStyle Normal | Out-Null
        } catch {
            _warn "UAC was denied. Run this in an Administrator PowerShell, then restart your PC:"
            _warn "   wsl --install -d Ubuntu"
            _warn "After restart, re-run:  .\dev.ps1"
            exit 1
        }
        $w = 0
        while ($w -lt 180) {
            Start-Sleep 5; $w += 5
            if (Test-UbuntuInstalled) { $wslOk = $true; break }
            if ($w % 30 -eq 0) { _step "  Still waiting for Ubuntu... ($w s)" }
        }
    }

    if (-not $wslOk) {
        _warn "Ubuntu did not appear after install. A reboot may be needed."
        _warn "Restart your PC, then re-run:  .\dev.ps1"
        exit 1
    }
    _ok "WSL2 + Ubuntu installed"
} else {
    _ok "WSL2 Ubuntu ready"
}

# ── 3. Ubuntu first-boot ──────────────────────────────────────────────────────
# A freshly installed distro may still be extracting its rootfs (~30 s).
_step "Waiting for Ubuntu to respond..."
$ready = $false; $w = 0
while ($w -lt 240) {
    try {
        $out = (wsl.exe -d Ubuntu -- bash -c 'echo ready' 2>$null) -join ''
        if ($out -match 'ready') { $ready = $true; break }
    } catch {}
    Start-Sleep 5; $w += 5
    if ($w % 30 -eq 0) { _step "  Still initialising Ubuntu... ($w s)" }
}

if (-not $ready) {
    # Ubuntu may be waiting on an interactive first-launch password dialog.
    # Set root as default user so it runs unattended.
    _step "Setting Ubuntu default user to root (unattended mode)..."
    try { ubuntu.exe config --default-user root 2>$null } catch {}
    wsl.exe --terminate Ubuntu 2>$null | Out-Null
    Start-Sleep 3
    try {
        $out = (wsl.exe -d Ubuntu -- bash -c 'echo ready' 2>$null) -join ''
        $ready = $out -match 'ready'
    } catch {}
}

if (-not $ready) {
    _fail "Ubuntu is installed but won't respond."
    _fail "Open a terminal and run:  wsl -d Ubuntu"
    _fail "Complete the first-launch setup, then re-run:  .\dev.ps1"
    exit 1
}
_ok "Ubuntu ready"

# ── 4. Bootstrap tools inside Ubuntu (idempotent) ────────────────────────────
_step "Checking/installing dev tools inside Ubuntu..."
Write-Host ""

$bootstrapScript = @'
set -e
export DEBIAN_FRONTEND=noninteractive

_need() {
  local MISSING=""
  for pkg in "$@"; do
    dpkg -s "$pkg" &>/dev/null || MISSING="$MISSING $pkg"
  done
  [ -z "$MISSING" ] && return 0
  sudo apt-get update -qq
  sudo apt-get install -y -qq $MISSING
}

# Core utilities
_need curl ca-certificates gnupg git python3

# Node.js LTS (via NodeSource)
if ! command -v node &>/dev/null; then
  echo "  >> Installing Node.js LTS..."
  curl -fsSL https://deb.nodesource.com/setup_lts.x | sudo -E bash - 2>/dev/null
  sudo apt-get install -y -qq nodejs
  echo "  OK Node.js $(node --version)"
else
  echo "  OK Node.js $(node --version)"
fi

# Podman
if ! command -v podman &>/dev/null; then
  echo "  >> Installing Podman..."
  sudo apt-get update -qq
  sudo apt-get install -y -qq podman 2>/dev/null || {
    curl -fsSL https://download.opensuse.org/repositories/devel:/kubic:/libcontainers:/unstable/xUbuntu_22.04/Release.key \
      | sudo gpg --dearmor -o /usr/share/keyrings/podman.gpg
    echo "deb [signed-by=/usr/share/keyrings/podman.gpg] https://download.opensuse.org/repositories/devel:/kubic:/libcontainers:/unstable/xUbuntu_22.04 /" \
      | sudo tee /etc/apt/sources.list.d/podman.list
    sudo apt-get update -qq && sudo apt-get install -y -qq podman
  }
  echo "  OK Podman $(podman --version)"
else
  echo "  OK Podman $(podman --version)"
fi

# podman-compose
if ! command -v podman-compose &>/dev/null; then
  echo "  >> Installing podman-compose..."
  # Ubuntu 24.04+ uses PEP 668 — pip install requires --break-system-packages
  # or pipx. We try pipx first (cleanest), fall back to pip with the flag.
  if ! command -v pipx &>/dev/null; then
    sudo apt-get install -y -qq pipx 2>/dev/null || true
  fi
  if command -v pipx &>/dev/null; then
    pipx install podman-compose 2>/dev/null && export PATH="$HOME/.local/bin:$PATH" || true
  fi
  if ! command -v podman-compose &>/dev/null; then
    pip3 install --user --break-system-packages -q podman-compose 2>/dev/null \
      || pip3 install --user -q podman-compose 2>/dev/null || true
  fi
  export PATH="$HOME/.local/bin:$PATH"
  echo "  OK podman-compose installed"
else
  echo "  OK podman-compose ready"
fi

# Podman: add Docker Hub as default unqualified search registry
# Without this, short image names like "postgres:17" or "redis:7-alpine" fail
# with "did not resolve to an alias and no unqualified-search registries defined"
sudo mkdir -p /etc/containers/registries.conf.d
if ! grep -q 'docker.io' /etc/containers/registries.conf.d/docker.conf 2>/dev/null; then
  echo 'unqualified-search-registries = ["docker.io"]' \
    | sudo tee /etc/containers/registries.conf.d/docker.conf >/dev/null
  echo "  OK Podman registry configured (docker.io)"
fi

# cloudflared
if ! command -v cloudflared &>/dev/null; then
  echo "  >> Installing cloudflared..."
  curl -fsSL https://pkg.cloudflare.com/cloudflare-main.gpg \
    | sudo tee /usr/share/keyrings/cloudflare-main.gpg >/dev/null
  echo "deb [signed-by=/usr/share/keyrings/cloudflare-main.gpg] https://pkg.cloudflare.com/cloudflared jammy main" \
    | sudo tee /etc/apt/sources.list.d/cloudflared.list >/dev/null
  sudo apt-get update -qq && sudo apt-get install -y -qq cloudflared 2>/dev/null || true
  echo "  OK cloudflared installed"
else
  echo "  OK cloudflared ready"
fi

echo ""
echo "  OK All tools ready inside Ubuntu"
'@

$bootstrapScript | wsl.exe -d Ubuntu -- bash -s
if ($LASTEXITCODE -ne 0) {
    _warn "Tool bootstrap had errors (non-fatal — will retry next run)"
}

# ── 5. Convert Windows path → WSL2 path and hand off ────────────────────────
Write-Host ""
_step "Switching to WSL2 Linux environment..."

$wslRoot = Get-WslPath $ROOT_DIR
_ok "WSL2 path: $wslRoot"
Write-Host ""

$argStr = Build-ArgStr $DevArgs

_step "Running dev.sh inside Ubuntu..."
Write-Host ""

# Write the command to a temp script to avoid PowerShell quoting issues.
# Use [IO.File]::WriteAllText with explicit LF endings — piping through
# PowerShell adds CRLF which bash misparsed, mangling the argument list.
$tmpScript = "/tmp/devtools-run-$PID.sh"
$tmpScriptWin = "\\wsl.localhost\Ubuntu\tmp\devtools-run-$PID.sh"
$bashContent = "#!/bin/bash`nexport PATH=`"/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin:`$HOME/.local/bin`"`ncd '$wslRoot'`nsed -i 's/\r//' dev.sh`nexec bash dev.sh $argStr`n"
[System.IO.File]::WriteAllText($tmpScriptWin, $bashContent, (New-Object System.Text.UTF8Encoding $false))
wsl.exe -d Ubuntu -- chmod +x $tmpScript
wsl.exe -d Ubuntu -- bash $tmpScript
$devShExitCode = $LASTEXITCODE
wsl.exe -d Ubuntu -- rm -f $tmpScript 2>$null | Out-Null

# ── Android: open emulator screen via scrcpy ─────────────────────────────────
if ($DevArgs.Count -gt 0 -and $DevArgs[0] -eq 'android') {
    $scrcpyExe = Find-ScrcpyExecutable

    if (-not $scrcpyExe) {
        Write-Host ""
        $scrcpyExe = Install-Scrcpy
    }

    if ($scrcpyExe) {
        Write-Host ""
        Write-Host "  >> Connecting to Android emulator screen..." -ForegroundColor Cyan

        # Get WSL IP address
        $wslIpOutput = (wsl.exe -d Ubuntu -- bash -c "hostname -I" 2>$null) -join ''
        $wslIp = $null
        if ($wslIpOutput) {
            $wslIpParts = $wslIpOutput.Trim() -split '\s+'
            if ($wslIpParts.Count -gt 0) { $wslIp = $wslIpParts[0] }
        }

        if (-not $wslIp) {
            _fail 'Could not determine WSL IP address.'
            exit 1
        }

        _step "WSL IP: $wslIp"

        # First, wait for the emulator to be fully booted in WSL
        _step "Waiting for emulator to fully boot (this may take 30-60 seconds)..."
        $bootWait = 0
        $emulatorBooted = $false
        while ($bootWait -lt 120) {
            # Check both that device is listed AND that boot is complete
            $deviceCheck = (wsl.exe -d Ubuntu -- bash -c "/root/Android/Sdk/platform-tools/adb devices 2>/dev/null | grep 'emulator' | grep -c 'device$'" 2>$null) -join ''
            $bootCompleteCheck = (wsl.exe -d Ubuntu -- bash -c "/root/Android/Sdk/platform-tools/adb -s emulator-5554 shell getprop sys.boot_completed 2>/dev/null | tr -d '\r\n'" 2>$null) -join ''
            
            if ($deviceCheck -match '^\d+$' -and [int]$deviceCheck -gt 0 -and $bootCompleteCheck -eq '1') {
                $emulatorBooted = $true
                break
            }
            Start-Sleep -Seconds 3
            $bootWait += 3
            if ($bootWait % 15 -eq 0) {
                _step "Still waiting for emulator boot... (${bootWait}s elapsed)"
            }
        }

        if (-not $emulatorBooted) {
            _fail 'Emulator did not fully boot within 2 minutes.'
            _warn 'The emulator may be starting slowly. Wait a bit longer and try:'
            _warn '  wsl -d Ubuntu -- /root/Android/Sdk/platform-tools/adb devices'
            exit 1
        }
        
        _ok "Emulator is fully booted and ready"

        # Put emulator in TCP mode so Windows can reach it via port forward
        _step "Enabling TCP/IP mode on emulator..."
        wsl.exe -d Ubuntu -- bash -c "/root/Android/Sdk/platform-tools/adb -s emulator-5554 tcpip 5555 2>/dev/null" 2>&1 | Out-Null
        Start-Sleep -Seconds 2

        # Forward Windows localhost:5555 → WSL emulator:5555
        _step "Setting up port forwarding from Windows to WSL..."
        try {
            netsh interface portproxy delete v4tov4 listenport=5555 listenaddress=127.0.0.1 2>&1 | Out-Null
            netsh interface portproxy add v4tov4 listenport=5555 listenaddress=127.0.0.1 connectport=5555 connectaddress=$wslIp 2>&1 | Out-Null
        } catch {
            try {
                _step "Requesting administrator elevation for port forwarding..."
                $ps = Start-Process powershell -Verb RunAs -PassThru -WindowStyle Hidden -ArgumentList `
                    "-NoProfile -NonInteractive -ExecutionPolicy Bypass -Command `"netsh interface portproxy delete v4tov4 listenport=5555 listenaddress=127.0.0.1 2>``$null; netsh interface portproxy add v4tov4 listenport=5555 listenaddress=127.0.0.1 connectport=5555 connectaddress=$wslIp`""
                $ps.WaitForExit(10000) | Out-Null
            } catch {
                _warn "Could not set up port forwarding with elevation."
            }
        }

        Start-Sleep -Seconds 2

        # Verify port forwarding is working
        $adbBridgeReady = $false
        try {
            $adbBridgeReady = Test-NetConnection -ComputerName 127.0.0.1 -Port 5555 `
                -InformationLevel Quiet -WarningAction SilentlyContinue -ErrorAction SilentlyContinue
        } catch {}

        if (-not $adbBridgeReady) {
            _fail 'Port forwarding failed. Cannot reach WSL emulator from Windows.'
            _warn 'The emulator is running in WSL, but Windows cannot connect to it.'
            _warn 'Re-run this command and accept the Administrator prompt to set up port forwarding.'
            exit 1
        }

        _ok "Port forwarding established"

        # Connect Windows ADB to the TCP/IP emulator
        $scrcpyAdb = Join-Path (Split-Path $scrcpyExe -Parent) 'adb.exe'
        if (Test-Path $scrcpyAdb) {
            _step "Connecting Windows ADB to emulator..."
            & $scrcpyAdb disconnect 127.0.0.1:5555 2>$null | Out-Null
            & $scrcpyAdb connect 127.0.0.1:5555 2>&1 | Out-Null
            Start-Sleep -Seconds 1
            
            # Verify connection
            $adbDevices = (& $scrcpyAdb devices 2>$null) -join "`n"
            if ($adbDevices -notmatch '127\.0\.0\.1:5555.*device') {
                _fail 'Windows ADB could not connect to the WSL emulator.'
                _warn "ADB output: $adbDevices"
                exit 1
            }
            _ok "Windows ADB connected to emulator"
            
            # Set up adb reverse for Metro and API ports
            _step "Configuring port forwarding for Metro bundler and API..."
            & $scrcpyAdb -s 127.0.0.1:5555 reverse tcp:8081 tcp:8081 2>$null | Out-Null
            & $scrcpyAdb -s 127.0.0.1:5555 reverse tcp:8082 tcp:8082 2>$null | Out-Null
            & $scrcpyAdb -s 127.0.0.1:5555 reverse tcp:8000 tcp:8000 2>$null | Out-Null
            _ok "App connectivity configured"
            
            $scrcpyArgs = @('--serial=127.0.0.1:5555')
        } else {
            $scrcpyArgs = @('--tcpip=127.0.0.1:5555')
        }
        
        $scrcpyArgs += @('--force-adb-forward', '--max-size=1024', '--stay-awake')

        # Launch scrcpy — shows the emulator screen in a Windows window
        # Start it with CreateNoWindow to prevent the console but show the GUI
        Write-Host ""
        Write-Host "  OK Opening emulator screen..." -ForegroundColor Green
        
        # Add flags to reduce errors
        $scrcpyArgs += @('--no-audio')
        
        try {
            # Use Start-Process with NoNewWindow to prevent console but allow GUI
            $psi = New-Object System.Diagnostics.ProcessStartInfo
            $psi.FileName = $scrcpyExe
            $psi.Arguments = ($scrcpyArgs -join ' ')
            $psi.UseShellExecute = $false
            $psi.CreateNoWindow = $true
            $psi.RedirectStandardOutput = $true
            $psi.RedirectStandardError = $true
            
            $scrcpyProcess = New-Object System.Diagnostics.Process
            $scrcpyProcess.StartInfo = $psi
            [void]$scrcpyProcess.Start()
            
            Start-Sleep -Seconds 2
            if ($scrcpyProcess.HasExited -and $scrcpyProcess.ExitCode -ne 0) {
                _warn "scrcpy exited with code $($scrcpyProcess.ExitCode), but emulator may still be running in WSL2."
            }
        } catch {
            _warn "Could not launch scrcpy: $($_.Exception.Message)"
            _warn "The emulator is running in WSL2, but screen mirroring failed."
        }
    } else {
        Write-Host ""
        _fail "scrcpy could not be installed."
        _warn "The emulator is running headlessly in WSL."
        _warn "Install scrcpy manually from: https://github.com/Genymobile/scrcpy"
        _warn "Then run: .\dev.ps1 android"
        exit 1
    }
}

exit $devShExitCode
