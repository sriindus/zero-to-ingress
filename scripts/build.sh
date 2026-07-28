#!/usr/bin/env bash
# Build (and optionally push) the container image.
#   ./scripts/build.sh                 -> builds ghcr.io/sriindus/hello-world-frontend:<git-sha>
#   PUSH=1 ./scripts/build.sh          -> also pushes
set -euo pipefail

cd "$(dirname "$0")/.."

REGISTRY="${REGISTRY:-ghcr.io}"
IMAGE_OWNER="${IMAGE_OWNER:-sriindus}"
IMAGE_NAME="${IMAGE_NAME:-hello-world-frontend}"
IMAGE_REPO="${IMAGE_REPO:-$REGISTRY/$IMAGE_OWNER/$IMAGE_NAME}"
IMAGE_TAG="${IMAGE_TAG:-$(git rev-parse --short HEAD 2>/dev/null || echo dev)}"

echo "==> building $IMAGE_REPO:$IMAGE_TAG"
docker build -t "$IMAGE_REPO:$IMAGE_TAG" -t "$IMAGE_REPO:latest" -f Dockerfile .

if [[ "${PUSH:-0}" == "1" ]]; then
  echo "==> pushing $IMAGE_REPO:$IMAGE_TAG"
  docker push "$IMAGE_REPO:$IMAGE_TAG"
  docker push "$IMAGE_REPO:latest"
fi

echo "==> done: $IMAGE_REPO:$IMAGE_TAG"
