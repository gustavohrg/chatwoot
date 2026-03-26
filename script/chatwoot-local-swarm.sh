#!/usr/bin/env bash

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
STACK_NAME="${STACK_NAME:-chatwoot-local}"
REGISTRY_NAME="${REGISTRY_NAME:-chatwoot-local-registry}"
REGISTRY_PORT="${REGISTRY_PORT:-5000}"
ENV_FILE="${ENV_FILE:-${ROOT_DIR}/deployment/swarm/chatwoot-local-assigned-only.env}"
STACK_FILE="${STACK_FILE:-${ROOT_DIR}/deployment/swarm/chatwoot-local-assigned-only.stack.yml}"
IMAGE_REPO="${IMAGE_REPO:-localhost:${REGISTRY_PORT}/chatwoot}"
IMAGE_TAG="${IMAGE_TAG:-local-assigned-only}"
CHATWOOT_IMAGE="${CHATWOOT_IMAGE:-${IMAGE_REPO}:${IMAGE_TAG}}"

require_file() {
  local path="$1"
  if [[ ! -f "${path}" ]]; then
    echo "Missing required file: ${path}" >&2
    exit 1
  fi
}

ensure_swarm() {
  local swarm_state
  swarm_state="$(docker info --format '{{.Swarm.LocalNodeState}}')"

  if [[ "${swarm_state}" != "active" ]]; then
    docker swarm init >/dev/null
  fi
}

ensure_registry() {
  if docker ps --format '{{.Names}}' | grep -qx "${REGISTRY_NAME}"; then
    return
  fi

  if docker ps -a --format '{{.Names}}' | grep -qx "${REGISTRY_NAME}"; then
    docker start "${REGISTRY_NAME}" >/dev/null
    return
  fi

  docker run -d \
    --restart unless-stopped \
    -p "${REGISTRY_PORT}:5000" \
    --name "${REGISTRY_NAME}" \
    registry:2 >/dev/null
}

build_and_push_image() {
  docker buildx build \
    --platform linux/amd64 \
    --tag "${CHATWOOT_IMAGE}" \
    --push \
    "${ROOT_DIR}"
}

deploy_stack() {
  (
    cd "$(dirname "${STACK_FILE}")"
    export CHATWOOT_IMAGE
    docker stack deploy \
      --compose-file "$(basename "${STACK_FILE}")" \
      --with-registry-auth \
      "${STACK_NAME}"
  )
}

wait_for_rails_container() {
  local container_id=""

  for _ in $(seq 1 60); do
    container_id="$(docker ps \
      --filter "label=com.docker.swarm.service.name=${STACK_NAME}_rails" \
      --format '{{.ID}}' | head -n 1)"
    if [[ -n "${container_id}" ]]; then
      echo "${container_id}"
      return
    fi
    sleep 2
  done

  echo "Timed out waiting for the ${STACK_NAME}_rails container" >&2
  exit 1
}

prepare_database() {
  local rails_container
  rails_container="$(wait_for_rails_container)"

  for _ in $(seq 1 30); do
    if docker exec "${rails_container}" bundle exec rails db:chatwoot_prepare; then
      return
    fi
    sleep 2
  done

  echo "Timed out waiting for db:chatwoot_prepare to succeed" >&2
  exit 1
}

print_next_steps() {
  cat <<EOF
Local Swarm stack deployed.

Open: http://localhost:$(grep '^RAILS_PORT=' "${ENV_FILE}" | cut -d'=' -f2)

Create the first admin account in the browser, then seed richer sample data with:

docker exec -it \$(docker ps --filter label=com.docker.swarm.service.name=${STACK_NAME}_rails -q | head -n1) \\
  bundle exec rails runner "Seeders::AccountSeeder.new(account: Account.last).perform!"

Recommended verification:
1. Create Agent A and Agent B.
2. Ensure the account has one conversation assigned to each agent plus one unassigned conversation.
3. Log in as Agent A and confirm only Agent A's assigned conversations are visible.
4. Verify direct URL access, search, and bulk actions do not expose Agent B or unassigned conversations.
EOF
}

main() {
  require_file "${ENV_FILE}"
  require_file "${STACK_FILE}"
  ensure_swarm
  ensure_registry
  build_and_push_image
  deploy_stack
  prepare_database
  print_next_steps
}

main "$@"
