#!/usr/bin/env bash
set -euo pipefail

VARS_FILE="./variables.sh"
STATE_DIR=".git"
STATE_FILE="${STATE_DIR}/.persistent_uv_cache_original_line"

die() { printf 'error: %s\n' "$*" >&2; exit 1; }

require_repo() {
  git rev-parse --git-dir >/dev/null 2>&1 || die "not a git repository"
}

require_vars_file() {
  [[ -f "$VARS_FILE" ]] || die "missing ${VARS_FILE}"
}

save_original_line() {
  # Save the first matching line exactly as-is.
  local line=""
  line="$(LC_ALL=C grep -m 1 -E '^[[:space:]]*PERSISTENT_UV_CACHE[[:space:]]*=' "$VARS_FILE" || true)"
  [[ -n "$line" ]] || die "PERSISTENT_UV_CACHE not found in ${VARS_FILE}"
  printf '%s\n' "$line" >"$STATE_FILE"
}

force_false_in_file() {
  # Replace only the value, preserving:
  # - leading spaces
  # - spaces around '='
  # - trailing inline comment if present (starts with '#')
  #
  # It will rewrite the first occurrence only.
  local tmp
  tmp="$(mktemp)"

  awk '
    BEGIN { done=0 }
    done==0 {
      # Match: [spaces]PERSISTENT_UV_CACHE[spaces]=[spaces]<value><spaces><optional #comment>
      if (match($0, /^[[:space:]]*PERSISTENT_UV_CACHE[[:space:]]*=[[:space:]]*[^#[:space:]]+([[:space:]]*#.*)?$/, m)) {
        # Capture the trailing comment part (if any) by re-matching for (#.*)
        comment=""
        if (match($0, /#.*$/, c)) {
          comment=c[0]
          sub(/[[:space:]]*#.*$/, "", $0)
        }
        # Now $0 has LHS + original value (no comment). Replace RHS token with false while keeping LHS spacing.
        # Split on '=' while preserving spaces around it by using a regex approach:
        if (match($0, /^([[:space:]]*PERSISTENT_UV_CACHE[[:space:]]*=[[:space:]]*).*/, p)) {
          printf "%sfalse", p[1]
          if (comment != "") {
            printf "%s", (comment ~ /^[[:space:]]*#/ ? comment : " " comment)
          }
          printf "\n"
          done=1
          next
        }
      }
    }
    { print }
  ' "$VARS_FILE" >"$tmp"

  mv "$tmp" "$VARS_FILE"
}

restore_original_line() {
  [[ -f "$STATE_FILE" ]] || die "missing state file ${STATE_FILE} (nothing to restore?)"
  local original
  original="$(cat "$STATE_FILE")"

  # Restore by replacing the first matching PERSISTENT_UV_CACHE=... line with the saved line.
  local tmp
  tmp="$(mktemp)"

  awk -v orig="$original" '
    BEGIN { done=0 }
    done==0 && $0 ~ /^[[:space:]]*PERSISTENT_UV_CACHE[[:space:]]*=/ {
      print orig
      done=1
      next
    }
    { print }
  ' "$VARS_FILE" >"$tmp"

  mv "$tmp" "$VARS_FILE"
  rm -f "$STATE_FILE"
}

stage_vars_file() {
  git add -- "$VARS_FILE" >/dev/null 2>&1 || true
}

cmd="${1:-}"
require_repo
require_vars_file

case "$cmd" in
  force)
    mkdir -p "$STATE_DIR"
    save_original_line
    force_false_in_file
    stage_vars_file
    ;;
  restore)
    restore_original_line
    ;;
  *)
    die "usage: $0 {force|restore}"
    ;;
esac
