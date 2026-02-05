#!/usr/bin/env bash

source variables.sh

echo "[attach] Waiting for docker compose service '${COMPOSE_PROJECT_NAME}' to become ready..."
# wait until container is up and state file exists
until docker compose -p "${COMPOSE_PROJECT_NAME}" exec -T ubuntu \
  test -f "${COMPOSE_STATE_DIR}" >/dev/null 2>&1; do
  sleep 0.5
done
echo "[attach] Container is up. Waiting for initialization to finish..."
# wait until state becomes "false"
while true; do
  value="$(
    docker compose -p "${COMPOSE_PROJECT_NAME}" exec -T ubuntu \
      cat "${COMPOSE_STATE_DIR}" 2>/dev/null || true
  )"
  [[ "${value}" == "false" ]] && break
  sleep 0.5
done
echo "[attach] Initialization complete. Attaching interactive shell."

# attach interactive shell
docker compose -p "${COMPOSE_PROJECT_NAME}" exec -it \
  -u "${CONTAINER_USER}" \
  -w "/home/${CONTAINER_USER}" \
  ubuntu \
  bash -i
