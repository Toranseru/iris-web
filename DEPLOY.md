# IRIS deployment and configuration (live fork)

This document covers deploying and configuring DFIR IRIS in this workspace and pushing updates to the fork at **https://github.com/Toranseru/iris-web**.

## One-click install (Windows)

A single PowerShell script installs Docker (with WSL2), clones this repo, generates `.env` with secrets, and deploys IRIS on **https://localhost**.

- **Run as Administrator.** WSL or Docker install may require a reboot; if so, run the script again after reboot.
- **Requirements:** Port 443 free. Git is installed via winget if missing; for private repos a credential prompt appears when cloning.
- **First visit:** Accept the dev certificate warning (Advanced → Proceed to localhost).
- **Test run:** See [TEST.md](TEST.md) for clean-state steps and verification.

```powershell
# From the repo root (where Install-IRIS.ps1 lives):
.\Install-IRIS.ps1
# Or: -InstallParent "C:\Projects"  -RepoFolderName "iris-web"  -RepoUrl "https://github.com/..."
# Skip Docker install if already installed:
# .\Install-IRIS.ps1 -SkipDockerInstall
# Existing .env is never overwritten; delete .env to regenerate secrets.
```

After run, the admin password is printed and saved to `iris-admin-password.txt` in the repo root (delete after saving elsewhere). Username: **administrator**.

## Directory layout

- **Live workspace (this repo):** `iris-web-master-live/iris-web-master/` — your fork workspace; deploy and edit here.
- **Original (comparison):** `iris-web-master-original/iris-web-master/` — reference only; do not deploy from here.

## 1. Pre-deploy configuration

1. **Edit `.env`** (already created from `.env.model`). Before first run, set:
   - `POSTGRES_PASSWORD` — PostgreSQL password for IRIS user (replace `__MUST_BE_CHANGED__`).
   - `POSTGRES_ADMIN_PASSWORD` — PostgreSQL admin/migration user password (replace `__MUST_BE_CHANGED__`).
   - `IRIS_SECRET_KEY` — strong random secret for Flask (replace default).
   - `IRIS_SECURITY_PASSWORD_SALT` — strong random salt (replace default).
   - Optional: `IRIS_ADM_PASSWORD` — uncomment and set to fix the initial admin password instead of using the one printed in logs.
   - Optional: `SERVER_NAME` — set to your hostname if not using `iris.app.dev`.

2. **Certificates:** Dev certs are under `certificates/`. For production, use your own TLS certs and set `KEY_FILENAME` / `CERT_FILENAME` in `.env` (see [CONFIGURATION.md](CONFIGURATION.md)).

## 2. Deploy with Docker

From this directory (`iris-web-master`):

```bash
# Pull images (default: v2.4.20)
docker compose pull

# Start IRIS (HTTPS on port 443)
docker compose up
```

- **URL:** `https://<your_host_or_ip>` (or `https://localhost` if bound locally).
- **First-run admin password:** Shown once in the `app` container logs. Search for `WARNING :: post_init :: create_safe_admin :: >>>` in the `webapp`/`app` service logs. Alternatively, set `IRIS_ADM_PASSWORD` in `.env` before first start.

Services: `app` (web + API), `db` (PostgreSQL), `rabbitmq`, `worker`, `nginx`.

## 3. Post-deploy

- **Modules:** Manage > Modules in the UI to enable/configure modules (MISP, VT, etc.).
- **Backups:** Back up the `db_data` volume and any mounted data; do not expose the UI directly to the internet (use a private/VPN network).

## 4. Pushing this repo to GitHub (Toranseru/iris-web)

This workspace was not a git clone. To turn it into a repo and push to your fork:

```bash
cd d:\DockerWorkspace\iris-web-master-live\iris-web-master

# Initialize git (if not already)
git init

# Add the fork as remote (replace with SSH URL if you use SSH)
git remote add origin https://github.com/Toranseru/iris-web.git

# If the remote already exists (e.g. as dfir-iris upstream), set origin to your fork:
# git remote set-url origin https://github.com/Toranseru/iris-web.git

# Stage and commit your changes (e.g. after config/deploy tweaks)
git add .
git status
git commit -m "Your message"

# Push (first time: create branch and set upstream)
git branch -M master
git push -u origin master
```

- **Note:** `.env` is ignored by `.gitignore` (`.env*`), so secrets are not committed.
- To track upstream (dfir-iris/iris-web) for merges: `git remote add upstream https://github.com/dfir-iris/iris-web.git`, then `git fetch upstream` and merge as needed.

## References

- [README.md](README.md) — project overview and quick start.
- [CONFIGURATION.md](CONFIGURATION.md) — all configuration options (env, Key Vault, config.ini).
- [Official docs](https://docs.dfir-iris.org) — operations, upgrades, API.
