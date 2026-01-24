#!/usr/bin/env bash
# set -euo pipefail
source variables.sh

export PROJECT SERVICE CONTAINER_USER
export HOST_VOLUME_PATH DATA_DIR SSH_DIR UV_CACHE_DIR

# Ensure required directories exist
mkdir -p "${HOST_VOLUME_PATH}/${DATA_DIR}"
mkdir -p "${HOST_VOLUME_PATH}/${SSH_DIR}"
mkdir -p "${HOST_VOLUME_PATH}/${UV_CACHE_DIR}"

# (Optional but recommended) sane permissions for SSH dir
chmod 700 "${HOST_VOLUME_PATH}/${SSH_DIR}" || true

export HOST_UID="$(id -u)"
export HOST_GID="$(id -g)"

if docker compose -p "${PROJECT}" ps -q >/dev/null 2>&1 \
   && [ -n "$(docker compose -p "${PROJECT}" ps -q)" ]; then
    docker compose -p "${PROJECT}" down
fi
docker compose -p "${PROJECT}" up -d --build
docker compose -p "${PROJECT}" ps
