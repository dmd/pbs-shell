#!/usr/bin/env sh
set -eu

IMAGE="${IMAGE:-ghcr.io/dmd/pbs-shell:latest}"
AUTH_FILE="${AUTH_FILE:-${PWD}/auth.env}"
PULL_IMAGE="${PULL_IMAGE:-1}"
LVM_SUPPRESS_FD_WARNINGS="${LVM_SUPPRESS_FD_WARNINGS:-1}"

if [ ! -f "$AUTH_FILE" ]; then
  echo "auth file not found: $AUTH_FILE" >&2
  exit 1
fi

if [ "$PULL_IMAGE" = "1" ]; then
  echo "pulling image: $IMAGE"
  docker pull "$IMAGE"
elif ! docker image inspect "$IMAGE" >/dev/null 2>&1; then
  echo "image not found locally and PULL_IMAGE=0: $IMAGE" >&2
  exit 1
fi

docker run --rm -it \
  --privileged \
  --tmpfs /tmp \
  --tmpfs /root/.cache \
  --device /dev/fuse \
  --cap-add SYS_ADMIN \
  --security-opt apparmor:unconfined \
  -e "LVM_SUPPRESS_FD_WARNINGS=${LVM_SUPPRESS_FD_WARNINGS}" \
  -v "${AUTH_FILE}:/app/auth.env:ro" \
  "$IMAGE"
