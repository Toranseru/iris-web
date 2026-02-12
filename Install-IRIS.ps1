<#
.SYNOPSIS
  One-click install: WSL2, Docker Desktop, clone Toranseru/iris-web, generate .env, deploy IRIS on localhost.
.DESCRIPTION
  Run as Administrator when installing Docker/WSL. Use -SkipDockerInstall to run without elevation when Docker is already installed.
  Installs Docker Desktop (with WSL2) if missing, clones or pulls the repo,
  creates .env with generated secrets and SERVER_NAME=localhost, then runs docker compose up.
  IRIS will be available at https://localhost. Admin password is printed and saved to iris-admin-password.txt.
  First visit: accept the dev certificate warning (Advanced -> Proceed to localhost).
.NOTES
  Reboot may be required after WSL/Docker install; if so, run this script again after reboot.
  Port 443 must be free. Git must be on PATH for clone/pull.
#>

param(
    [string]$InstallParent = $env:USERPROFILE,
    [string]$RepoUrl = "https://github.com/Toranseru/iris-web.git",
    [switch]$SkipDockerInstall
)

$ErrorActionPreference = "Stop"
$RepoName = "iris-web"
$RepoRoot = Join-Path $InstallParent $RepoName

function Write-Step { param([string]$Msg) Write-Host "`n--- $Msg ---" -ForegroundColor Cyan }
function Write-Ok { param([string]$Msg) Write-Host $Msg -ForegroundColor Green }
function Write-Warn { param([string]$Msg) Write-Host $Msg -ForegroundColor Yellow }

# ---------- Step 1: WSL2 and Docker Desktop ----------
Write-Step "Step 1: WSL2 and Docker Desktop"

# Check WSL
$wslOk = $false
try {
    $wslVer = wsl -l -v 2>$null
    if ($LASTEXITCODE -eq 0 -and $wslVer) { $wslOk = $true }
} catch {}
if (-not $wslOk) {
    Write-Warn "WSL not detected. Installing WSL (may require reboot)..."
    wsl --install
    Write-Warn "If the system rebooted, run this script again after reboot."
    exit 0
}

# Check Docker
$dockerOk = $false
try {
    docker info 2>$null | Out-Null
    if ($LASTEXITCODE -eq 0) { $dockerOk = $true }
} catch {}

if (-not $dockerOk -and -not $SkipDockerInstall) {
    $isAdmin = ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
    if (-not $isAdmin) {
        Write-Host "Docker is not installed and this script is not running as Administrator. Run PowerShell as Administrator, or install Docker Desktop manually and run with -SkipDockerInstall." -ForegroundColor Red
        exit 1
    }
    $installerPath = Join-Path $env:TEMP "DockerDesktopInstaller.exe"
    $dockerInstallerUrl = "https://desktop.docker.com/win/main/amd64/Docker%20Desktop%20Installer.exe"

    Write-Host "Downloading Docker Desktop installer..."
    Invoke-WebRequest -Uri $dockerInstallerUrl -OutFile $installerPath -UseBasicParsing

    Write-Host "Installing Docker Desktop (silent)..."
    Start-Process -FilePath $installerPath -ArgumentList "install", "--quiet", "--accept-license", "--noreboot" -Wait -Verb RunAs

    Write-Host "Waiting for Docker Desktop to start (up to 90s)..."
    $maxWait = 90
    $waited = 0
    while ($waited -lt $maxWait) {
        Start-Sleep -Seconds 5
        $waited += 5
        try {
            docker info 2>$null | Out-Null
            if ($LASTEXITCODE -eq 0) { $dockerOk = $true; break }
        } catch {}
    }
    if (-not $dockerOk) {
        Write-Warn "Docker did not become ready in time. Start Docker Desktop manually, then run this script again."
        exit 1
    }
}
if (-not $dockerOk) {
    $clientOk = $false
    try { docker version 2>$null | Out-Null; if ($LASTEXITCODE -eq 0) { $clientOk = $true } } catch {}
    if ($clientOk) {
        Write-Host "Docker client found but the daemon is not running. Start Docker Desktop from the Start menu, wait until it is ready, then run this script again." -ForegroundColor Red
    } else {
        Write-Host "Docker is not available. Install Docker Desktop or run without -SkipDockerInstall." -ForegroundColor Red
    }
    exit 1
}
Write-Ok "Docker is ready."

# ---------- Step 2: Clone or pull repo ----------
Write-Step "Step 2: Clone or pull repo"

if (Test-Path (Join-Path $RepoRoot ".git")) {
    Write-Host "Repo already exists at $RepoRoot. Pulling..."
    Push-Location $RepoRoot
    git pull
    if ($LASTEXITCODE -ne 0) { Write-Warn "git pull had issues; continuing." }
    Pop-Location
} else {
    if (-not (Get-Command git -ErrorAction SilentlyContinue)) {
        Write-Host "Git is not on PATH. Install Git for Windows or clone the repo manually." -ForegroundColor Red
        exit 1
    }
    Write-Host "Cloning $RepoUrl into $InstallParent ..."
    Push-Location $InstallParent
    git clone $RepoUrl
    Pop-Location
    if (-not (Test-Path $RepoRoot)) {
        Write-Host "Clone failed or repo is not at $RepoRoot." -ForegroundColor Red
        exit 1
    }
}
Write-Ok "Repo ready at $RepoRoot"

# ---------- Step 3: Create .env with generated secrets ----------
Write-Step "Step 3: Create .env"

$envModelPath = Join-Path $RepoRoot ".env.model"
$envPath = Join-Path $RepoRoot ".env"

if (-not (Test-Path $envModelPath)) {
    Write-Host ".env.model not found at $envModelPath" -ForegroundColor Red
    exit 1
}

if (Test-Path $envPath) {
    Write-Warn "Existing .env found; keeping it (passwords unchanged). Delete .env to regenerate secrets."
} else {
    $content = Get-Content $envModelPath -Raw

    function New-RandomBase64 {
        $bytes = New-Object byte[] 32
        [System.Security.Cryptography.RNGCryptoServiceProvider]::Create().GetBytes($bytes)
        [Convert]::ToBase64String($bytes) -replace '\+', '-' -replace '/', '_'
    }

    $postgresPassword = New-RandomBase64
    $postgresAdminPassword = New-RandomBase64
    $irisSecretKey = New-RandomBase64
    $irisSalt = New-RandomBase64
    $irisAdmPassword = New-RandomBase64

    $content = $content -replace 'POSTGRES_PASSWORD=__MUST_BE_CHANGED__', "POSTGRES_PASSWORD=$postgresPassword"
    $content = $content -replace 'POSTGRES_ADMIN_PASSWORD=__MUST_BE_CHANGED__', "POSTGRES_ADMIN_PASSWORD=$postgresAdminPassword"
    $content = $content -replace 'IRIS_SECRET_KEY=AVerySuperSecretKey-SoNotThisOne', "IRIS_SECRET_KEY=$irisSecretKey"
    $content = $content -replace 'IRIS_SECURITY_PASSWORD_SALT=ARandomSalt-NotThisOneEither', "IRIS_SECURITY_PASSWORD_SALT=$irisSalt"
    $content = $content -replace 'SERVER_NAME=iris.app.dev', 'SERVER_NAME=localhost'
    $content = $content -replace '#IRIS_ADM_PASSWORD=MySuperAdminPassword!', "IRIS_ADM_PASSWORD=$irisAdmPassword"

    Set-Content -Path $envPath -Value $content -NoNewline

    $passwordFilePath = Join-Path $RepoRoot "iris-admin-password.txt"
    Set-Content -Path $passwordFilePath -Value $irisAdmPassword
    Write-Ok ".env created; admin password saved to iris-admin-password.txt"
    $script:AdminPassword = $irisAdmPassword
}

# If we skipped overwrite, we don't have admin password in variable; try to read from file
if (-not $script:AdminPassword -and (Test-Path (Join-Path $RepoRoot "iris-admin-password.txt"))) {
    $script:AdminPassword = Get-Content (Join-Path $RepoRoot "iris-admin-password.txt") -Raw
}

# ---------- Step 4: Docker Compose ----------
Write-Step "Step 4: Deploy with Docker Compose"

Push-Location $RepoRoot
Write-Host "Pulling images..."
docker compose pull
if ($LASTEXITCODE -ne 0) {
    Write-Host "docker compose pull failed." -ForegroundColor Red
    Pop-Location
    exit 1
}
Write-Host "Starting stack (detached)..."
docker compose up -d
if ($LASTEXITCODE -ne 0) {
    Write-Host "docker compose up failed." -ForegroundColor Red
    Pop-Location
    exit 1
}
Pop-Location

# Optional: wait for HTTPS to respond
Write-Host "Waiting for IRIS to respond (up to 60s)..."
$maxWait = 60
$waited = 0
$ready = $false
while ($waited -lt $maxWait) {
    Start-Sleep -Seconds 5
    $waited += 5
    try {
        $r = Invoke-WebRequest -Uri "https://localhost" -SkipCertificateCheck -UseBasicParsing -TimeoutSec 5 -ErrorAction SilentlyContinue
        if ($r.StatusCode -in 200, 302) { $ready = $true; break }
    } catch {}
}
if (-not $ready) { Write-Warn "HTTPS did not respond in time; IRIS may still be starting." }

# ---------- Step 5: Output ----------
Write-Step "Done"
Write-Ok "IRIS is available at: https://localhost"
Write-Host "Admin username: administrator" -ForegroundColor White
if ($script:AdminPassword) {
    Write-Host "Admin password: $($script:AdminPassword)" -ForegroundColor White
    Write-Host "Password also saved to: $RepoRoot\iris-admin-password.txt (delete after saving elsewhere)." -ForegroundColor Yellow
} else {
    Write-Host "Admin password: see iris-admin-password.txt in repo root, or app container logs (WARNING :: post_init :: create_safe_admin :: >>>)." -ForegroundColor Yellow
}
Write-Host "`nFirst visit: accept the certificate warning (Advanced -> Proceed to localhost)." -ForegroundColor Gray
