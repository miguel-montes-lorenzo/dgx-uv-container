#!/usr/bin/env bash
set -Eeuo pipefail

# cache-cleanup-hook.sh
# Deletes contents of the target user's ~/.cache directory.

: "${CLEANUP_TARGET_USER:?CLEANUP_TARGET_USER is required}"
: "${CLEANUP_TARGET_HOME:?CLEANUP_TARGET_HOME is required}"

# Always log to /run/control/log by default (not ~)
LOG_FILE="${CACHE_CLEANUP_LOG_FILE:-/run/control/log/cache-cleanup.log}"

touch "${LOG_FILE}" 2>/dev/null || true

log() {
  local msg="$1"
  printf '%s\n' "${msg}" >>"${LOG_FILE}" 2>/dev/null || true
}

ts() { date -Is; }

# Safety checks (avoid deleting wrong paths)
if [[ -z "${CLEANUP_TARGET_HOME}" || "${CLEANUP_TARGET_HOME}" == "/" ]]; then
  log "$(ts) [ERROR] Refusing to run: CLEANUP_TARGET_HOME='${CLEANUP_TARGET_HOME}'"
  exit 1
fi

cache_dir="${CLEANUP_TARGET_HOME}/.cache"
if [[ ! -d "${cache_dir}" ]]; then
  log "$(ts) [INFO] No cache dir: ${cache_dir} (nothing to do)"
  exit 0
fi

log "$(ts) [INFO] Cleaning cache for user='${CLEANUP_TARGET_USER}' dir='${cache_dir}'"

# Depth-first deletion with find -delete
# Note: if there are permission issues, find will fail.
if find "${cache_dir}" -mindepth 1 -delete; then
  log "$(ts) [INFO] Cache cleaned successfully"
else
  log "$(ts) [ERROR] Cache cleanup failed (find returned non-zero)"
  exit 1
fi
