#!/usr/bin/env bash
source variables.sh
docker compose -p "${PROJECT}" exec -it \
  -u "${CONTAINER_USER}" \
  -w "/home/${CONTAINER_USER}" \
  ubuntu \
  bash -l