<#
.SYNOPSIS
  Prepares the machine for end-to-end testing of Install-IRIS.ps1 (WSL + Docker install, reboot/resume, clone, deploy).
.DESCRIPTION
  Run as Administrator. Removes WSL distros, disables WSL, uninstalls Docker Desktop, and optionally removes
  the iris-web clone and DB volume. After running, run Install-IRIS.ps1 without -SkipDockerInstall to test
  the full flow (WSL install -> reboot -> resume -> Docker install -> clone -> .env -> deploy).
.NOTES
  Use only on a test machine or VM. This script modifies system state.
#>

#Requires -RunAsAdministrator

param(
    [switch]$RemoveWSL,
    [switch]$RemoveDocker,
    [switch]$RemoveIrisClone,
    [switch]$Force
)

$ErrorActionPreference = "Stop"

function Write-Step { param([string]$Msg) Write-Host "`n--- $Msg ---" -ForegroundColor Cyan }
function Write-Ok { param([string]$Msg) Write-Host $Msg -ForegroundColor Green }
function Write-Warn { param([string]$Msg) Write-Host $Msg -ForegroundColor Yellow }

if (-not $Force -and -not ($RemoveWSL -or $RemoveDocker -or $RemoveIrisClone)) {
    Write-Host "Specify what to remove: -RemoveWSL, -RemoveDocker, -RemoveIrisClone (or -Force to run all)." -ForegroundColor Yellow
    Write-Host "Example: .\Prepare-E2ETest.ps1 -RemoveWSL -RemoveDocker -RemoveIrisClone -Force" -ForegroundColor Gray
    exit 0
}

if (-not $Force) {
    $confirm = Read-Host "This will remove the selected components. Continue? (y/N)"
    if ($confirm -ne "y" -and $confirm -ne "Y") { exit 0 }
}

# ---------- WSL ----------
if ($RemoveWSL -or $Force) {
    Write-Step "Removing WSL"
    $distros = wsl -l -q 2>$null
    if ($distros) {
        foreach ($d in $distros) {
            $d = $d.Trim()
            if ($d) {
                Write-Host "Unregistering WSL distro: $d"
                wsl --unregister $d 2>$null
            }
        }
    }
    Write-Host "Disabling Windows Subsystem for Linux feature..."
    dism /online /disable-feature /featurename:Microsoft-Windows-Subsystem-Linux /norestart 2>$null
    Write-Ok "WSL disabled. Reboot may be required for full removal."
}

# ---------- Docker Desktop ----------
if ($RemoveDocker -or $Force) {
    Write-Step "Removing Docker Desktop"
    $docker = Get-AppxPackage -Name "*Docker*" -ErrorAction SilentlyContinue
    if ($docker) {
        foreach ($p in $docker) {
            Write-Host "Removing: $($p.Name)"
            Remove-AppxPackage -Package $p.PackageFullName
        }
    }
    $prog = Get-Package -Name "*Docker*" -ErrorAction SilentlyContinue
    if ($prog) {
        foreach ($p in $prog) {
            Write-Host "Uninstalling: $($p.Name)"
            Uninstall-Package -Name $p.Name -Force -ErrorAction SilentlyContinue
        }
    }
    Write-Host "Attempting winget uninstall Docker.DockerDesktop..."
    winget uninstall --id Docker.DockerDesktop -e --silent 2>$null
    $dPath = "${env:ProgramFiles}\Docker\Docker\Docker Desktop Installer.exe"
    if (Test-Path $dPath) {
        Write-Host "Running Docker Desktop uninstaller..."
        Start-Process -FilePath $dPath -ArgumentList "uninstall", "--quiet" -Wait
    }
    Write-Ok "Docker Desktop removal attempted. Reboot if needed."
}

# ---------- iris-web clone and volume ----------
if ($RemoveIrisClone -or $Force) {
    Write-Step "Removing iris-web clone and DB volume"
    $clonePath = Join-Path $env:USERPROFILE "iris-web"
    if (Test-Path $clonePath) {
        Push-Location $clonePath
        docker compose down 2>$null
        docker volume rm iris-web_db_data 2>$null
        Pop-Location
        Remove-Item -Recurse -Force $clonePath -ErrorAction SilentlyContinue
        Write-Ok "Removed $clonePath and iris-web_db_data volume."
    } else {
        Write-Warn "Clone not found at $clonePath."
    }
}

# ---------- Next step ----------
Write-Step "Next step"
Write-Host "Run Install-IRIS.ps1 without -SkipDockerInstall to test end-to-end:" -ForegroundColor White
Write-Host "  cd `"$PSScriptRoot`"" -ForegroundColor Gray
Write-Host "  .\Install-IRIS.ps1" -ForegroundColor Gray
Write-Host "`nIf WSL or Docker was removed, a reboot may be required before running the install script." -ForegroundColor Yellow
Write-Host "The install script will schedule a resume at next logon and reboot if needed." -ForegroundColor Gray
