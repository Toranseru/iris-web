# IRIS one-click install – test run

Use this to prepare and run a clean test of [Install-IRIS.ps1](Install-IRIS.ps1).

## End-to-end test (WSL + Docker + reboot/resume)

To test the full flow (WSL install, reboot, resume, Docker install, clone, deploy), use [Prepare-E2ETest.ps1](Prepare-E2ETest.ps1) first. Run as Administrator:

```powershell
cd d:\DockerWorkspace\iris-web-master-live\iris-web-master
.\Prepare-E2ETest.ps1 -RemoveWSL -RemoveDocker -RemoveIrisClone -Force
```

Then run the install script **without** `-SkipDockerInstall`:

```powershell
.\Install-IRIS.ps1
```

The script will install WSL (or Docker), schedule a one-time resume at next logon, and reboot. After you log back in, it will continue automatically. Use only on a test machine or VM.

## Prerequisites

- **Docker Desktop** running (or run the script without `-SkipDockerInstall` and let it install).
- **PowerShell** (interactive window; for private repo, a credential prompt will appear when cloning).
- **Port 443** free.

## Optional: clean state for a fresh test

If you want a **first-run** test (new `.env`, new DB), do this **before** running the script:

1. **Stop and remove the existing clone and its Docker resources** (only if you already have a clone from a previous run):

   ```powershell
   cd $env:USERPROFILE
   if (Test-Path "iris-web") {
       Push-Location iris-web
       docker compose down
       docker volume rm iris-web_db_data 2>$null
       Pop-Location
       Remove-Item -Recurse -Force iris-web
   }
   ```

   This removes `%USERPROFILE%\iris-web` (repo, `.env`, and DB volume) so the next run is a full first run.

2. If you **only** want to reset the DB but keep the repo and code: from the clone folder run `docker compose down`, then `docker volume rm iris-web_db_data`, then delete `.env` in the clone. The script will then create a new `.env` on next run; run the script again or run `docker compose up -d` from the clone.

## Run the script

From the **live repo** (where `Install-IRIS.ps1` lives):

```powershell
cd d:\DockerWorkspace\iris-web-master-live\iris-web-master
.\Install-IRIS.ps1 -SkipDockerInstall
```

- **First run:** Clones into `%USERPROFILE%\iris-web`, creates `.env`, starts stack. For a **private** repo, a GitHub credential prompt will appear when `git clone` runs.
- **Re-run:** Pulls latest, keeps existing `.env`, runs `docker compose up -d`.

Optional parameters:

- `-InstallParent "C:\Projects"` – clone into `C:\Projects\iris-web`.
- `-RepoFolderName "my-iris"` – clone into `%USERPROFILE%\my-iris` (or `$InstallParent\my-iris`).
- `-RepoUrl "https://github.com/YourOrg/private-iris-web.git"` – use a private repo (credential prompt when cloning).

## Verify

1. **Script output:** “IRIS is available at: https://localhost” and admin password (and path to `iris-admin-password.txt`).
2. **Browser:** Open https://localhost, accept the certificate warning, log in with **administrator** and the printed password.
3. **Containers:** From the clone folder, `docker compose ps` – all services should be Up.

## If the app fails (e.g. “page unavailable”)

- **Password mismatch:** If you had an old `.env` and an old DB, the DB was created with different passwords. Do the “clean state” steps above (remove clone + volume, or at least volume + `.env`), then run the script again.
- **Logs:** From the clone folder: `docker compose logs app --tail 100` to see errors (e.g. “password authentication failed for user postgres”).
