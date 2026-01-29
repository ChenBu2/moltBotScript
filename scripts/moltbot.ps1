# Moltbot one-click deploy/start script (Windows PowerShell)
# Usage: .\moltbot.ps1 -Mode native|docker -Channel stable|beta|dev -Port 18789
# Env override: $env:MODE, $env:CHANNEL, $env:PORT
# Requires: PowerShell 7+, Node >=22 (auto-install if possible), pnpm/corepack, Docker (optional)

[CmdletBinding()]
param(
    [ValidateSet('native','docker')]
    [string]$Mode = 'native',
    [ValidateSet('stable','beta','dev')]
    [string]$Channel = 'stable',
    [int]$Port = 18789,
    [switch]$Help
)

$ErrorActionPreference = 'Stop'
$version = '2026-01-29'
$logPath = Join-Path $env:TEMP 'moltbot-gateway.log'

function Write-Info($msg) { Write-Host "[moltbot] $msg" -ForegroundColor Green }
function Write-Warn($msg) { Write-Host "[moltbot] $msg" -ForegroundColor Yellow }
function Write-Err($msg) { Write-Host "[moltbot] $msg" -ForegroundColor Red }

function Show-Usage {
    Write-Host "Usage: .\moltbot.ps1 -Mode native|docker -Channel stable|beta|dev -Port 18789" -ForegroundColor Cyan
    Write-Host "Env override: MODE, CHANNEL, PORT" -ForegroundColor Cyan
}

if ($Help) { Show-Usage; exit 0 }

if ($env:MODE) { $Mode = $env:MODE }
if ($env:CHANNEL) { $Channel = $env:CHANNEL }
if ($env:PORT) { $Port = [int]$env:PORT }

function Test-NodeVersionOK {
    try {
        $v = (& node -v) -replace '^v',''
        if (-not $v) { return $false }
        $major = [int]($v.Split('.')[0])
        return ($major -ge 22)
    } catch { return $false }
}

function Ensure-Node {
    if (Test-NodeVersionOK) { Write-Info "Node $(node -v) OK (>=22)"; return }
    Write-Warn "Node >=22 not found. Attempting install..."
    $winget = Get-Command winget -ErrorAction SilentlyContinue
    if ($winget) {
        try {
            Write-Info "Installing Node via winget (OpenJS.NodeJS)"
            winget install --id OpenJS.NodeJS --silent --accept-package-agreements --accept-source-agreements
        } catch {
            Write-Warn "winget Node install failed: $($_.Exception.Message)"
        }
    }
    if (-not (Test-NodeVersionOK)) {
        if ($winget) {
            try {
                Write-Info "Installing NVM for Windows via winget"
                winget install --id CoreyButler.NVMforWindows --silent --accept-package-agreements --accept-source-agreements
            } catch {
                Write-Warn "winget NVM install failed: $($_.Exception.Message)"
            }
        }
        $nvm = Get-Command nvm -ErrorAction SilentlyContinue
        if ($nvm) {
            Write-Info "Installing Node 22 via nvm-windows"
            & nvm install 22
            & nvm use 22
        } else {
            Write-Err "NVM not available; please install Node >=22 manually."
        }
    }
    if (-not (Test-NodeVersionOK)) { throw "Node install failed or version <22" }
}

function Ensure-Corepack {
    $corepack = Get-Command corepack -ErrorAction SilentlyContinue
    if ($corepack) {
        try { corepack enable } catch {}
        try { corepack prepare pnpm@latest --activate } catch {}
    } else {
        $npm = Get-Command npm -ErrorAction SilentlyContinue
        if ($npm) {
            Write-Info "Installing pnpm globally via npm"
            npm i -g pnpm@latest
        } else {
            throw "npm not found; cannot install pnpm"
        }
    }
}

function Has-Repo {
    (Test-Path 'package.json') -and (Test-Path 'pnpm-workspace.yaml')
}

function Load-Env {
    if (Test-Path '.env') {
        Write-Info "Loading .env"
        Get-Content '.env' | ForEach-Object {
            $line = $_.Trim()
            if ($line -and -not $line.StartsWith('#') -and $line.Contains('=')) {
                $key,$val = $line.Split('=',2)
                $key = $key.Trim()
                $val = $val.Trim()
                [Environment]::SetEnvironmentVariable($key,$val,'Process')
            }
        }
    }
}

function Install-Native-Global {
    Ensure-Corepack
    $pnpm = Get-Command pnpm -ErrorAction SilentlyContinue
    if ($pnpm) {
        Write-Info "Installing moltbot globally via pnpm ($Channel)"
        try { pnpm add -g "moltbot@$Channel" } catch { pnpm add -g moltbot@latest }
    } else {
        Write-Info "Installing moltbot globally via npm ($Channel)"
        try { npm i -g "moltbot@$Channel" } catch { npm i -g moltbot@latest }
    }
}

function Install-Native-Source {
    Ensure-Corepack
    $pnpm = Get-Command pnpm -ErrorAction SilentlyContinue
    if (-not $pnpm) { throw "pnpm is required for source builds" }
    Write-Info "Installing from source (pnpm install)"
    pnpm install
    Write-Info "Building UI (pnpm ui:build)"
    try { pnpm ui:build } catch { Write-Warn "ui:build failed; continuing" }
    Write-Info "Building project (pnpm build)"
    pnpm build
}

function Start-Gateway-Native {
    $moltbot = Get-Command moltbot -ErrorAction SilentlyContinue
    if (-not $moltbot) { throw "moltbot CLI not found after global install" }
    Write-Info "Running onboarding wizard (install daemon)"
    try { moltbot onboard --install-daemon } catch { Write-Warn "onboard failed: $($_.Exception.Message)" }
    Write-Info "Starting Gateway on port $Port"
    $args = @('gateway','--port',"$Port",'--verbose')
    Start-Process -FilePath 'moltbot' -ArgumentList $args -RedirectStandardOutput $logPath -RedirectStandardError $logPath -NoNewWindow
    Write-Info "Gateway log: $logPath"
}

function Start-Gateway-Source {
    Write-Info "Running onboarding wizard via pnpm (TypeScript)"
    try { pnpm moltbot onboard --install-daemon } catch { Write-Warn "onboard failed: $($_.Exception.Message)" }
    Write-Info "Starting Gateway (pnpm gateway:watch)"
    Start-Process -FilePath 'pnpm' -ArgumentList @('gateway:watch') -RedirectStandardOutput $logPath -RedirectStandardError $logPath -NoNewWindow
    Write-Info "Gateway log: $logPath"
}

function Install-Docker {
    $docker = Get-Command docker -ErrorAction SilentlyContinue
    if (-not $docker) { throw "Docker is not installed" }
    if (Test-Path './docker-setup.sh') {
        $bash = Get-Command bash -ErrorAction SilentlyContinue
        if ($bash) {
            Write-Info "Running docker-setup.sh"
            & bash ./docker-setup.sh
        } else {
            Write-Warn "bash not available; skipping docker-setup.sh"
        }
    }
    $composePlugin = $false
    try {
        & docker compose version | Out-Null
        $composePlugin = $true
    } catch {}
    if ($composePlugin) {
        Write-Info "Starting docker compose (plugin)"
        & docker compose up -d
    } else {
        $dc = Get-Command docker-compose -ErrorAction SilentlyContinue
        if ($dc) {
            Write-Info "Starting docker-compose"
            & docker-compose up -d
        } else {
            throw "docker compose not available"
        }
    }
}

try {
    Write-Info "Moltbot one-click deploy/start ($Mode)"
    Load-Env
    Ensure-Node
    if ($Mode -eq 'docker') {
        Install-Docker
        Write-Info "Docker deployment started."
    } else {
        if (Has-Repo) {
            Write-Info "Detected moltbot repository (source build)"
            Install-Native-Source
            Start-Gateway-Source
        } else {
            Write-Info "Global install (no repo detected)"
            Install-Native-Global
            Start-Gateway-Native
        }
    }
    Write-Info "Done. Try: moltbot message send --to +1234567890 --message 'Hello'"
} catch {
    Write-Err "Failed: $($_.Exception.Message)"
    exit 1
}