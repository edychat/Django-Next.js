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

# ── sync fast-path ─────────────────────────────────────────────────────────────
# `.\dev.ps1 sync [flags]` skips the full tool bootstrap (podman, cloudflared,
# etc.) and goes directly to WSL2 with only the minimal tools sync needs
# (curl, python3, git, bash — all pre-installed in Ubuntu).
# This makes `.\dev.ps1 sync` as fast as possible: no package manager installs,
# no Podman machine startup, just WSL2 → bash dev.sh sync.
if ($DevArgs.Count -gt 0 -and $DevArgs[0] -eq 'sync') {
    Write-Host ""
    Write-Host "  OldBook.ai  — sync" -ForegroundColor Blue
    Write-Host "  ══════════════════" -ForegroundColor Blue
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
    wsl.exe -d Ubuntu -- bash -c @'
command -v curl    &>/dev/null || { sudo apt-get update -qq && sudo apt-get install -y -qq curl;    }
command -v python3 &>/dev/null || { sudo apt-get update -qq && sudo apt-get install -y -qq python3; }
echo "  OK curl $(curl --version 2>/dev/null | head -1 | awk '{print $2}')"
echo "  OK python3 $(python3 --version 2>/dev/null)"
'@
    if ($LASTEXITCODE -ne 0) {
        _warn "Prerequisite check had warnings (non-fatal, continuing...)"
    }

    # 4. Convert path and run dev.sh sync inside WSL2
    $wslRoot = Get-WslPath $ROOT_DIR
    $argStr  = Build-ArgStr $DevArgs   # includes 'sync' plus any extra flags

    Write-Host ""
    _step "Running dev.sh $argStr inside Ubuntu..."
    Write-Host ""

    wsl.exe -d Ubuntu -- bash -c "export PATH=`"`$HOME/.local/bin:`$PATH`"; cd '$wslRoot' && sed -i 's/\r//' dev.sh && bash dev.sh $argStr"
    exit $LASTEXITCODE
}

# ── full bootstrap (all other commands) ───────────────────────────────────────
Write-Host ""
Write-Host "  OldBook.ai  Windows Bootstrap" -ForegroundColor Blue
Write-Host "  ================================" -ForegroundColor Blue
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

wsl.exe -d Ubuntu -- bash -c $bootstrapScript
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

$wslCmd = "export PATH=`"`$HOME/.local/bin:`$PATH`"; cd '$wslRoot' && sed -i 's/\r//' dev.sh && bash dev.sh $argStr"

_step "Running dev.sh inside Ubuntu..."
Write-Host ""
wsl.exe -d Ubuntu -- bash -c $wslCmd
exit $LASTEXITCODE
