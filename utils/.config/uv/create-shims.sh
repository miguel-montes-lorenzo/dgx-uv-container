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
cat > "$UVSHIM/_python" << 'EOF'
#!/usr/bin/env bash
set -euo pipefail
PY="$(uv run python -c 'import sys; print(sys.executable)')"
exec uv run --python "$PY" python "$@"
EOF
chmod +x "$UVSHIM/_python"

cat > "$UVSHIM/python" << 'EOF'
#!/usr/bin/env bash
exec "$HOME/.local/uv-shims/_python" "$@"
EOF
chmod +x "$UVSHIM/python"

# -------------------------
# pip (maps to uv pip; accepts -p/--python)
# -------------------------
cat > "$UVSHIM/_pip" << 'EOF'
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
chmod +x "$UVSHIM/_pip"

cat > "$UVSHIM/pip" << 'EOF'
#!/usr/bin/env bash
exec "$HOME/.local/uv-shims/_pip" "$@"
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
  set -euo pipefail

  # Avoid nesting
  if [[ -n "${VIRTUAL_ENV:-}" ]]; then
    printf '[venv] Already inside a virtual environment: %s\n' "${VIRTUAL_ENV}" >&2
    return 0
  fi

  local py=""
  local act=".venv"

  # Parse args
  while [[ $# -gt 0 ]]; do
    case "${1-}" in
      -p|--python)
        shift || true
        [[ $# -gt 0 ]] || { printf '[ERROR] missing value for --python\n' >&2; return 1; }
        py="${1-}"
        shift || true
        ;;
      --)
        shift || true
        break
        ;;
      -*)
        printf '[ERROR] unknown option: %s\n' "${1-}" >&2
        return 1
        ;;
      *)
        act="${1-}"
        shift || true
        break
        ;;
    esac
  done

  # Remaining args → uv
  # shellcheck disable=SC2124
  local uv_extra_args="$*"

  local activate_path="${act}/bin/activate"

  # Create venv if missing
  if [[ ! -f "${activate_path}" ]]; then
    if [[ -n "${py}" ]]; then
      if [[ -n "${uv_extra_args}" ]]; then
        eval "uv --no-progress venv --python \"${py}\" ${uv_extra_args} \"${act}\""
      else
        uv --no-progress venv --python "${py}" "${act}"
      fi
    else
      if [[ -n "${uv_extra_args}" ]]; then
        eval "uv --no-progress venv ${uv_extra_args} \"${act}\""
      else
        uv --no-progress venv "${act}"
      fi
    fi
  fi

  [[ -f "${activate_path}" ]] || {
    printf '[ERROR] expected %s not found\n' "${activate_path}" >&2
    return 1
  }

  # Load rc first (matches old behavior)
  if [[ -n "${BASH_VERSION:-}" ]]; then
    [[ -f "${HOME}/.bashrc" ]] && source "${HOME}/.bashrc"
  elif [[ -n "${ZSH_VERSION:-}" ]]; then
    local zdot="${ZDOTDIR:-${HOME}}"
    [[ -f "${zdot}/.zshrc" ]] && source "${zdot}/.zshrc"
  fi

  # Activate
  # shellcheck disable=SC1090
  source "${activate_path}"
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
# Ensure PATH contains ~/.local/uv-shims
# -------------------------
PROFILE="$HOME/.bashrc"
[[ -n "${ZSH_VERSION:-}" ]] && PROFILE="$HOME/.zshrc"
if ! grep -q '# uv shims$' "$PROFILE"; then
  printf '%s\n' '[[ ":$PATH:" != *":$HOME/.local/uv-shims:"* ]] && export PATH="$HOME/.local/uv-shims:$PATH"  # uv shims' >> "$PROFILE"
  echo "[INFO] Added ~/.local/uv-shims to PATH in $PROFILE"
fi
