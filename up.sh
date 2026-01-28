#!/usr/bin/env bash
# set -euo pipefail
source variables.sh
git config core.hooksPath .githooks

export PROJECT SERVICE CONTAINER_USER
export PERSISTENT_UV_CACHE
export HOST_VOLUME_PATH DATA_SUBDIR SSH_SUBDIR UV_CACHE_SUBDIR

# Ensure required directories exist
mkdir -p "${HOST_VOLUME_PATH}/${DATA_SUBDIR}"
mkdir -p "${HOST_VOLUME_PATH}/${SSH_SUBDIR}"
mkdir -p "${HOST_VOLUME_PATH}/${UV_CACHE_SUBDIR}"

# (Optional but recommended) sane permissions for SSH dir
chmod 700 "${HOST_VOLUME_PATH}/${SSH_SUBDIR}" || true

export HOST_UID="$(id -u)"
export HOST_GID="$(id -g)"

if docker compose -p "${PROJECT}" ps -q >/dev/null 2>&1 \
   && [ -n "$(docker compose -p "${PROJECT}" ps -q)" ]; then
    docker compose -p "${PROJECT}" down
fi
docker compose -p "${PROJECT}" up -d --build
# docker compose -p "${PROJECT}" build --no-cache --progress=plain
docker compose -p "${PROJECT}" ps
