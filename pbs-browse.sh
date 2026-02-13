#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
IMAGE="${IMAGE:-pbs-snapshot-browser}"
AUTH_FILE="${AUTH_FILE:-${SCRIPT_DIR}/auth.env}"

if [[ ! -f "$AUTH_FILE" ]]; then
  echo "auth file not found: $AUTH_FILE" >&2
  exit 1
fi

if ! docker image inspect "$IMAGE" >/dev/null 2>&1; then
  echo "image not found locally: $IMAGE"
  echo "building image from ${SCRIPT_DIR}/Dockerfile ..."
  docker build -t "$IMAGE" "$SCRIPT_DIR"
fi

docker run --rm -it \
  --privileged \
  --tmpfs /tmp \
  --tmpfs /root/.cache \
  --device /dev/fuse \
  --cap-add SYS_ADMIN \
  --security-opt apparmor:unconfined \
  -v "${AUTH_FILE}:/app/auth.env:ro" \
  "$IMAGE"
