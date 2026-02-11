#!/usr/bin/env bash
set -euo pipefail

VARS_FILE="./variables.sh"
STATE_DIR=".git"

STATE_FILE_COMMIT="${STATE_DIR}/.vars_original_lines_for_commit"
STATE_FILE_DESIRED="${STATE_DIR}/.vars_desired_values"

die() { printf 'error: %s\n' "$*" >&2; exit 1; }

require_repo() {
  git rev-parse --git-dir >/dev/null 2>&1 || die "not a git repository"
}

require_vars_file() {
  [[ -f "$VARS_FILE" ]] || die "missing ${VARS_FILE}"
}

_key_list() {
  printf '%s ' \
    "CACHE_CLEANUP_TIME" \
    "CACHE_CLEANUP_STRATEGY" \
    "PERSISTENT_UV_CACHE"
}

_fixed_value_for_key() {
  local key="${1:?missing key}"
  case "$key" in
    CACHE_CLEANUP_TIME) printf '%s' "86400" ;;
    CACHE_CLEANUP_STRATEGY) printf '%s' "1" ;;
    PERSISTENT_UV_CACHE) printf '%s' "true" ;;
    *) die "unknown key: $key" ;;
  esac
}

_save_original_lines_for_commit() {
  : >"$STATE_FILE_COMMIT"
  local key=""
  for key in $(_key_list); do
    local line=""
    line="$(
      LC_ALL=C grep -m 1 -E "^[[:space:]]*${key}[[:space:]]*=" "$VARS_FILE" || true
    )"
    [[ -n "$line" ]] || die "${key} not found in ${VARS_FILE}"
    printf '%s\t%s\n' "$key" "$line" >>"$STATE_FILE_COMMIT"
  done
}

_restore_original_lines_for_commit() {
  [[ -f "$STATE_FILE_COMMIT" ]] || die "missing state file ${STATE_FILE_COMMIT}"

  local tmp=""
  tmp="$(mktemp)"

  awk -v state_file="$STATE_FILE_COMMIT" '
    BEGIN {
      FS="\t"
      while ((getline < state_file) > 0) {
        key=$1
        sub(/^[^\t]*\t/, "", $0)
        orig[key]=$0
      }
      close(state_file)
    }
    {
      printed=0
      for (k in orig) {
        if (!(k in done) && $0 ~ ("^[[:space:]]*" k "[[:space:]]*=")) {
          print orig[k]
          done[k]=1
          printed=1
          break
        }
      }
      if (!printed) print
    }
  ' "$VARS_FILE" >"$tmp"

  mv "$tmp" "$VARS_FILE"
  rm -f "$STATE_FILE_COMMIT"
}

_force_value_in_file() {
  local key="${1:?missing key}"
  local value="${2:?missing value}"

  local tmp=""
  tmp="$(mktemp)"

  awk -v k="$key" -v v="$value" '
    BEGIN { done=0 }
    done==0 {
      if (match($0, "^[[:space:]]*" k "[[:space:]]*=[[:space:]]*[^#[:space:]]+([[:space:]]*#.*)?$", m)) {
        comment=""
        if (match($0, /#.*$/, c)) {
          comment=c[0]
          sub(/[[:space:]]*#.*$/, "", $0)
        }
        if (match($0, "^([[:space:]]*" k "[[:space:]]*=[[:space:]]*).*$", p)) {
          printf "%s%s", p[1], v
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

_force_fixed_values_for_commit() {
  local key=""
  for key in $(_key_list); do
    local value=""
    value="$(_fixed_value_for_key "$key")"
    _force_value_in_file "$key" "$value"
  done
}

_stage_vars_file() {
  git add -- "$VARS_FILE" >/dev/null 2>&1 || true
}

_read_current_value_from_file() {
  local key="${1:?missing key}"
  local val=""
  val="$(
    awk -v k="$key" '
      $0 ~ ("^[[:space:]]*" k "[[:space:]]*=") {
        line=$0
        sub(/#.*$/, "", line)
        sub("^[[:space:]]*" k "[[:space:]]*=[[:space:]]*", "", line)
        sub(/[[:space:]]+$/, "", line)
        print line
        exit 0
      }
    ' "$VARS_FILE"
  )"
  [[ -n "$val" ]] || die "could not parse value for ${key} in ${VARS_FILE}"
  printf '%s' "$val"
}

_desired_set_if_missing() {
  mkdir -p "$STATE_DIR"
  if [[ -f "$STATE_FILE_DESIRED" ]]; then
    return 0
  fi

  : >"$STATE_FILE_DESIRED"
  local key=""
  for key in $(_key_list); do
    local cur=""
    cur="$(_read_current_value_from_file "$key")"
    printf '%s=%s\n' "$key" "$cur" >>"$STATE_FILE_DESIRED"
  done
}

_desired_update_from_current_file() {
  mkdir -p "$STATE_DIR"
  : >"$STATE_FILE_DESIRED"
  local key=""
  for key in $(_key_list); do
    local cur=""
    cur="$(_read_current_value_from_file "$key")"
    printf '%s=%s\n' "$key" "$cur" >>"$STATE_FILE_DESIRED"
  done
}

_apply_desired_values() {
  _desired_set_if_missing

  local key=""
  local value=""
  while IFS='=' read -r key value; do
    [[ -n "$key" ]] || continue
    _force_value_in_file "$key" "$value"
  done <"$STATE_FILE_DESIRED"
}

cmd="${1:-}"
require_repo
require_vars_file

case "$cmd" in
  force)
    mkdir -p "$STATE_DIR"
    _save_original_lines_for_commit
    _force_fixed_values_for_commit
    _stage_vars_file
    ;;
  restore)
    _restore_original_lines_for_commit
    _stage_vars_file
    _desired_update_from_current_file
    ;;
  protect)
    _apply_desired_values
    ;;
  remember)
    _desired_update_from_current_file
    ;;
  *)
    die "usage: $0 {force|restore|protect|remember}"
    ;;
esac
