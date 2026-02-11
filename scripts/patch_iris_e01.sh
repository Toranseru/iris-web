#!/usr/bin/env bash
#
# Patch an existing iris-web deployment with iris_e01_processor and HE_VT_KEY.
#
# Usage: ./patch_iris_e01.sh [TARGET_PATH]
# Default TARGET_PATH: /home/analyst/iris-web
#
# Required: These 4 files must be in the same directory as this script:
#   __init__.py
#   IrisE01ProcessorConfig.py
#   IrisE01Processor.py
#   import_timeline_from_csv.py
#
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TARGET_ROOT="${1:-/home/analyst/iris-web}"

readonly FILES=(
  "__init__.py:source/iris_e01_processor/__init__.py"
  "IrisE01ProcessorConfig.py:source/iris_e01_processor/IrisE01ProcessorConfig.py"
  "IrisE01Processor.py:source/iris_e01_processor/IrisE01Processor.py"
  "import_timeline_from_csv.py:source/tools/import_timeline_from_csv.py"
)

readonly VOLUME_LINE="      - ./source/iris_e01_processor:/iriswebapp/iris_e01_processor:ro"
readonly ENV_LINE="      - HE_VT_KEY"
COMPOSE_FILE="${TARGET_ROOT}/docker-compose.base.yml"

log()  { printf '  %s\n' "$1"; }
ok()   { printf '  [OK] %s\n' "$1"; }
skip() { printf '  [SKIP] %s\n' "$1"; }
fail() { printf '  [FAIL] %s\n' "$1" >&2; exit 1; }

# --- 1) Check required files exist in script directory ---
log "Checking required files in $SCRIPT_DIR ..."
for entry in "${FILES[@]}"; do
  src="${entry%%:*}"
  if [[ ! -f "$SCRIPT_DIR/$src" ]]; then
    fail "Missing file: $src (must be in same directory as script)"
  fi
done
ok "All 4 required files found."

# --- 2) Validate target directory and compose file ---
if [[ ! -d "$TARGET_ROOT" ]]; then
  fail "Target directory does not exist: $TARGET_ROOT"
fi
if [[ ! -f "$COMPOSE_FILE" ]]; then
  fail "Compose file not found: $COMPOSE_FILE"
fi
log "Target root: $TARGET_ROOT"
echo

# --- 3) Create destination directories and copy files ---
log "Creating directories and copying files..."
for entry in "${FILES[@]}"; do
  src="${entry%%:*}"
  dest_rel="${entry#*:}"
  dest_path="$TARGET_ROOT/$dest_rel"
  dest_dir="$(dirname "$dest_path")"
  mkdir -p "$dest_dir"
  cp -f "$SCRIPT_DIR/$src" "$dest_path"
  ok "Copied $src -> $dest_rel"
done

# --- 4) Patch docker-compose.base.yml (idempotent) ---
log "Patching $COMPOSE_FILE ..."

has_volume() { grep -q 'iris_e01_processor' "$COMPOSE_FILE"; }
has_vt()     { grep -q 'HE_VT_KEY' "$COMPOSE_FILE"; }

# Add volume line after each "      - server_data" (app and worker each have one)
if ! has_volume; then
  awk -v vol="$VOLUME_LINE" '
    /^      - server_data$/ { print; print vol; next }
    { print }
  ' "$COMPOSE_FILE" > "$COMPOSE_FILE.tmp" && mv "$COMPOSE_FILE.tmp" "$COMPOSE_FILE"
  ok "Added E01 module volume to app and worker."
else
  skip "E01 module volume already present."
fi

# Add HE_VT_KEY after each "      - IRIS_SECURITY_PASSWORD_SALT" (app and worker each have one)
if ! has_vt; then
  awk -v envline="$ENV_LINE" '
    /^      - IRIS_SECURITY_PASSWORD_SALT$/ { print; print envline; next }
    { print }
  ' "$COMPOSE_FILE" > "$COMPOSE_FILE.tmp" && mv "$COMPOSE_FILE.tmp" "$COMPOSE_FILE"
  ok "Added HE_VT_KEY to app and worker environment."
else
  skip "HE_VT_KEY already present."
fi

ok "Saved $COMPOSE_FILE"
echo
echo "========================================"
echo " Patch complete"
echo "========================================"
echo
log "Next steps:"
echo "  1. Ensure HE_VT_KEY is set in the environment (e.g. in .env or exported in shell)."
echo "  2. From $TARGET_ROOT run: docker compose up -d --force-recreate app worker"
echo "  3. In IRIS: Manage -> Modules -> Add module -> name: iris_e01_processor"
echo "  4. Configure E01 module; if VT module does not use HE_VT_KEY, set API key in UI."
echo
