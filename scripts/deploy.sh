#!/usr/bin/env bash
# Apply the manifests to the current kubectl context.
#   ./scripts/deploy.sh                       -> deploys the image tag already in kustomization.yaml
#   IMAGE_TAG=abc1234 ./scripts/deploy.sh     -> pins that tag first
set -euo pipefail

cd "$(dirname "$0")/.."

NAMESPACE="${K8S_NAMESPACE:-hello-world}"
REGISTRY="${REGISTRY:-ghcr.io}"
IMAGE_OWNER="${IMAGE_OWNER:-OWNER}"
IMAGE_NAME="${IMAGE_NAME:-hello-world-frontend}"
IMAGE_REPO="${IMAGE_REPO:-$REGISTRY/$IMAGE_OWNER/$IMAGE_NAME}"

echo "==> context: $(kubectl config current-context)"

if [[ -n "${IMAGE_TAG:-}" ]]; then
  echo "==> pinning image $IMAGE_REPO:$IMAGE_TAG"
  (cd k8s && kustomize edit set image "$IMAGE_REPO=$IMAGE_REPO:$IMAGE_TAG")
fi

echo "==> applying manifests"
kubectl apply -k k8s/

echo "==> waiting for rollout"
kubectl -n "$NAMESPACE" rollout status deployment/hello-world-frontend --timeout=180s

kubectl -n "$NAMESPACE" get deploy,pod,svc,ingress
