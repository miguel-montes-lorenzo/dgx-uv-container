COMPOSE_PROJECT_NAME=""
CONTAINER_USER="guest"

# uv
PERSISTENT_UV_CACHE=false

# Host paths
HOST_VOLUME_PATH="/home/${USER}/workdata/"
DATA_SUBDIR="data"
SSH_SUBDIR="ssh"
UV_CACHE_SUBDIR="uv_cache"


# Define dynamic (user-unique & dir-unique) COMPOSE_PROJECT_NAME
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


export COMPOSE_PROJECT_NAME SERVICE CONTAINER_USER
export PERSISTENT_UV_CACHE
export HOST_VOLUME_PATH DATA_SUBDIR SSH_SUBDIR UV_CACHE_SUBDIR
