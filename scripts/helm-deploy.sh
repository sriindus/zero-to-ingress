#!/usr/bin/env bash
# Deploy via the Helm chart (the manifest-based alternative is scripts/deploy.sh).
#   ./scripts/helm-deploy.sh                        -> release "hello-world-frontend" in ns hello-world
#   IMAGE_TAG=abc1234 ./scripts/helm-deploy.sh      -> pin an image tag
#   VALUES=helm/values-prod.yaml ./scripts/helm-deploy.sh
#   DRY_RUN=1 ./scripts/helm-deploy.sh              -> render and validate only
set -euo pipefail

cd "$(dirname "$0")/.."

CHART="helm/hello-world-frontend"
# Matching the release name to the chart name keeps resource names free of the
# "hello-world-frontend-hello-world-frontend" stutter.
RELEASE="${RELEASE:-hello-world-frontend}"
NAMESPACE="${K8S_NAMESPACE:-hello-world}"

args=(upgrade --install "$RELEASE" "$CHART"
      --namespace "$NAMESPACE" --create-namespace
      --wait --timeout 180s)

[[ -n "${IMAGE_TAG:-}" ]] && args+=(--set "image.tag=$IMAGE_TAG")
[[ -n "${VALUES:-}" ]] && args+=(--values "$VALUES")

if [[ "${DRY_RUN:-0}" == "1" ]]; then
  args+=(--dry-run)
  echo "==> dry run only"
else
  echo "==> context: $(kubectl config current-context)"
fi

echo "==> helm ${args[*]}"
helm "${args[@]}"

[[ "${DRY_RUN:-0}" == "1" ]] && exit 0

echo "==> running chart tests"
helm test "$RELEASE" --namespace "$NAMESPACE" --timeout 120s

kubectl -n "$NAMESPACE" get deploy,pod,svc,ingress
