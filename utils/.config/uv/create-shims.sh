#!/usr/bin/env bash
# create-shims.sh — robust uv shims for WSL/Linux
# Shims installed to ~/.local/uv-shims:
#   python       -> uv run python (stable resolver)
#   pip          -> uv pip (supports -p/--python)
#   version      -> 2 lines: "uv X.Y.Z" and "Python A.B.C" (or "(none)")
#   venv         -> creates venv + execs a new interactive shell already activated
#   lpin         -> print/set local pin
#   gpin         -> print/set global pin
#   interpreters -> fast, deduped, patch-level names; ⭐ current/exact pin/highest patch
#   uv           -> dispatcher; safe when called with no args
#
# After running:
#   source ~/.bashrc
#   hash -r

# set -euo pipefail
set -uo pipefail

UVSHIM="$HOME/.local/uv-shims"
mkdir -p "$UVSHIM"

# -------------------------
# Helpers (host script)
# -------------------------
_read_global_pin() {
  for c in \
    "${XDG_CONFIG_HOME:-$HOME/.config}/uv/.python-version" \
    "$HOME/.uv/.python-version" \
    "$HOME/.config/uv/python/version"
  do
    [[ -f "$c" ]] && { sed -n '1p' "$c"; return 0; }
  done
  return 1
}

_pick_bin_for_pin() {
  # Given "3.12[.Z]" prefer python3.12 / python312 / python3.12; else python / python3
  local pin="${1:-}" mm cand
  if [[ "$pin" =~ ^([0-9]+)\.([0-9]+) ]]; then
    mm="${BASH_REMATCH[1]}.${BASH_REMATCH[2]}"
    for cand in "python$mm" "python${mm/./}" "python3.${BASH_REMATCH[2]}"; do
      if command -v "$cand" >/dev/null 2>&1; then
        command -v "$cand"; return 0
      fi
    done
  fi
  command -v python  >/dev/null 2>&1 && { command -v python;  return 0; }
  command -v python3 >/dev/null 2>&1 && { command -v python3; return 0; }
  return 1
}

TIMEOUT_BIN="$(command -v timeout 2>/dev/null || true)"
_tmo1() { [[ -n "$TIMEOUT_BIN" ]] && "$TIMEOUT_BIN" 1s "$@" || "$@"; }
_tmo2() { [[ -n "$TIMEOUT_BIN" ]] && "$TIMEOUT_BIN" 2s "$@" || "$@"; }

# -------------------------
# python (via uv run; resolves stable interpreter)
# -------------------------
cat > "$UVSHIM/python" << 'EOF'
#!/usr/bin/env bash
set -euo pipefail
PY="$(uv run python -c 'import sys; print(sys.executable)')"
exec uv run --python "$PY" python "$@"
EOF
chmod +x "$UVSHIM/python"


# -------------------------
# pip (maps to uv pip; accepts -p/--python)
# -------------------------
cat > "$UVSHIM/pip" << 'EOF'
#!/usr/bin/env bash
set -euo pipefail
ARGS=(); PY=""
while [[ $# -gt 0 ]]; do
  case "${1-}" in
    -p|--python) shift || true; PY="${1-}";;
    *) ARGS+=("${1-}");;
  esac
  shift || true
done
if [[ -z "$PY" ]]; then
  PY="$(uv run python -c 'import sys; print(sys.executable)')"
fi
exec uv pip --no-progress "${ARGS[@]}" --python "$PY"
EOF
chmod +x "$UVSHIM/pip"



# -------------------------
# version (two lines; matches uv resolver or active venv)
# -------------------------
cat > "$UVSHIM/version" << 'EOF'
#!/usr/bin/env bash
set -euo pipefail

# 1) uv version
uv self version

# 2) Python version — prefer active venv; else uv-run; else heuristic; else "(none)"
if [[ -n "${VIRTUAL_ENV:-}" && -x "$VIRTUAL_ENV/bin/python" ]]; then
  exec "$VIRTUAL_ENV/bin/python" --version
fi

if PYVER="$(UV_PYTHON_DOWNLOADS=never uv --no-progress run python -V 2>/dev/null || true)"; then
  if [[ -n "$PYVER" ]]; then
    echo "$PYVER"
    exit 0
  fi
fi

_pick_bin_for_pin() {
  local pin="${1:-}" mm cand
  if [[ "$pin" =~ ^([0-9]+)\.([0-9]+) ]]; then
    mm="${BASH_REMATCH[1]}.${BASH_REMATCH[2]}"
    for cand in "python$mm" "python${mm/./}" "python3.${BASH_REMATCH[2]}"; do
      if command -v "$cand" >/dev/null 2>&1; then
        command -v "$cand"; return 0
      fi
    done
  fi
  command -v python  >/dev/null 2>&1 && { command -v python;  return 0; }
  command -v python3 >/dev/null 2>&1 && { command -v python3; return 0; }
  return 1
}

PIN=""
if [[ -f ".python-version" ]]; then
  PIN="$(sed -n '1p' .python-version)"
else
  for c in \
    "${XDG_CONFIG_HOME:-$HOME/.config}/uv/.python-version" \
    "$HOME/.uv/.python-version" \
    "$HOME/.config/uv/python/version"
  do
    [[ -f "$c" ]] && { PIN="$(sed -n '1p' "$c")"; break; }
  done
fi

BIN="$(_pick_bin_for_pin "$PIN" 2>/dev/null || true)"
if [[ -n "${BIN:-}" ]]; then
  exec "$BIN" --version
fi

echo "Python (none)"
EOF
chmod +x "$UVSHIM/version"







# -------------------------
# venv (function): create/activate venv
# -------------------------
venv() {
    local _is_interactive="0"
    case "$-" in *i*) _is_interactive="1" ;; esac

    local _old_opts=""
    _old_opts="$(set +o)"
    if [[ "${_is_interactive}" == "0" ]]; then
        set -euo pipefail
    fi

    if [[ -n "${VIRTUAL_ENV:-}" ]]; then
        printf '[venv] Already inside a virtual environment: %s\n' \
            "${VIRTUAL_ENV}" 1>&2
        eval "${_old_opts}"
        return 0
    fi

    local py=""
    local act=".venv"

    while [[ $# -gt 0 ]]; do
        case "${1-}" in
            -p|--python)
                shift || true
                if [[ $# -le 0 ]]; then
                    printf '[ERROR] missing value for --python\n' 1>&2
                    eval "${_old_opts}"
                    return 1
                fi
                py="${1-}"
                shift || true
                ;;
            --)
                shift || true
                break
                ;;
            -*)
                printf '[ERROR] unknown option: %s\n' "${1-}" 1>&2
                eval "${_old_opts}"
                return 1
                ;;
            *)
                act="${1-}"
                shift || true
                break
                ;;
        esac
    done

    local -a extra_args=()
    while [[ $# -gt 0 ]]; do
        extra_args+=("$1")
        shift || true
    done

    local activate_path="${act}/bin/activate"

    if [[ ! -f "${activate_path}" ]]; then
        local -a cmd=(uv --no-progress venv)
        if [[ -n "${py}" ]]; then
            cmd+=(--python "${py}")
        fi

        # Use absolute path only for creation output
        local act_abs=""
        if [[ "${act}" = /* ]]; then
            act_abs="${act}"
        else
            act_abs="$(pwd)/${act}"
        fi

        cmd+=("${extra_args[@]}" "${act_abs}")

        # Filter uv output: drop "Activate with" line
        "${cmd[@]}" 2>&1 | sed '/^Activate with:/d'
    fi

    if [[ ! -f "${activate_path}" ]]; then
        printf '[ERROR] expected %s not found\n' "${activate_path}" 1>&2
        eval "${_old_opts}"
        return 1
    fi

    # Activate in the current shell
    # shellcheck disable=SC1090
    source "${activate_path}"

    # ---- PROMPT FIX (matches `uv venv`) ----
    local dir_name=""
    dir_name="$(basename "$(pwd)")"

    export VIRTUAL_ENV_PROMPT="(${dir_name}) "

    if [[ -n "${_OLD_VIRTUAL_PS1:-}" ]]; then
        PS1="${VIRTUAL_ENV_PROMPT}${_OLD_VIRTUAL_PS1}"
    else
        PS1="${VIRTUAL_ENV_PROMPT}${PS1}"
    fi
    # ---------------------------------------

    eval "${_old_opts}"
}













# -------------------------
# lpin (local pin)
# -------------------------
cat > "$UVSHIM/lpin" << 'EOF'
#!/usr/bin/env bash
set -euo pipefail

# If a version is provided, pin it here first.
if [[ $# -gt 0 ]]; then
  uv python pin "$1" >/dev/null
fi

# Find nearest ancestor (including PWD) that has .python-version
find_lpin_root() {
  local dir="$PWD"
  while :; do
    if [[ -f "$dir/.python-version" ]]; then
      printf '%s\n' "$dir"
      return 0
    fi
    local parent="${dir%/*}"
    [[ "$dir" == "$parent" ]] && return 1   # reached /
    dir="$parent"
  done
}

# In a pinned dir → print just "<version>"
if [[ -f ".python-version" ]]; then
  head -n 1 .python-version
  exit 0
fi

# Under a pinned ancestor → print "(~path) <version>"
if root="$(find_lpin_root)"; then
  version="$(head -n 1 "$root/.python-version")"
  # Shorten $HOME prefix to "~" (no slash → "~data/…", as you wanted)
  display="$root"
  if [[ "$display" == "$HOME" ]]; then
    display="~"
  else
    display="${display/#$HOME\//~}"
  fi
  printf '(%s) %s\n' "$display" "$version"
else
  # No pinned parent → "(none)"
  echo "(none)"
fi
EOF
chmod +x "$UVSHIM/lpin"


# -------------------------
# gpin (global pin)
# -------------------------
cat > "$UVSHIM/gpin" << 'EOF'
#!/usr/bin/env bash
set -euo pipefail
if [[ $# -gt 0 ]]; then uv python pin "$1" --global >/dev/null; fi
for c in \
  "${XDG_CONFIG_HOME:-$HOME/.config}/uv/.python-version" \
  "$HOME/.uv/.python-version" \
  "$HOME/.config/uv/python/version"
do
  [[ -f "$c" ]] && { sed -n '1p' "$c"; exit 0; }
done
echo "(none)"
EOF
chmod +x "$UVSHIM/gpin"

# -------------------------
# interpreters (fast + resilient; patch-level; dedup; smart star)
# -------------------------
cat > "$UVSHIM/interpreters" << 'EOF'
#!/usr/bin/env bash
set -euo pipefail

TIMEOUT_BIN="$(command -v timeout 2>/dev/null || true)"
tmo1() { [[ -n "$TIMEOUT_BIN" ]] && "$TIMEOUT_BIN" 1s "$@" || "$@"; }
tmo2() { [[ -n "$TIMEOUT_BIN" ]] && "$TIMEOUT_BIN" 2s "$@" || "$@"; }

_resolve() { readlink -f "$1" 2>/dev/null || realpath -e "$1" 2>/dev/null || printf '%s' "$1"; }
_should_skip_path() { local p="$1"; [[ "${UV_SHIMS_SCAN_MNT:-0}" = 0 && "$p" == /mnt/* ]] && return 0; return 1; }
array_push() { eval "$1+=(\"\$2\")"; }

# Current interpreter (respect pins; avoid downloads)
CUR=""
if CUR_PATH="$(UV_PYTHON_DOWNLOADS=never uv --no-progress run python - <<'PY' 2>/dev/null || true
import sys; print(sys.executable)
PY
)"; then CUR="$(_resolve "$CUR_PATH")"; fi

# Read pins for star selection
_read_global_pin() {
  for c in \
    "${XDG_CONFIG_HOME:-$HOME/.config}/uv/.python-version" \
    "$HOME/.uv/.python-version" \
    "$HOME/.config/uv/python/version"
  do [[ -f "$c" ]] && { sed -n '1p' "$c"; return 0; }; done
  return 1
}
LPIN=""; GPIN=""
[[ -f ".python-version" ]] && LPIN="$(sed -n '1p' .python-version || true)"
GPIN="$(_read_global_pin || true)"
PIN="${LPIN:-$GPIN}"

PIN_FULL=""; PIN_PREFIX=""
if [[ "$PIN" =~ ^([0-9]+)\.([0-9]+)\.([0-9]+)$ ]]; then
  PIN_FULL="cpython-${BASH_REMATCH[1]}.${BASH_REMATCH[2]}.${BASH_REMATCH[3]}"
  PIN_PREFIX="cpython-${BASH_REMATCH[1]}.${BASH_REMATCH[2]}"
elif [[ "$PIN" =~ ^([0-9]+)\.([0-9]+)$ ]]; then
  PIN_PREFIX="cpython-${BASH_REMATCH[1]}.${BASH_REMATCH[2]}"
elif [[ "$PIN" =~ ^(cpython-[0-9]+\.[0-9]+\.[0-9]+)$ ]]; then
  PIN_FULL="${BASH_REMATCH[1]}"
  PIN_PREFIX="${PIN_FULL%.*}"
elif [[ "$PIN" =~ ^(cpython-[0-9]+\.[0-9]+)$ ]]; then
  PIN_PREFIX="${BASH_REMATCH[1]}"
fi

declare -a SHORTS PATHS
declare -A SEEN   # by resolved sys.executable
MAXLEN=0
LIST_OK=0

_add_record() {
  local path="$1" ver="$2"
  local real_norm="$(_resolve "$path")"
  [[ -z "${SEEN[$real_norm]:-}" ]] || return 0
  SEEN["$real_norm"]=1
  local short="cpython-$ver"
  array_push SHORTS "$short"
  array_push PATHS  "$real_norm"
  (( ${#short} > MAXLEN )) && MAXLEN=${#short}
}

parse_line() {
  local ent="$1" rawp="$2"
  [[ -n "$rawp" ]] || return 1
  local p="${rawp#"${rawp%%[![:space:]]*}"}"
  p="${p%% *->*}"
  [[ -n "$p" ]] || return 1
  if [[ "$p" != /* ]]; then p="$(realpath -m -- "$p" 2>/dev/null || printf '%s' "$p")"; fi
  _should_skip_path "$p" && return 1
  [[ -x "$p" ]] || return 1

  local real_py ver real_norm
  real_py="$(tmo1 "$p" -c 'import sys;print(sys.executable)' 2>/dev/null || true)" || true
  [[ -n "$real_py" ]] || return 1
  ver="$(tmo1 "$p" -c 'import sys;print(f"{sys.version_info[0]}.{sys.version_info[1]}.{sys.version_info[2]}")' 2>/dev/null || true)" || true
  [[ -n "$ver" ]] || return 1
  real_norm="$(_resolve "$real_py")"
  _add_record "$real_norm" "$ver"
}

if OUT="$(tmo2 uv --no-progress python list --only-installed 2>/dev/null || true)"; then
  if [[ -n "$OUT" ]]; then
    while IFS= read -r line; do
      [[ -z "$line" ]] && continue
      a="${line%%[[:space:]]*}"; b="${line#"$a"}"; b="${b##[[:space:]]}"
      parse_line "$a" "$b" || true
    done <<<"$OUT"
    LIST_OK=1
  fi
fi

# fallback probing (PATH + uv-managed) if the list call wasn't usable
_add_entry_probe() {
  local bin="$1"; [[ -x "$bin" ]] || return 0; _should_skip_path "$bin" && return 0
  local real_py ver real_norm
  real_py="$(tmo1 "$bin" -c 'import sys;print(sys.executable)' 2>/dev/null || true)" || true
  [[ -n "$real_py" ]] || return 0
  ver="$(tmo1 "$bin" -c 'import sys;print(f"{sys.version_info[0]}.{sys.version_info[1]}.{sys.version_info[2]}")' 2>/dev/null || true)" || true
  [[ -n "$ver" ]] || return 0
  real_norm="$(_resolve "$real_py")"
  _add_record "$real_norm" "$ver"
}
if [[ "$LIST_OK" -eq 0 ]]; then
  if [[ "${UV_SHIMS_FAST:-0}" = "1" ]]; then
    for cand in python python3 python3.12 python3.11 python3.10; do
      bin="$(command -v "$cand" 2>/dev/null || true)"
      [[ -n "$bin" ]] && _add_entry_probe "$bin"
    done
  else
    while IFS= read -r cand; do
      bin="$(command -v "$cand" 2>/dev/null || true)"
      [[ -n "$bin" ]] && _add_entry_probe "$bin"
    done < <(LC_ALL=C compgen -c | grep -E '^python(3(\.[0-9]+)?)?$|^python3\.[0-9]+$' | sort -u)
    if [[ "${UV_SHIMS_SKIP_UVDATA:-0}" != 1 ]]; then
      _uv_data="${XDG_DATA_HOME:-$HOME/.local/share}/uv/python"
      if [[ -d "$_uv_data" ]]; then
        while IFS= read -r p; do _add_entry_probe "$p"; done < <(
          find "$_uv_data" -type f -path '*/bin/python*' -executable 2>/dev/null | sort -u
        )
      fi
    fi
  fi
fi

# Sort by version and decide star index
if ((${#SHORTS[@]}==0)); then
  echo "(no interpreters found)"; exit 0
fi
mapfile -t KEYS < <(printf '%s\n' "${!SHORTS[@]}")
IFS=$'\n' KEYS=($(for i in "${KEYS[@]}"; do echo -e "${SHORTS[i]}\t$i"; done | sort -V | awk -F'\t' '{print $2}')); unset IFS

STAR_IDX=-1
# prefer current interpreter
if [[ -n "$CUR" ]]; then
  for i in "${KEYS[@]}"; do
    [[ "$CUR" == "${PATHS[i]}" ]] && { STAR_IDX="$i"; break; }
  done
fi
# exact pinned X.Y.Z
if [[ "$STAR_IDX" -lt 0 && -n "$PIN_FULL" ]]; then
  for i in "${KEYS[@]}"; do
    [[ "${SHORTS[i]}" == "$PIN_FULL" ]] && STAR_IDX="$i"
  done
fi
# highest patch for pinned X.Y
if [[ "$STAR_IDX" -lt 0 && -n "$PIN_PREFIX" ]]; then
  for i in "${KEYS[@]}"; do
    [[ "${SHORTS[i]}" == ${PIN_PREFIX}* ]] && STAR_IDX="$i"
  done
fi

for i in "${KEYS[@]}"; do
  mark=' '
  [[ "$i" == "$STAR_IDX" ]] && mark='*'
  printf "%s %s %s\n" "$mark" "${SHORTS[i]}" "${PATHS[i]}"
done
EOF
chmod +x "$UVSHIM/interpreters"








# -------------------------
# prune (shim): prune uv cache using hardlink GC + venv-installed wheels keep
# -------------------------
cat > "$UVSHIM/prune" << 'EOF'
#!/usr/bin/env bash
set -euo pipefail

: "${UV_CACHE_DIR:=$HOME/.cache/uv}"

DEBUG=0  # set to 1 to activate logs
log() {
  if (( DEBUG )); then
    printf '[uv-cache-gc] %s\n' "$*" >&2
  fi
  return 0
}

normalize_project_name() {
  local name="$1"
  name="${name,,}"
  name="${name//_/-}"
  name="${name//./-}"
  name="${name//+/-}"
  printf '%s' "$name"
}

has_linked_files() {
  local dir="$1"
  find "$dir" -type f -print0 2>/dev/null \
    | xargs -0 -r stat -c '%h' -- 2>/dev/null \
    | awk '$1 > 1 { found=1; exit } END { exit !found }'
}

extract_names_from_archive_object() {
  # Print normalized dist names found in *.dist-info/METADATA under obj_dir
  local obj_dir="$1"

  # Correct: match paths like ".../<something>.dist-info/METADATA"
  mapfile -d '' -t metadata_files < <(
    find "$obj_dir" -type f -name METADATA -print0 2>/dev/null \
      | tr '\0' '\n' \
      | awk '$0 ~ /\.dist-info\/METADATA$/ { print }' \
      | tr '\n' '\0'
  )

  log "  METADATA files found: ${#metadata_files[@]} (under $obj_dir)"
  if (( ${#metadata_files[@]} > 0 )); then
    local show_n=5
    if (( ${#metadata_files[@]} < show_n )); then
      show_n="${#metadata_files[@]}"
    fi
    for ((i = 0; i < show_n; i++)); do
      log "    METADATA: ${metadata_files[$i]}"
    done
  fi

  local metadata_path=""
  for metadata_path in "${metadata_files[@]}"; do
    local dist_name=""
    dist_name="$(
      awk -F': *' 'tolower($1)=="name" { print $2; exit }' "$metadata_path" \
        || true
    )"

    if [[ -z "$dist_name" ]]; then
      log "    WARN: could not parse Name: from $metadata_path"
      continue
    fi

    local norm=""
    norm="$(normalize_project_name "$dist_name")"
    log "    Parsed Name: '$dist_name' -> keep key: '$norm'"
    printf '%s\n' "$norm"
  done
}

if [[ ! -d "$UV_CACHE_DIR" ]]; then
  echo "UV cache directory does not exist: $UV_CACHE_DIR" >&2
  exit 1
fi

log "UV_CACHE_DIR=$UV_CACHE_DIR"

mapfile -d '' -t archive_roots < <(find "$UV_CACHE_DIR" -type d -name '*archive*' -print0 2>/dev/null)
log "Found archive roots: ${#archive_roots[@]}"
for r in "${archive_roots[@]}"; do
  log "  archive_root: $r"
done

mapfile -d '' -t wheels_roots < <(find "$UV_CACHE_DIR" -type d -name '*wheels*' -print0 2>/dev/null)
log "Found wheels roots: ${#wheels_roots[@]}"
for r in "${wheels_roots[@]}"; do
  log "  wheels_root: $r"
done

# -----------------------------------------------------------------------------
# 1) Prune archive objects that have ONLY single-linked files (nlink == 1)
#    Then remove the archive root itself if it becomes empty.
# -----------------------------------------------------------------------------
for archive_root in "${archive_roots[@]}"; do
  [[ -d "$archive_root" ]] || continue

  mapfile -d '' -t obj_dirs < <(
    find "$archive_root" -mindepth 1 -maxdepth 1 -type d -print0 2>/dev/null
  )
  log "Scanning archive root: $archive_root (objects=${#obj_dirs[@]})"

  for obj_dir in "${obj_dirs[@]}"; do
    [[ -d "$obj_dir" ]] || continue

    if has_linked_files "$obj_dir"; then
      log "KEEP archive object (has linked files): $obj_dir"
      continue
    fi

    log "DELETE archive object (all nlink==1): $obj_dir"
    rm -rf -- "$obj_dir"
  done

  if [[ -d "$archive_root" ]] && [[ -z "$(ls -A "$archive_root" 2>/dev/null)" ]]; then
    log "DELETE empty archive root: $archive_root"
    rmdir -- "$archive_root" 2>/dev/null || true
  fi
done

# -----------------------------------------------------------------------------
# 2) Build keep-list from installed packages in *existing venvs* (site-packages)
# -----------------------------------------------------------------------------
keep_projects_file="$(mktemp)"
trap 'rm -f -- "$keep_projects_file"' EXIT

scan_roots=(
  "$PWD"
  "$HOME/data"
  "/mnt/workdata/data"
)

log "Scanning for installed packages in venvs under:"
for root in "${scan_roots[@]}"; do
  log "  scan_root: $root"
done

metadata_count=0
name_count=0

for root in "${scan_roots[@]}"; do
  [[ -d "$root" ]] || continue

  while IFS= read -r -d '' metadata_path; do
    metadata_count=$((metadata_count + 1))

    dist_name="$(
      awk -F': *' 'tolower($1)=="name" { print $2; exit }' "$metadata_path" \
        || true
    )"

    if [[ -z "$dist_name" ]]; then
      log "  WARN: could not parse Name: from $metadata_path"
      continue
    fi

    norm="$(normalize_project_name "$dist_name")"
    printf '%s\n' "$norm" >>"$keep_projects_file"
    name_count=$((name_count + 1))
  done < <(
    find "$root" -type f \
      -path '*/.venv/lib/python*/site-packages/*.dist-info/METADATA' \
      -print0 2>/dev/null
  )
done

if [[ -s "$keep_projects_file" ]]; then
  sort -u "$keep_projects_file" -o "$keep_projects_file"
fi

log "Venv METADATA files seen: $metadata_count"
log "Names extracted (pre-dedupe): $name_count"
log "Keep-list (deduped):"
if [[ -s "$keep_projects_file" ]]; then
  while IFS= read -r name; do
    log "  keep: $name"
  done <"$keep_projects_file"
else
  log "  (empty)"
fi

# -----------------------------------------------------------------------------
# 3) Under any "*wheels*"/pypi/, keep ONLY wheels for keep-list names
# -----------------------------------------------------------------------------
for wheels_root in "${wheels_roots[@]}"; do
  pypi_root="$wheels_root/pypi"
  if [[ ! -d "$pypi_root" ]]; then
    log "Skip wheels root without pypi/: $wheels_root"
    continue
  fi

  mapfile -d '' -t proj_dirs < <(
    find "$pypi_root" -mindepth 1 -maxdepth 1 -type d -print0 2>/dev/null
  )
  log "Scanning wheels pypi root: $pypi_root (projects=${#proj_dirs[@]})"

  for proj_dir in "${proj_dirs[@]}"; do
    [[ -d "$proj_dir" ]] || continue
    proj_name="$(basename -- "$proj_dir")"

    if [[ -s "$keep_projects_file" ]] && grep -Fxq -- "$proj_name" "$keep_projects_file"; then
      log "KEEP wheels project dir: $proj_dir"
      continue
    fi

    log "DELETE wheels project dir: $proj_dir"
    rm -rf -- "$proj_dir"
  done
done

log "Done."
EOF
chmod +x "$UVSHIM/prune"







# -------------------------
# lock (shim): promote active venv to pyproject + uv lock (names only)
# -------------------------
cat > "$UVSHIM/lock" << 'EOF'
#!/usr/bin/env bash
# lock — promote active venv deps to pyproject.toml (names only) and run `uv lock`
#
# Walk upward from the active environment directory to find pyproject.toml.
# If none exists at the venv-level directory, initialize one with `uv init`.
# Then declare EVERYTHING installed in the environment as plain names
# (no versions) using uv, and run `uv lock`.
#
# Pure-bash implementation: no Python invocations.
#
# Requirements:
# - Active environment (VIRTUAL_ENV set)
# - uv available in PATH

set -euo pipefail

if [[ -z "${VIRTUAL_ENV:-}" ]]; then
  echo "error: no active environment (VIRTUAL_ENV is not set)" >&2
  exit 1
fi

if ! command -v uv >/dev/null 2>&1; then
  echo "error: uv not found in PATH" >&2
  exit 1
fi

# ----------------------------------------------------------------------
# Helpers
# ----------------------------------------------------------------------
normalize_name() {
  # Normalize as in PEP 503-ish: [-_.]+ -> -, lowercase.
  # Args:
  #   $1: raw name
  local raw_name="${1:-}"
  raw_name="${raw_name,,}"
  raw_name="$(printf '%s' "$raw_name" | sed -E 's/[-_.]+/-/g')"
  printf '%s\n' "$raw_name"
}

is_nvidia_dependency() {
  # Return success if dependency name should be classified as CUDA/NVIDIA.
  # Args:
  #   $1: normalized dependency name
  local name="${1:-}"
  if [[ "$name" == *nvidia* || "$name" == *cuda* ]]; then
    return 0
  fi
  return 1
}

find_site_packages_dirs() {
  # Find site-packages under the active venv without calling python.
  # Prints one directory per line.
  local venv_dir="${1:?}"
  local found_any="0"
  local d=""

  while IFS= read -r d; do
    found_any="1"
    printf '%s\n' "$d"
  done < <(
    find "$venv_dir" -type d \
      \( -name "site-packages" -o -name "dist-packages" \) \
      -print 2>/dev/null \
      | LC_ALL=C sort -u
  )

  if [[ "$found_any" == "0" ]]; then
    return 1
  fi
}

name_from_dist_info() {
  # Args:
  #   $1: path to *.dist-info directory
  local dist_dir="${1:?}"
  local meta_path="$dist_dir/METADATA"

  if [[ -f "$meta_path" ]]; then
    local name_line=""
    name_line="$(grep -m1 -E '^Name:' "$meta_path" || true)"
    if [[ -n "$name_line" ]]; then
      local raw_name=""
      raw_name="$(printf '%s' "$name_line" | sed -E 's/^Name:[[:space:]]*//')"
      raw_name="$(printf '%s' "$raw_name" | sed -E 's/[[:space:]]+$//')"
      if [[ -n "$raw_name" ]]; then
        normalize_name "$raw_name"
        return 0
      fi
    fi
  fi

  return 1
}

name_from_egg_info() {
  # Args:
  #   $1: path to *.egg-info (dir or file)
  local egg_path="${1:?}"
  local pkg_info=""

  if [[ -d "$egg_path" && -f "$egg_path/PKG-INFO" ]]; then
    pkg_info="$egg_path/PKG-INFO"
  elif [[ -f "$egg_path" ]]; then
    # Rare: single-file *.egg-info; treat it like PKG-INFO-ish
    pkg_info="$egg_path"
  else
    return 1
  fi

  local name_line=""
  name_line="$(grep -m1 -E '^Name:' "$pkg_info" || true)"
  if [[ -n "$name_line" ]]; then
    local raw_name=""
    raw_name="$(printf '%s' "$name_line" | sed -E 's/^Name:[[:space:]]*//')"
    raw_name="$(printf '%s' "$raw_name" | sed -E 's/[[:space:]]+$//')"
    if [[ -n "$raw_name" ]]; then
      normalize_name "$raw_name"
      return 0
    fi
  fi

  return 1
}

fallback_name_from_metadata_dir_basename() {
  # Best-effort fallback if METADATA/PKG-INFO missing.
  local base="${1:?}"
  base="${base%.dist-info}"
  base="${base%.egg-info}"

  # If it matches wheel convention {dist}-{version}, strip last -<version-ish>.
  local prefix="${base%*-}"
  local suffix="${base##*-}"
  if [[ "$base" != "$prefix" && "$suffix" =~ ^[0-9] ]]; then
    base="$prefix"
  fi

  normalize_name "$base"
}

# ----------------------------------------------------------------------
# Ensure pyproject.toml exists at venv-level directory
# ----------------------------------------------------------------------
venv_level_dir="$(dirname "$(cd "$VIRTUAL_ENV" && pwd)")"

if [[ ! -f "$venv_level_dir/pyproject.toml" ]]; then
  echo "No pyproject.toml found at venv level: $venv_level_dir"
  echo "Initializing with: uv init"
  (
    cd "$venv_level_dir"
    uv init >/dev/null
  )
fi

# ----------------------------------------------------------------------
# Walk upward from the environment directory to find pyproject.toml
# ----------------------------------------------------------------------
search_dir="$(cd "$VIRTUAL_ENV" && pwd)"
pyproject_path=""

while [[ "$search_dir" != "/" ]]; do
  if [[ -f "$search_dir/pyproject.toml" ]]; then
    pyproject_path="$search_dir/pyproject.toml"
    break
  fi
  search_dir="$(dirname "$search_dir")"
done

if [[ -z "$pyproject_path" ]]; then
  echo "error: could not find pyproject.toml above $VIRTUAL_ENV" >&2
  exit 1
fi

project_root="$(dirname "$pyproject_path")"
echo "Using pyproject.toml at: $pyproject_path"

tmp_names="$(mktemp)"
tmp_all="$(mktemp)"
tmp_cuda="$(mktemp)"
tmp_main="$(mktemp)"
trap 'rm -f "$tmp_names" "$tmp_all" "$tmp_cuda" "$tmp_main"' EXIT

# ----------------------------------------------------------------------
# Enumerate installed distributions (names only) without Python
# ----------------------------------------------------------------------
site_dirs=""
if ! site_dirs="$(find_site_packages_dirs "$VIRTUAL_ENV")"; then
  echo "error: could not locate site-packages under: $VIRTUAL_ENV" >&2
  exit 1
fi

while IFS= read -r sp; do
  find "$sp" -maxdepth 1 -type d -name "*.dist-info" -print 2>/dev/null \
    | while IFS= read -r dist_dir; do
        if ! name_from_dist_info "$dist_dir"; then
          fallback_name_from_metadata_dir_basename "$(basename "$dist_dir")"
        fi
      done

  find "$sp" -maxdepth 1 -type d -name "*.egg-info" -print 2>/dev/null \
    | while IFS= read -r egg_dir; do
        if ! name_from_egg_info "$egg_dir"; then
          fallback_name_from_metadata_dir_basename "$(basename "$egg_dir")"
        fi
      done

  find "$sp" -maxdepth 1 -type f -name "*.egg-info" -print 2>/dev/null \
    | while IFS= read -r egg_file; do
        if ! name_from_egg_info "$egg_file"; then
          fallback_name_from_metadata_dir_basename "$(basename "$egg_file")"
        fi
      done
done <<<"$site_dirs" >"$tmp_all"

LC_ALL=C sort -u "$tmp_all" >"$tmp_names"

# Split into "main" and "cuda" groups
while IFS= read -r name; do
  if [[ -z "$name" ]]; then
    continue
  fi
  if is_nvidia_dependency "$name"; then
    printf '%s\n' "$name" >>"$tmp_cuda"
  else
    printf '%s\n' "$name" >>"$tmp_main"
  fi
done <"$tmp_names"

LC_ALL=C sort -u "$tmp_main" -o "$tmp_main" 2>/dev/null || true
LC_ALL=C sort -u "$tmp_cuda" -o "$tmp_cuda" 2>/dev/null || true

count_total="$(wc -l <"$tmp_names" | tr -d ' ')"
count_main="$(wc -l <"$tmp_main" | tr -d ' ')"
count_cuda="$(wc -l <"$tmp_cuda" | tr -d ' ')"

echo "Found ${count_total} installed packages."
echo " - main: ${count_main}"
echo " - cuda: ${count_cuda}"
echo "Adding them to pyproject.toml (no versions, no sync)..."

cd "$project_root"

# Add main deps to [project.dependencies]
if [[ -s "$tmp_main" ]]; then
  xargs -a "$tmp_main" -n 50 uv add --raw --no-sync -- >/dev/null
fi

# Add CUDA deps to optional-dependencies.extra "cuda"
if [[ -s "$tmp_cuda" ]]; then
  xargs -a "$tmp_cuda" -n 50 uv add --raw --optional cuda --no-sync -- >/dev/null
fi

echo "Running: uv lock"
uv lock

echo "Done."
EOF
chmod +x "$UVSHIM/lock"




# -------------------------
# Ensure PATH contains ~/.local/uv-shims
# -------------------------
PROFILE="$HOME/.bashrc"
[[ -n "${ZSH_VERSION:-}" ]] && PROFILE="$HOME/.zshrc"
if ! grep -q '# uv shims$' "$PROFILE"; then
  printf '%s\n' '[[ ":$PATH:" != *":$HOME/.local/uv-shims:"* ]] && export PATH="$HOME/.local/uv-shims:$PATH"  # uv shims' >> "$PROFILE"
  echo "[INFO] Added ~/.local/uv-shims to PATH in $PROFILE"
fi