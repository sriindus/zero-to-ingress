# hello-world-k8s

A Node.js "Hello World" front end, containerized on Alpine Linux, deployed to Kubernetes
behind an nginx ingress, and shipped by a Jenkins pipeline. Every component is open source.

| Concern | Choice | License |
| --- | --- | --- |
| Runtime | Node.js 22 | MIT |
| Web server | Express 4 | MIT |
| Base image | `node:22-alpine` | MIT / Alpine (BSD-ish) |
| Init | tini | MIT |
| Orchestration | Kubernetes + Kustomize | Apache-2.0 |
| Ingress | ingress-nginx | Apache-2.0 |
| CI/CD | Jenkins LTS | MIT |
| Local cluster | kind | Apache-2.0 |

## Layout

```
app/                    Node.js front end (Express + static assets)
  server.js             HTTP server, /api/hello, /healthz, /readyz
  public/               index.html, styles.css, app.js
  test/                 node:test suite (no extra test deps)
Dockerfile              Multi-stage Alpine build, non-root, read-only rootfs
docker-compose.yml      Run the production image locally
k8s/                    Namespace, ServiceAccount, ConfigMap, Deployment,
                        Service, Ingress, HPA, PDB, kustomization
Jenkinsfile             test -> build -> push -> deploy -> smoke test
jenkins/                Dockerfile + compose to run a Jenkins controller locally
scripts/                build.sh, deploy.sh, kind-cluster.sh, github-init.sh
```

## Before you start: two placeholders

Replace `OWNER` with your GitHub username/org in:

- [k8s/deployment.yaml](k8s/deployment.yaml) (`image:`)
- [k8s/kustomization.yaml](k8s/kustomization.yaml) (`images[].name`)
- [Jenkinsfile](Jenkinsfile) (`IMAGE_OWNER`)

And pick your hostname in [k8s/ingress.yaml](k8s/ingress.yaml) — it ships as
`hello-world.local` for local use.

```bash
# one-liner for the image owner
grep -rl 'OWNER' k8s Jenkinsfile scripts | xargs sed -i '' 's|OWNER|your-github-user|g'
```

## 1. Run it locally

```bash
cd app
npm install
npm start          # http://localhost:3000
npm test           # 5 tests, no network needed
```

## 2. Build the container

```bash
./scripts/build.sh                          # tags with the short git SHA
docker compose up --build                   # or run it via compose
curl localhost:3000/api/hello
```

The image runs as uid 1000 with a read-only root filesystem, all capabilities dropped,
and `/tmp` as the only writable mount.

## 3. Deploy to Kubernetes

Any cluster works. For a throwaway local one:

```bash
brew install kind kubectl kustomize          # macOS
./scripts/kind-cluster.sh                    # creates cluster + ingress-nginx + deploys
echo "127.0.0.1 hello-world.local" | sudo tee -a /etc/hosts
open http://hello-world.local
```

Against an existing cluster:

```bash
kubectl apply -k k8s/
kubectl -n hello-world rollout status deployment/hello-world-frontend
kubectl -n hello-world get pod,svc,ingress
```

If your cluster pulls from a private registry, add the pull secret:

```bash
kubectl -n hello-world create secret docker-registry ghcr-pull \
  --docker-server=ghcr.io --docker-username=YOUR_USER --docker-password=YOUR_PAT
# then add to k8s/deployment.yaml under spec.template.spec:
#   imagePullSecrets:
#     - name: ghcr-pull
```

### What the manifests give you

- **Deployment** — 2 replicas, rolling update with `maxUnavailable: 0`, startup/liveness/
  readiness probes, CPU+memory requests and limits, `preStop` sleep so the ingress drains
  the pod before it dies, topology spread across nodes.
- **Service** — ClusterIP on port 80 → container port 3000.
- **Ingress** — `ingressClassName: nginx`, host-based routing, TLS block ready to
  uncomment once cert-manager is installed.
- **HPA** — scales 2→6 pods at 70% CPU (needs metrics-server in the cluster).
- **PodDisruptionBudget** — keeps at least 1 pod up during node drains.

## 4. Push to GitHub

```bash
brew install gh && gh auth login
./scripts/github-init.sh                     # REPO_NAME=... VISIBILITY=private to override
```

Or manually:

```bash
git init -b main && git add -A && git commit -m "initial commit"
git remote add origin git@github.com:YOUR_USER/hello-world-k8s.git
git push -u origin main
```

## 5. Jenkins pipeline

Run a controller locally (Docker-outside-of-Docker, so it builds with your host daemon):

```bash
docker compose -f jenkins/docker-compose.yml up -d --build
docker compose -f jenkins/docker-compose.yml exec jenkins \
  cat /var/jenkins_home/secrets/initialAdminPassword
# open http://localhost:8080
```

The image pre-installs `docker`, `kubectl`, `kustomize` and the plugins in
[jenkins/plugins.txt](jenkins/plugins.txt).

Then add two credentials under **Manage Jenkins → Credentials**:

| ID | Kind | Contents |
| --- | --- | --- |
| `ghcr-credentials` | Username with password | GitHub user + PAT with `write:packages` |
| `kubeconfig` | Secret file | your cluster's kubeconfig |

Create a **Multibranch Pipeline** job pointed at your GitHub repo. Jenkins finds the
`Jenkinsfile` automatically and runs:

1. **Checkout** — resolves the short SHA used as the image tag
2. **Install & Test** — `npm ci && npm test` inside `node:22-alpine`
3. **Lint Manifests** — `kubectl kustomize k8s/` must render
4. **Build & Push Image** — `docker build` + push `:<sha>` and `:latest` to GHCR
5. **Deploy** — `kustomize edit set image` then `kubectl apply -k`, waits on rollout (main only)
6. **Smoke Test** — in-cluster `curl` against `/api/hello` (main only)

For webhook builds, point GitHub at `http://<jenkins-host>/github-webhook/`.

If your Jenkins itself runs in Kubernetes, swap the Docker build stage for
[Kaniko](https://github.com/GoogleContainerTools/kaniko) or
[Buildah](https://buildah.io/) — both open source and rootless-friendly.

## Endpoints

| Path | Purpose |
| --- | --- |
| `/` | The Hello World page |
| `/api/hello` | JSON: message, environment, version, pod hostname, timestamp |
| `/healthz` | Liveness probe |
| `/readyz` | Readiness probe |

## Configuration

Set via [k8s/configmap.yaml](k8s/configmap.yaml) or the environment:

| Variable | Default | Meaning |
| --- | --- | --- |
| `PORT` | `3000` | Listen port |
| `HOST` | `0.0.0.0` | Bind address |
| `APP_MESSAGE` | `Hello World` | Headline shown on the page |
| `APP_ENV` | `local` | Environment label |
| `APP_VERSION` | package version | Displayed build version |

## Troubleshooting

```bash
kubectl -n hello-world logs -l app.kubernetes.io/name=hello-world-frontend --tail=50
kubectl -n hello-world describe pod -l app.kubernetes.io/name=hello-world-frontend
kubectl -n hello-world port-forward svc/hello-world-frontend 8080:80   # bypass ingress
kubectl -n ingress-nginx logs -l app.kubernetes.io/component=controller
```

- **Ingress 404** — the `Host` header must match `k8s/ingress.yaml`; check `/etc/hosts`.
- **`ImagePullBackOff`** — `OWNER` still unreplaced, or a pull secret is missing.
- **HPA shows `<unknown>`** — install metrics-server.
