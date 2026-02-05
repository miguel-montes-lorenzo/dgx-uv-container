# DOCKER
COMPOSE_PROJECT_NAME="TO BE DEFINED IN __update_compose_project_name"
CONTAINER_USER="guest"

# CONTROL
COMPOSE_STATE_DIR="/run/control/compose-running"
CLEANUP_STATE_DIR="/run/control/cache-cleanup-time"
CACHE_CLEANUP_TIME=3600

# UV
PERSISTENT_UV_CACHE=false

# HOST PATHS
HOST_VOLUME_PATH="/home/${USER}/workdata/"
DATA_SUBDIR="data"
SSH_SUBDIR="ssh"
UV_CACHE_SUBDIR="uv_cache"


# DEFINE DYNAMIC (USER-UNIQUE & DIR-UNIQUE) COMPOSE_PROJECT_NAME
__update_compose_project_name() {
  local user="$USER"
  local dir
  dir="$(basename "$PWD")"

  COMPOSE_PROJECT_NAME="$(
    printf '%s-%s' "$user" "$dir" \
    | tr '[:upper:]' '[:lower:]' \
    | sed 's|[^a-z0-9_-]|-|g'
  )"
  export COMPOSE_PROJECT_NAME
}
__update_compose_project_name
if [[ ";$PROMPT_COMMAND;" == *";__update_compose_project_name;"* ]]; then
  :
elif [[ -z "$PROMPT_COMMAND" ]]; then
  PROMPT_COMMAND="__update_compose_project_name"
else
  PROMPT_COMMAND="__update_compose_project_name; $PROMPT_COMMAND"
fi

# EXPORT VARIABLES
export COMPOSE_PROJECT_NAME CONTAINER_USER
export COMPOSE_STATE_DIR CLEANUP_STATE_DIR CACHE_CLEANUP_TIME
export PERSISTENT_UV_CACHE
export HOST_VOLUME_PATH DATA_SUBDIR SSH_SUBDIR UV_CACHE_SUBDIR
