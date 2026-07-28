#!/usr/bin/env bash
# Stand up a local kind cluster with ingress-nginx, build the image and load it in.
# Everything here is open source: kind (Apache-2.0) + ingress-nginx (Apache-2.0).
set -euo pipefail

cd "$(dirname "$0")/.."

CLUSTER="${CLUSTER:-hello-world}"
IMAGE_REPO="${IMAGE_REPO:-ghcr.io/sriindus/hello-world-frontend}"
IMAGE_TAG="${IMAGE_TAG:-dev}"

# Host ports the ingress is published on. Defaults are unprivileged because macOS
# (and colima's port forwarder) cannot bind ports below 1024 without root.
# On Linux, HTTP_PORT=80 HTTPS_PORT=443 works and gives you clean URLs.
HTTP_PORT="${HTTP_PORT:-8080}"
HTTPS_PORT="${HTTPS_PORT:-8443}"

if ! kind get clusters 2>/dev/null | grep -qx "$CLUSTER"; then
  echo "==> creating kind cluster '$CLUSTER' (ingress on :$HTTP_PORT and :$HTTPS_PORT)"
  kind create cluster --name "$CLUSTER" --config - <<EOF
kind: Cluster
apiVersion: kind.x-k8s.io/v1alpha4
nodes:
  - role: control-plane
    kubeadmConfigPatches:
      - |
        kind: InitConfiguration
        nodeRegistration:
          kubeletExtraArgs:
            node-labels: "ingress-ready=true"
    extraPortMappings:
      - containerPort: 80
        hostPort: ${HTTP_PORT}
        protocol: TCP
      - containerPort: 443
        hostPort: ${HTTPS_PORT}
        protocol: TCP
  - role: worker
EOF
fi

echo "==> installing ingress-nginx"
kubectl apply -f https://raw.githubusercontent.com/kubernetes/ingress-nginx/controller-v1.12.0/deploy/static/provider/kind/deploy.yaml
kubectl -n ingress-nginx wait --for=condition=ready pod \
  --selector=app.kubernetes.io/component=controller --timeout=180s

echo "==> building and loading $IMAGE_REPO:$IMAGE_TAG"
docker build -t "$IMAGE_REPO:$IMAGE_TAG" -f Dockerfile .
kind load docker-image "$IMAGE_REPO:$IMAGE_TAG" --name "$CLUSTER"

echo "==> deploying"
(cd k8s && kustomize edit set image "$IMAGE_REPO=$IMAGE_REPO:$IMAGE_TAG")
kubectl apply -k k8s/
kubectl -n hello-world rollout status deployment/hello-world-frontend --timeout=180s

cat <<EOF

Done. Add the host entry once:
  echo "127.0.0.1 hello-world.local" | sudo tee -a /etc/hosts

Then open http://hello-world.local:${HTTP_PORT}

No sudo? The Host header is what matters, so this works too:
  curl -H 'Host: hello-world.local' http://127.0.0.1:${HTTP_PORT}/api/hello
EOF
