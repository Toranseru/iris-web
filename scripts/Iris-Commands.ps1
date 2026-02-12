<#
.SYNOPSIS
  DFIR-IRIS helper commands for PowerShell. Loaded by Install-IRIS.ps1 into your profile.
.DESCRIPTION
  Provides: iris-start, iris-stop, iris-restart, iris-status, iris-logs, iris-shell, iris-update, iris-backup, iris-help.
  Uses the repo where this script lives (parent of scripts folder). Docker runs on Windows (Docker Desktop).
#>

$ErrorActionPreference = "Stop"
$script:IrisDir = Split-Path $PSScriptRoot -Parent
$script:DockerBinPath = "C:\Program Files\Docker\Docker\resources\bin"
if (Test-Path $script:DockerBinPath) { $env:PATH = "$script:DockerBinPath;$env:PATH" }

function _Iris-Compose {
    Push-Location $script:IrisDir
    try {
        & docker compose @args
    } finally {
        Pop-Location
    }
}

function iris-start {
    <# .SYNOPSIS  Start Docker Desktop (if needed) and the IRIS stack. #>
    Write-Host "[*] Starting DFIR-IRIS..." -ForegroundColor Cyan
    $dockerExePath = Join-Path $script:DockerBinPath "docker.exe"
    $dockerDesktopExe = "C:\Program Files\Docker\Docker\Docker Desktop.exe"
    if (Test-Path $dockerExePath) {
        & $dockerExePath info 2>$null | Out-Null
        if ($LASTEXITCODE -ne 0 -and (Test-Path $dockerDesktopExe)) {
            Write-Host "[*] Starting Docker Desktop..." -ForegroundColor Yellow
            Start-Process -FilePath $dockerDesktopExe -WindowStyle Hidden
            $waited = 0
            while ($waited -lt 90) {
                Start-Sleep -Seconds 5
                $waited += 5
                & $dockerExePath info 2>$null | Out-Null
                if ($LASTEXITCODE -eq 0) { break }
                Write-Host "." -NoNewline -ForegroundColor Gray
            }
            Write-Host ""
        }
    }
    _Iris-Compose up -d
    if ($LASTEXITCODE -eq 0) { Write-Host "[+] IRIS stack started. https://localhost" -ForegroundColor Green }
    else { Write-Host "[X] Failed to start." -ForegroundColor Red }
}

function iris-stop {
    <# .SYNOPSIS  Stop the IRIS stack (data preserved). #>
    Write-Host "[-] Shutting down DFIR-IRIS stack..." -ForegroundColor Yellow
    try {
        _Iris-Compose down
        Write-Host "[+] Containers stopped. Data preserved." -ForegroundColor Green
    } catch {
        Write-Host "[X] Error stopping IRIS: $_" -ForegroundColor Red
    }
}

function iris-restart {
    <# .SYNOPSIS  Restart IRIS containers. #>
    Write-Host "[*] Restarting DFIR-IRIS services..." -ForegroundColor Cyan
    try {
        _Iris-Compose restart
        Write-Host "[+] Restart complete." -ForegroundColor Green
    } catch {
        Write-Host "[X] Error: $_" -ForegroundColor Red
    }
}

function iris-status {
    <# .SYNOPSIS  Show IRIS container status. #>
    Write-Host "[*] DFIR-IRIS System Status" -ForegroundColor Cyan
    Write-Host "---------------------------" -ForegroundColor Gray
    _Iris-Compose ps
}

function iris-logs {
    <# .SYNOPSIS  Tail IRIS logs. Default service: app. #>
    param([string]$Service = "app")
    Write-Host "[*] Tailing logs for service: $Service (Ctrl+C to exit)" -ForegroundColor Cyan
    _Iris-Compose logs -f --tail=50 $Service
}

function iris-shell {
    <# .SYNOPSIS  Open a shell in the IRIS app container. #>
    Write-Host "[*] Entering IRIS App Container Shell..." -ForegroundColor Cyan
    Write-Host "    Type 'exit' to return to Windows." -ForegroundColor Gray
    _Iris-Compose exec app /bin/sh
}

function iris-update {
    <# .SYNOPSIS  Pull repo, pull images, and recreate containers. #>
    Write-Host "[-] Updating DFIR-IRIS..." -ForegroundColor Yellow
    Write-Host "[1/3] Pulling git repository..." -ForegroundColor Cyan
    Push-Location $script:IrisDir
    try {
        git pull
        Write-Host "[2/3] Pulling Docker images..." -ForegroundColor Cyan
        docker compose pull
        Write-Host "[3/3] Applying updates..." -ForegroundColor Cyan
        docker compose up -d
        Write-Host "[+] Update complete." -ForegroundColor Green
    } finally {
        Pop-Location
    }
}

function iris-backup {
    <# .SYNOPSIS  Backup IRIS database to a timestamped .sql file. #>
    $BackupDir = "C:\Backups\Iris"
    if (!(Test-Path $BackupDir)) { New-Item -ItemType Directory -Force -Path $BackupDir | Out-Null }
    $DateStr = Get-Date -Format "yyyy-MM-dd_HHmm"
    $FileName = Join-Path $BackupDir "iris_db_$DateStr.sql"
    Write-Host "[*] Starting database backup..." -ForegroundColor Cyan
    try {
        _Iris-Compose exec -T db pg_dump -U postgres iris_db | Out-File -FilePath $FileName -Encoding utf8
        if (Test-Path $FileName) {
            $Size = (Get-Item $FileName).Length / 1KB
            Write-Host "[+] Backup saved: $FileName ($([math]::Round($Size, 2)) KB)" -ForegroundColor Green
        } else {
            Write-Host "[!] Backup file was not created." -ForegroundColor Red
        }
    } catch {
        Write-Host "[X] Backup failed: $_" -ForegroundColor Red
    }
}

function iris-help {
    <# .SYNOPSIS  Show IRIS console command reference. #>
    Write-Host "`n[?] DFIR-IRIS Console Commands" -ForegroundColor Yellow
    Write-Host "    iris-start   : Start Docker (if needed) and IRIS stack" -ForegroundColor White
    Write-Host "    iris-stop    : Stop IRIS stack (data preserved)" -ForegroundColor White
    Write-Host "    iris-restart : Restart IRIS containers" -ForegroundColor White
    Write-Host "    iris-status  : Container status" -ForegroundColor White
    Write-Host "    iris-logs    : Tail logs (default: app); e.g. iris-logs db" -ForegroundColor White
    Write-Host "    iris-shell   : Shell into app container" -ForegroundColor White
    Write-Host "    iris-update  : git pull + docker compose pull + up -d" -ForegroundColor White
    Write-Host "    iris-backup  : Backup DB to C:\Backups\Iris" -ForegroundColor White
    Write-Host "    iris-help    : Show this help`n" -ForegroundColor Gray
}

# Optional: show help once when profile loads (quiet load)
# iris-help
