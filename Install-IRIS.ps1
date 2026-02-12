<#
.SYNOPSIS
  One-click deploy: requires Docker Desktop (WSL2 backend), clones repo, generates .env, deploys IRIS on localhost.
.DESCRIPTION
  Requires Docker Desktop to be installed and running. Does not install WSL or Docker.
  Clones or pulls the repo, creates .env with generated secrets and SERVER_NAME=localhost, then runs docker compose up.
  IRIS will be available at https://localhost. Admin password is printed in the console.
  First visit: accept the dev certificate warning (Advanced -> Proceed to localhost).
.NOTES
  Port 443 must be free. Git is installed via winget if missing; for private repos a credential prompt will appear when cloning.
  When running inside a virtual machine, nested virtualization must be enabled on the VM host (required for Docker/WSL2).
#>

param(
    [string]$InstallParent = $env:USERPROFILE,
    [string]$RepoUrl = "https://github.com/Toranseru/iris-web.git",
    [string]$RepoFolderName = "iris-web"
)

$ErrorActionPreference = "Stop"
Set-ExecutionPolicy -ExecutionPolicy RemoteSigned -Scope Process -Force
$RepoRoot = Join-Path $InstallParent $RepoFolderName

function Write-Step { param([string]$Msg) Write-Host "`n--- $Msg ---" -ForegroundColor Cyan }
function Write-Ok { param([string]$Msg) Write-Host $Msg -ForegroundColor Green }
function Write-Warn { param([string]$Msg) Write-Host $Msg -ForegroundColor Yellow }

# ---------- Step 1: Docker ----------
Write-Step "Step 1: Docker"

# Ensure we see Docker on PATH: child process (e.g. powershell -File) may not have User PATH; prepend Machine + User + known Docker paths.
$machinePath = [Environment]::GetEnvironmentVariable("Path", "Machine")
$userPath = [Environment]::GetEnvironmentVariable("Path", "User")
if ($machinePath) { $env:PATH = "$machinePath;$env:PATH" }
if ($userPath) { $env:PATH = "$userPath;$env:PATH" }
# Use literal 64-bit path so we find Docker even when child process is 32-bit ($env:ProgramFiles would be (x86)).
$dockerBinPath = "C:\Program Files\Docker\Docker\resources\bin"
if (Test-Path $dockerBinPath) { $env:PATH = "$dockerBinPath;$env:PATH" }

Write-Host "Checking Docker daemon..."
$dockerOk = $false
$dockerExePath = Join-Path $dockerBinPath "docker.exe"
if (Test-Path $dockerExePath) {
    try {
        & $dockerExePath info 2>$null
        if ($LASTEXITCODE -eq 0) { $dockerOk = $true }
    } catch {}
}

# If daemon not responding, check if Docker client is installed (avoid re-download). docker.exe at known path = client installed (docker version can exit non-zero when daemon is down).
$dockerClientExists = $false
if (-not $dockerOk -and (Test-Path $dockerExePath)) { $dockerClientExists = $true }
if (-not $dockerOk -and $dockerClientExists) {
    $dockerDesktopExe = "C:\Program Files\Docker\Docker\Docker Desktop.exe"
    if (Test-Path $dockerDesktopExe) {
        Write-Host "Docker is installed but the daemon is not running. Starting Docker Desktop..." -ForegroundColor Yellow
        Start-Process -FilePath $dockerDesktopExe -WindowStyle Hidden
        Write-Host "Waiting for Docker daemon to start (up to 90s)..."
        $maxWait = 90
        $waited = 0
        while ($waited -lt $maxWait) {
            Start-Sleep -Seconds 5
            $waited += 5
            try {
                & $dockerExePath info 2>$null
                if ($LASTEXITCODE -eq 0) { $dockerOk = $true; break }
            } catch {}
        }
        if (-not $dockerOk) {
            Write-Host "Docker did not become ready in time." -ForegroundColor Yellow
            Write-Host "Start Docker Desktop from the Start menu, wait until it is ready (whale icon in tray), then run this script again." -ForegroundColor Yellow
            exit 1
        }
    } else {
        Write-Host "Docker is installed but the daemon is not running." -ForegroundColor Yellow
        Write-Host "Start Docker Desktop from the Start menu, wait until it is ready (whale icon in tray), then run this script again." -ForegroundColor Yellow
        exit 1
    }
}

if (-not $dockerOk) {
    Write-Host "Docker is not available. Install Docker Desktop (with WSL2 backend), start it, then run this script again." -ForegroundColor Red
    exit 1
}
Write-Ok "Docker is ready."

# ---------- Step 2: Clone or pull repo ----------
Write-Step "Step 2: Clone or pull repo"

Write-Host "Checking for existing repo at $RepoRoot ..."
if (Test-Path (Join-Path $RepoRoot ".git")) {
    Write-Host "Repo exists. Pulling latest changes..."
    Push-Location $RepoRoot
    git pull
    if ($LASTEXITCODE -ne 0) { Write-Warn "git pull had issues; continuing." }
    Pop-Location
} else {
    if (-not (Get-Command git -ErrorAction SilentlyContinue)) {
        Write-Host "Git is not on PATH. Installing Git via winget..."
        try {
            winget install --id Git.Git -e --source winget --silent --accept-package-agreements
        } catch {
            Write-Host "winget install failed. Install Git for Windows manually, then run this script again." -ForegroundColor Red
            exit 1
        }
        Write-Warn "Git was installed. Close this window, open a new PowerShell, then run this script again (PATH is updated in new sessions)."
        exit 0
    }
    Write-Host "Cloning repo from $RepoUrl into $InstallParent as $RepoFolderName ..."
    Push-Location $InstallParent
    git clone $RepoUrl $RepoFolderName
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

Write-Host "Checking for .env..."
if (-not (Test-Path $envModelPath)) {
    Write-Host ".env.model not found at $envModelPath" -ForegroundColor Red
    exit 1
}

if (Test-Path $envPath) {
    Write-Warn "Existing .env found; keeping it (passwords unchanged). Delete .env to regenerate secrets."
} else {
    Write-Host "Creating .env from .env.model and generating secrets..."
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

    Write-Ok ".env created."
    $script:AdminPassword = $irisAdmPassword
}

# ---------- Step 4: Docker Compose ----------
Write-Step "Step 4: Deploy with Docker Compose"

Push-Location $RepoRoot
Write-Host "Pulling IRIS container images (nginx, app, db, rabbitmq). This may take several minutes on first run..."
docker compose pull
if ($LASTEXITCODE -ne 0) {
    Write-Host "docker compose pull failed." -ForegroundColor Red
    Pop-Location
    exit 1
}
Write-Host "Starting IRIS containers (app, db, nginx, worker, rabbitmq)..."
docker compose up -d
if ($LASTEXITCODE -ne 0) {
    Write-Host "docker compose up failed." -ForegroundColor Red
    Pop-Location
    exit 1
}
Pop-Location

Write-Host "Checking if IRIS is responding at https://localhost (up to 60s)..."
$maxWait = 60
$waited = 0
$ready = $false
$lastStatusCode = $null
while ($waited -lt $maxWait) {
    Start-Sleep -Seconds 5
    $waited += 5
    try {
        $r = Invoke-WebRequest -Uri "https://localhost" -SkipCertificateCheck -UseBasicParsing -TimeoutSec 5 -ErrorAction SilentlyContinue
        if ($r.StatusCode -in 200, 302) { $ready = $true; $lastStatusCode = $r.StatusCode; break }
        $lastStatusCode = $r.StatusCode
    } catch {
        $lastStatusCode = $null
    }
}
if ($ready) {
    Write-Ok "IRIS responded at https://localhost (HTTP $lastStatusCode)."
} else {
    Write-Warn "HTTPS did not respond in time; IRIS may still be starting."
}

# ---------- Step 5: Output ----------
Write-Step "Done"
Write-Ok "IRIS is available at: https://localhost"
Write-Host "Admin username: administrator" -ForegroundColor White
if ($script:AdminPassword) {
    Write-Host "Admin password: $($script:AdminPassword)" -ForegroundColor White
} else {
    Write-Host "Admin password: see app container logs (WARNING :: post_init :: create_safe_admin :: >>>)." -ForegroundColor Yellow
}
Write-Host "`nFirst visit: accept the certificate warning (Advanced -> Proceed to localhost)." -ForegroundColor Gray
