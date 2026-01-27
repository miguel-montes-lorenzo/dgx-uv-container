register-ssh-host() {
  # register-ssh-host
  #
  # Usage:
  #   register-ssh-host
  #   register-ssh-host --alias=<alias>
  #
  # Behavior:
  # - Without flags:
  #   - Require CWD is a git repo.
  #   - Require CWD is not already a Host alias in ~/.ssh/config.
  #   - Generate a new ed25519 deploy key: ~/.ssh/id_ed25519_repo_<10digits>
  #   - Append Host entry with alias = "<CWD>"
  #   - chmod 600 ~/.ssh/config
  #   - Print the public key instructions.
  #
  # - With --alias=<alias>:
  #   - Require alias exists as a Host in ~/.ssh/config.
  #   - Require CWD is a git repo.
  #   - Require CWD is not already a Host alias in ~/.ssh/config.
  #   - Rename that Host alias to "<CWD>" (preserving rest of block).
  #
  # In both cases:
  # - git remote set-url origin <CWD>:<owner>/<repo>.git
  # - Reorder ~/.ssh/config Host blocks alphabetically by alias.
  #
  # Important:
  # - No `set -e`, to avoid exiting an interactive shell/container on controlled errors.
  # - History is disabled during execution to avoid polluting ~/.bash_history.

  # ----------------------------
  # Save/restore only what we touch
  # ----------------------------
  local _rss__was_history="off"
  local _rss__was_nounset="off"
  local _rss__was_pipefail="off"

  if [[ "$(set -o | awk '$1=="history"{print $2; exit}')" == "on" ]]; then
    _rss__was_history="on"
  fi
  if [[ "$-" == *u* ]]; then
    _rss__was_nounset="on"
  fi
  if [[ "$(set -o | awk '$1=="pipefail"{print $2; exit}')" == "on" ]]; then
    _rss__was_pipefail="on"
  fi

  set +o history
  set -u
  set -o pipefail

  _rss__exit() {
    local code="${1:-0}"

    if [[ "$_rss__was_nounset" != "on" ]]; then
      set +u
    fi
    if [[ "$_rss__was_pipefail" != "on" ]]; then
      set +o pipefail
    fi
    if [[ "$_rss__was_history" == "on" ]]; then
      set -o history
    fi

    return "$code"
  }

  # ----------------------------
  # Parse args
  # ----------------------------
  local cfg="$HOME/.ssh/config"
  local ssh_dir="$HOME/.ssh"
  local alias_arg=""

  while [[ $# -gt 0 ]]; do
    case "${1-}" in
      --alias=*)
        alias_arg="${1#--alias=}"
        ;;
      *)
        printf 'error: unknown argument: %s\n' "${1-}" >&2
        _rss__exit 2
        return $?
        ;;
    esac
    shift || true
  done

  if [[ -n "$alias_arg" && ! "$alias_arg" =~ ^[A-Za-z0-9]+$ ]]; then
    printf 'error: --alias must be [A-Za-z0-9]+ (got: %s)\n' "$alias_arg" >&2
    _rss__exit 2
    return $?
  fi

  # ----------------------------
  # Preconditions
  # ----------------------------
  if ! git rev-parse --is-inside-work-tree >/dev/null 2>&1; then
    printf 'error: current directory is not a git repository\n' >&2
    _rss__exit 1
    return $?
  fi

  local cwd=""
  cwd="$(pwd -P)"

  mkdir -p "$ssh_dir" >/dev/null 2>&1 || {
    printf 'error: could not create %s\n' "$ssh_dir" >&2
    _rss__exit 1
    return $?
  }
  chmod 700 "$ssh_dir" >/dev/null 2>&1 || true

  if [[ ! -e "$cfg" ]]; then
    : >"$cfg" || {
      printf 'error: could not create %s\n' "$cfg" >&2
      _rss__exit 1
      return $?
    }
  fi
  chmod 600 "$cfg" >/dev/null 2>&1 || true

  _rss__host_aliases() {
    awk '
      function ltrim(s){ sub(/^[ \t\r\n]+/, "", s); return s }
      function rtrim(s){ sub(/[ \t\r\n]+$/, "", s); return s }
      function trim(s){ return rtrim(ltrim(s)) }
      {
        line=$0
        sub(/\r$/, "", line)
        t=trim(line)
        if (t ~ /^#/ || t == "") next
        if (t ~ /^Host[ \t]+/) {
          sub(/^Host[ \t]+/, "", t)
          split(t, a, /[ \t]+/)
          if (a[1] != "") print a[1]
        }
      }
    ' "$cfg"
  }

  if _rss__host_aliases | awk -v want="$cwd" '$0==want{found=1} END{exit found?0:1}'; then
    printf 'error: cwd is already present as a Host alias in %s\n' "$cfg" >&2
    _rss__exit 1
    return $?
  fi

  if [[ -n "$alias_arg" ]]; then
    if ! _rss__host_aliases | awk -v want="$alias_arg" \
      '$0==want{found=1} END{exit found?0:1}'; then
      printf 'error: alias not found in %s: %s\n' "$cfg" "$alias_arg" >&2
      _rss__exit 1
      return $?
    fi
  fi

  # ----------------------------
  # Sort ~/.ssh/config blocks by alias (pure bash)
  # ----------------------------
  _rss__sort_ssh_config_by_alias() {
    local in_file="$1"
    local out_file="$2"

    local tmpd=""
    tmpd="$(mktemp -d)" || return 1

    local pre="$tmpd/preamble"
    local map="$tmpd/map.tsv"
    : >"$pre" || {
      rm -rf "$tmpd"
      return 1
    }
    : >"$map" || {
      rm -rf "$tmpd"
      return 1
    }

    local in_block="0"
    local cur_alias=""
    local cur_file=""
    local idx="0"
    local line=""

    _rss__flush_block() {
      if [[ "$in_block" == "1" ]]; then
        printf '%s\t%s\n' "$cur_alias" "$cur_file" >>"$map" || return 1
      fi
      return 0
    }

    while IFS= read -r line || [[ -n "$line" ]]; do
      line="${line%$'\r'}"

      if [[ "$line" =~ ^[[:space:]]*Host[[:space:]]+ ]] && \
         [[ ! "$line" =~ ^[[:space:]]*# ]]; then
        if ! _rss__flush_block; then
          rm -rf "$tmpd"
          return 1
        fi

        idx="$((idx + 1))"
        cur_file="$tmpd/block_$idx"
        : >"$cur_file" || {
          rm -rf "$tmpd"
          return 1
        }

        cur_alias="$(
          printf '%s\n' "$line" \
            | awk '{for (i=1;i<=NF;i++) if ($i=="Host"){print $(i+1); exit}}'
        )"

        in_block="1"
        printf '%s\n' "$line" >>"$cur_file" || {
          rm -rf "$tmpd"
          return 1
        }
      else
        if [[ "$in_block" == "1" ]]; then
          printf '%s\n' "$line" >>"$cur_file" || {
            rm -rf "$tmpd"
            return 1
          }
        else
          printf '%s\n' "$line" >>"$pre" || {
            rm -rf "$tmpd"
            return 1
          }
        fi
      fi
    done <"$in_file"

    if ! _rss__flush_block; then
      rm -rf "$tmpd"
      return 1
    fi

    : >"$out_file" || {
      rm -rf "$tmpd"
      return 1
    }

    cat "$pre" >>"$out_file" || {
      rm -rf "$tmpd"
      return 1
    }

    local first="1"
    local file_path=""
    local _alias=""

    while IFS=$'\t' read -r _alias file_path; do
      [[ -n "$file_path" ]] || continue

      if [[ "$first" == "1" ]]; then
        first="0"
        if [[ -s "$out_file" ]]; then
          if [[ "$(tail -n 1 "$out_file" | tr -d ' \t')" != "" ]]; then
            printf '\n' >>"$out_file" || {
              rm -rf "$tmpd"
              return 1
            }
          fi
        fi
      else
        printf '\n' >>"$out_file" || {
          rm -rf "$tmpd"
          return 1
        }
      fi

      cat "$file_path" >>"$out_file" || {
        rm -rf "$tmpd"
        return 1
      }

      if [[ "$(tail -c 1 "$out_file" 2>/dev/null || true)" != $'\n' ]]; then
        printf '\n' >>"$out_file" || {
          rm -rf "$tmpd"
          return 1
        }
      fi
    done < <(LC_ALL=C sort -t $'\t' -k1,1 "$map")

    rm -rf "$tmpd"
    return 0
  }

  # ----------------------------
  # Main branches
  # ----------------------------
  local key_id=""
  local key_priv=""
  local key_pub=""

  if [[ -z "$alias_arg" ]]; then
    key_id="$(LC_ALL=C tr -dc '0-9' </dev/urandom | head -c 10)"
    key_priv="$ssh_dir/id_ed25519_repo_${key_id}"
    key_pub="${key_priv}.pub"

    if [[ -e "$key_priv" || -e "$key_pub" ]]; then
      printf 'error: key path already exists: %s\n' "$key_priv" >&2
      _rss__exit 1
      return $?
    fi

    if ! ssh-keygen -t ed25519 \
      -C "deploy-key-repo_${key_id}" \
      -f "$key_priv" \
      -N ""; then
      printf 'error: ssh-keygen failed\n' >&2
      _rss__exit 1
      return $?
    fi

    chmod 600 "$key_priv" >/dev/null 2>&1 || true
    chmod 644 "$key_pub" >/dev/null 2>&1 || true

    {
      printf '\n'
      printf 'Host %s\n' "$cwd"
      printf '  HostName github.com\n'
      printf '  User git\n'
      printf '  IdentityFile %s\n' "$key_priv"
      printf '  IdentitiesOnly yes\n'
      printf '  StrictHostKeyChecking yes\n'
    } >>"$cfg" || {
      printf 'error: could not write to %s\n' "$cfg" >&2
      _rss__exit 1
      return $?
    }

    chmod 600 "$cfg" >/dev/null 2>&1 || true

    printf 'Include the following public key in your GitHub repository (Settings → Deploy keys → Add deploy key).\n'
    printf '> PUBLIC KEY: %s\n' "$(cat "$key_pub")"

  else
    local tmp_cfg=""
    tmp_cfg="$(mktemp)" || {
      printf 'error: mktemp failed\n' >&2
      _rss__exit 1
      return $?
    }

    if ! awk -v old="$alias_arg" -v new="$cwd" '
      function ltrim(s){ sub(/^[ \t\r\n]+/, "", s); return s }
      function rtrim(s){ sub(/[ \t\r\n]+$/, "", s); return s }
      function trim(s){ return rtrim(ltrim(s)) }
      {
        line=$0
        sub(/\r$/, "", line)
        t=trim(line)
        if (t ~ /^Host[ \t]+/) {
          rest=t
          sub(/^Host[ \t]+/, "", rest)
          split(rest, a, /[ \t]+/)
          if (a[1] == old) {
            print "Host " new
            next
          }
        }
        print line
      }
    ' "$cfg" >"$tmp_cfg"; then
      rm -f "$tmp_cfg" >/dev/null 2>&1 || true
      printf 'error: failed to update %s\n' "$cfg" >&2
      _rss__exit 1
      return $?
    fi

    if ! mv -f "$tmp_cfg" "$cfg"; then
      rm -f "$tmp_cfg" >/dev/null 2>&1 || true
      printf 'error: failed to replace %s\n' "$cfg" >&2
      _rss__exit 1
      return $?
    fi
    chmod 600 "$cfg" >/dev/null 2>&1 || true
  fi

  # ----------------------------
  # Update origin URL: <cwd>:<owner>/<repo>.git
  # ----------------------------
  _rss__origin_owner_repo() {
    local origin_url="$1"
    local s="$origin_url"
    s="${s%.git}"

    if [[ "$s" =~ ^git@[^:]+:(.+)/(.+)$ ]]; then
      printf '%s/%s\n' "${BASH_REMATCH[1]}" "${BASH_REMATCH[2]}"
      return 0
    fi
    if [[ "$s" =~ ^ssh://git@[^/]+/(.+)/(.+)$ ]]; then
      printf '%s/%s\n' "${BASH_REMATCH[1]}" "${BASH_REMATCH[2]}"
      return 0
    fi
    if [[ "$s" =~ ^https?://[^/]+/(.+)/(.+)$ ]]; then
      printf '%s/%s\n' "${BASH_REMATCH[1]}" "${BASH_REMATCH[2]}"
      return 0
    fi
    return 1
  }

  local origin_url=""
  origin_url="$(git remote get-url origin 2>/dev/null || true)"
  if [[ -z "$origin_url" ]]; then
    printf 'error: origin remote not found\n' >&2
    _rss__exit 1
    return $?
  fi

  local owner_repo=""
  if ! owner_repo="$(_rss__origin_owner_repo "$origin_url")"; then
    printf 'error: could not parse owner/repo from origin: %s\n' "$origin_url" >&2
    _rss__exit 1
    return $?
  fi

  if ! git remote set-url origin "${cwd}:${owner_repo}.git"; then
    printf 'error: failed to set origin url\n' >&2
    _rss__exit 1
    return $?
  fi

  # ----------------------------
  # Sort config and write back
  # ----------------------------
  local sorted_cfg=""
  sorted_cfg="$(mktemp)" || {
    printf 'error: mktemp failed\n' >&2
    _rss__exit 1
    return $?
  }

  if ! _rss__sort_ssh_config_by_alias "$cfg" "$sorted_cfg"; then
    rm -f "$sorted_cfg" >/dev/null 2>&1 || true
    printf 'error: failed to sort %s\n' "$cfg" >&2
    _rss__exit 1
    return $?
  fi

  if ! mv -f "$sorted_cfg" "$cfg"; then
    rm -f "$sorted_cfg" >/dev/null 2>&1 || true
    printf 'error: failed to write %s\n' "$cfg" >&2
    _rss__exit 1
    return $?
  fi
  chmod 600 "$cfg" >/dev/null 2>&1 || true

  printf 'Repository registered in ssh config.\n'
  _rss__exit 0
  return $?
}











# -----------------------------------------------------------------------------
# register-ssh-keys
#
# Create a GitHub deploy-key pair and a matching Host entry in ~/.ssh/config.
#
# Notes (important with set -euo pipefail):
# - Avoid pipelines that end with `head -c ...` because the upstream command can
#   get SIGPIPE and return non-zero, which aborts the function under pipefail.
#   Random generation here is implemented without "early-terminating" pipelines.
#
# Usage:
#   register-ssh-keys
# -----------------------------------------------------------------------------
register-ssh-keys() {
  set -euo pipefail

  local ssh_dir="$HOME/.ssh"
  local config_file="$ssh_dir/config"

  mkdir -p "$ssh_dir"
  chmod 700 "$ssh_dir" 2>/dev/null || true

  if ! command -v ssh-keygen >/dev/null 2>&1; then
    echo "error: ssh-keygen not found in PATH" >&2
    return 1
  fi

  # Prefer openssl for clean textual randomness; fall back to python if needed.
  if ! command -v openssl >/dev/null 2>&1 && ! command -v python3 >/dev/null 2>&1; then
    echo "error: need either openssl or python3 to generate randomness" >&2
    return 1
  fi

  # If config exists but is not readable/writable, fail early.
  if [[ -e "$config_file" && ! -r "$config_file" ]]; then
    echo "error: ~/.ssh/config exists but is not readable" >&2
    ls -l "$config_file" >&2 || true
    return 1
  fi
  if [[ -e "$config_file" && ! -w "$config_file" ]]; then
    echo "error: ~/.ssh/config exists but is not writable" >&2
    ls -l "$config_file" >&2 || true
    return 1
  fi

  _create_ssh_host_rand_digits_10() {
    local out
    if command -v openssl >/dev/null 2>&1; then
      # hex -> digits (may be <10; loop)
      while :; do
        out="$(openssl rand -hex 16 | tr -cd '0-9')"
        if [[ ${#out} -ge 10 ]]; then
          printf '%s' "${out:0:10}"
          return 0
        fi
      done
    else
      # python: digits only
      python3 - <<'PY'
import secrets, string
alphabet = string.digits
print("".join(secrets.choice(alphabet) for _ in range(10)))
PY
    fi
  }

  _create_ssh_host_rand_alias_10() {
    local out
    if command -v openssl >/dev/null 2>&1; then
      # base32 gives [A-Z2-7]=text; map to lowercase + digits and trim to 10.
      # We loop to be safe in case mapping reduces length.
      while :; do
        out="$(openssl rand -base64 24 \
          | tr -cd 'A-Za-z0-9' \
          | tr 'A-Z' 'a-z')"
        if [[ ${#out} -ge 10 ]]; then
          printf '%s' "${out:0:10}"
          return 0
        fi
      done
    else
      python3 - <<'PY'
import secrets, string
alphabet = string.ascii_lowercase + string.digits
print("".join(secrets.choice(alphabet) for _ in range(10)))
PY
    fi
  }

  _create_ssh_host_sort_config_by_host_alias() {
    local cfg_path="$1"
    local tmp_path
    tmp_path="$(mktemp)"

    awk '
      function flush_block() {
        if (in_block) {
          idx = ++n
          keys[idx] = cur_key
          blocks[idx] = cur_block
          cur_block = ""
          cur_key = ""
          in_block = 0
        }
      }

      BEGIN {
        preamble = ""
        cur_block = ""
        cur_key = ""
        in_block = 0
        saw_host = 0
        n = 0
      }

      $0 ~ /^[[:space:]]*Host[[:space:]]+/ {
        saw_host = 1
        flush_block()

        in_block = 1
        cur_block = $0 "\n"

        line = $0
        sub(/^[[:space:]]*Host[[:space:]]+/, "", line)
        split(line, a, /[[:space:]]+/)
        cur_key = a[1]
        next
      }

      {
        if (!saw_host) {
          preamble = preamble $0 "\n"
        } else if (in_block) {
          cur_block = cur_block $0 "\n"
        } else {
          preamble = preamble $0 "\n"
        }
      }

      END {
        flush_block()

        for (i = 2; i <= n; i++) {
          k = keys[i]
          b = blocks[i]
          j = i - 1
          while (j >= 1 && keys[j] > k) {
            keys[j+1] = keys[j]
            blocks[j+1] = blocks[j]
            j--
          }
          keys[j+1] = k
          blocks[j+1] = b
        }

        printf "%s", preamble

        for (i = 1; i <= n; i++) {
          gsub(/\n+$/, "\n", blocks[i])
          printf "%s", blocks[i]
          if (i < n) {
            printf "\n"
          }
        }

        if (preamble == "" && n == 0) {
          printf "\n"
        }
      }
    ' "$cfg_path" >"$tmp_path"

    cat "$tmp_path" >"$cfg_path"
    rm -f "$tmp_path"
  }

  # --- generate unique ddd + files ------------------------------------------
  local ddd alias key_path pub_path comment host_header

  while :; do
    ddd="$(_create_ssh_host_rand_digits_10)"
    key_path="$ssh_dir/id_ed25519_${ddd}"
    pub_path="${key_path}.pub"
    if [[ ! -e "$key_path" && ! -e "$pub_path" ]]; then
      break
    fi
  done

  # --- generate unique alias -------------------------------------------------
  while :; do
    alias="$(_create_ssh_host_rand_alias_10)"

    if [[ -f "$config_file" ]]; then
      if grep -Eq "^[[:space:]]*Host[[:space:]]+$alias([[:space:]]+|$)" \
        "$config_file" 2>/dev/null; then
        continue
      fi
    fi
    break
  done

  comment="deploy-key-repo_${ddd}"

  ssh-keygen -t ed25519 -C "$comment" -f "$key_path" -N "" >/dev/null

  chmod 600 "$key_path"
  chmod 644 "$pub_path"

  # --- write config entry ----------------------------------------------------
  if [[ ! -f "$config_file" ]]; then
    : >"$config_file"
  fi
  chmod 600 "$config_file"

  host_header="Host $alias"

  if [[ -s "$config_file" ]]; then
    printf '\n' >>"$config_file"
  fi

  cat >>"$config_file" <<EOF
$host_header
  HostName github.com
  User git
  IdentityFile $key_path
  IdentitiesOnly yes
  StrictHostKeyChecking yes
EOF

  chmod 600 "$config_file"

  _create_ssh_host_sort_config_by_host_alias "$config_file"

  # --- print public key + next steps ----------------------------------------
  local pub_key
  pub_key="$(cat "$pub_path")"

  echo "Include the following public key in your GitHub repository (Settings → Deploy keys → Add deploy key):"
  echo "> PUBLIC KEY: $pub_key"
  echo "Then clone the repository, change directory to its root and run:"
  echo "> register-ssh-host --alias=$alias"
}











# -----------------------------------------------------------------------------
# prune-ssh-config
#
# Goals:
# 1) Remove from ~/.ssh/config any "Host <alias>" block whose alias is NOT an
#    absolute path to an existing directory on the system.
# 2) If a block is removed, also delete the SSH key referenced by its IdentityFile
#    (and its .pub), if any.
# 3) Additionally, delete any deploy-key files under ~/.ssh that are NOT referenced
#    by ANY remaining config entry.
# 4) Ensure the resulting ~/.ssh/config has no two consecutive blank lines.
#
# Definitions:
# - Alias = first token after "Host" on the Host line.
# - A "valid directory alias" means alias begins with "/" AND test -d "$alias".
# - "Referenced key" means the expanded path from an IdentityFile line in a kept
#   Host block.
#
# Notes:
# - Preserves the preamble (anything before the first Host line).
# - Parses blocks starting at ^\s*Host\s+ through before next such line / EOF.
# - Writes ~/.ssh/config atomically and enforces chmod 600.
#
# Usage:
#   prune-ssh-config
# -----------------------------------------------------------------------------
prune-ssh-config() {
  set -euo pipefail

  local ssh_dir="$HOME/.ssh"
  local config_file="$ssh_dir/config"

  if [[ ! -d "$ssh_dir" ]]; then
    echo "error: ~/.ssh not found" >&2
    return 1
  fi

  if [[ ! -f "$config_file" ]]; then
    echo "error: ~/.ssh/config not found" >&2
    return 1
  fi

  if [[ ! -r "$config_file" || ! -w "$config_file" ]]; then
    echo "error: ~/.ssh/config is not readable/writable" >&2
    ls -l "$config_file" >&2 || true
    return 1
  fi

  local tmp_file referenced_list
  tmp_file="$(mktemp)"
  referenced_list="$(mktemp)"

  _prune_expand_identityfile() {
    local raw="$1"
    local expanded="$raw"

    expanded="${expanded#"${expanded%%[![:space:]]*}"}"
    expanded="${expanded%"${expanded##*[![:space:]]}"}"

    if [[ "$expanded" == "~/"* ]]; then
      expanded="$HOME/${expanded#~/}"
    elif [[ "$expanded" == "~" ]]; then
      expanded="$HOME"
    fi

    if [[ "$expanded" == "\$HOME/"* ]]; then
      expanded="$HOME/${expanded#\$HOME/}"
    elif [[ "$expanded" == "\$HOME" ]]; then
      expanded="$HOME"
    fi

    printf '%s' "$expanded"
  }

  _prune_rm_keypair_best_effort() {
    local key_path="$1"
    if [[ -n "$key_path" && -f "$key_path" ]]; then
      rm -f -- "$key_path" || true
    fi
    if [[ -n "$key_path" && -f "${key_path}.pub" ]]; then
      rm -f -- "${key_path}.pub" || true
    fi
  }

  _prune_compress_blank_lines_file() {
    local path="$1"
    local tmp
    tmp="$(mktemp)"

    # Collapse runs of blank lines to a single blank line.
    # Keep all non-blank lines unchanged.
    awk '
      BEGIN { blank = 0 }
      /^[[:space:]]*$/ {
        if (!blank) {
          print ""
          blank = 1
        }
        next
      }
      {
        print
        blank = 0
      }
    ' "$path" >"$tmp"

    cat "$tmp" >"$path"
    rm -f "$tmp"
  }

  # Extract preamble verbatim (everything before the first Host line).
  awk '
    $0 ~ /^[[:space:]]*Host[[:space:]]+/ { exit }
    { print }
  ' "$config_file" >"$tmp_file"

  local block line alias raw_idfile expanded_idfile

  block=""

  _prune_flush_block() {
    local alias_line

    if [[ -z "$block" ]]; then
      return 0
    fi

    alias_line="$(printf '%s' "$block" | awk '
      $0 ~ /^[[:space:]]*Host[[:space:]]+/ {
        sub(/^[[:space:]]*Host[[:space:]]+/, "", $0)
        split($0, a, /[[:space:]]+/)
        print a[1]
        exit
      }
    ')"
    alias="${alias_line:-}"

    raw_idfile="$(printf '%s' "$block" | awk '
      $0 ~ /^[[:space:]]*IdentityFile[[:space:]]+/ {
        sub(/^[[:space:]]*IdentityFile[[:space:]]+/, "", $0)
        print $0
        exit
      }
    ')"

    expanded_idfile=""
    if [[ -n "${raw_idfile:-}" ]]; then
      expanded_idfile="$(_prune_expand_identityfile "$raw_idfile")"
    fi

    if [[ -n "$alias" && "$alias" == /* && -d "$alias" ]]; then
      if [[ -s "$tmp_file" ]]; then
        printf '\n' >>"$tmp_file"
      fi
      printf '%s' "$block" >>"$tmp_file"
      if [[ "${block: -1}" != $'\n' ]]; then
        printf '\n' >>"$tmp_file"
      fi

      if [[ -n "$expanded_idfile" ]]; then
        printf '%s\n' "$expanded_idfile" >>"$referenced_list"
      fi

      block=""
      return 0
    fi

    if [[ -n "$expanded_idfile" ]]; then
      _prune_rm_keypair_best_effort "$expanded_idfile"
    fi

    block=""
    return 0
  }

  while IFS= read -r line || [[ -n "$line" ]]; do
    if [[ "$line" =~ ^[[:space:]]*Host[[:space:]]+ ]]; then
      _prune_flush_block
      block="${line}"$'\n'
    else
      if [[ -n "$block" ]]; then
        block+="${line}"$'\n'
      fi
    fi
  done <"$config_file"

  _prune_flush_block

  # Collapse multiple blank lines in the newly-built config before writing back.
  _prune_compress_blank_lines_file "$tmp_file"

  cat "$tmp_file" >"$config_file"
  rm -f "$tmp_file"
  chmod 600 "$config_file" 2>/dev/null || true

  # Remove any deploy keys not referenced by kept entries.
  sort -u "$referenced_list" -o "$referenced_list" 2>/dev/null || true

  local key_file
  shopt -s nullglob
  for key_file in "$ssh_dir"/id_ed25519_repo_*; do
    if [[ "$key_file" == *.pub ]]; then
      continue
    fi
    if [[ ! -f "$key_file" ]]; then
      continue
    fi
    if ! grep -Fxq -- "$key_file" "$referenced_list" 2>/dev/null; then
      _prune_rm_keypair_best_effort "$key_file"
    fi
  done
  shopt -u nullglob

  rm -f "$referenced_list"

  # Final pass: ensure no consecutive blank lines in the final config.
  _prune_compress_blank_lines_file "$config_file"
  chmod 600 "$config_file" 2>/dev/null || true

  echo "Pruned ~/.ssh/config and removed unreferenced deploy keys."
}
