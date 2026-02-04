#!/usr/bin/env bash
source variables.sh
docker compose -p "${COMPOSE_PROJECT_NAME}" exec -it \
  -u "${CONTAINER_USER}" \
  -w "/home/${CONTAINER_USER}" \
  ubuntu \
  bash -i