# zero-to-ingress

A Node.js "Hello World" front end, containerized on Alpine Linux, deployed to Kubernetes
behind an nginx ingress, and shipped by a Jenkins pipeline. Every component is open source.

| Concern | Choice | License |
| --- | --- | --- |
| Runtime | Node.js 22 | MIT |
| Web server | Express 4 | MIT |
| Base image | `node:22-alpine` | MIT / Alpine (BSD-ish) |
| Init | tini | MIT |
| Orchestration | Kubernetes + Kustomize | Apache-2.0 |
| Packaging | Helm 3 | Apache-2.0 |
| Ingress | ingress-nginx | Apache-2.0 |
| Autoscaling metrics | metrics-server | Apache-2.0 |
| CI/CD | Jenkins LTS | MIT |
| Local cluster | kind + colima | Apache-2.0 / MIT |

## Layout

```
app/                    Node.js front end (Express + static assets)
  server.js             HTTP server, /api/hello, /healthz, /readyz
  public/               index.html, styles.css, app.js
  test/                 node:test suite (no extra test deps)
Dockerfile              Multi-stage Alpine build, non-root, read-only rootfs
docker-compose.yml      Run the production image locally
k8s/                    Plain manifests: Namespace, ServiceAccount, ConfigMap,
                        Deployment, Service, Ingress, HPA, PDB, kustomization
helm/                   The same app as a Helm chart (values-driven)
  hello-world-frontend/ Chart.yaml, values.yaml, templates/
  values-prod.yaml      Example production overrides
Jenkinsfile             test -> build -> push -> deploy -> smoke test
jenkins/                Dockerfile + compose to run a Jenkins controller locally
scripts/                build.sh, deploy.sh, helm-deploy.sh, kind-cluster.sh,
                        github-init.sh
```

**Two deployment paths, deliberately.** [k8s/](k8s/) is the readable, no-tooling
version — good for learning and for `kubectl apply -k`. [helm/](helm/) is the
parameterized version for promoting one artifact across environments. They render
functionally identical resources; see [Manifests vs Helm](#manifests-vs-helm).

## Coordinates

- Repository: <https://github.com/sriindus/zero-to-ingress>
- Image: `ghcr.io/sriindus/hello-world-frontend`
- Ingress host: `hello-world.local` — change it in [k8s/ingress.yaml](k8s/ingress.yaml)
  when you have a real domain

If you fork this under a different account, the image owner appears in
[k8s/deployment.yaml](k8s/deployment.yaml), [k8s/kustomization.yaml](k8s/kustomization.yaml),
[Jenkinsfile](Jenkinsfile) and the [scripts/](scripts/):

```bash
grep -rl 'sriindus' k8s Jenkinsfile scripts | xargs sed -i '' 's|sriindus|your-github-user|g'
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

Any cluster works. For a throwaway local one on macOS:

```bash
brew install colima docker kubectl kustomize kind
colima start --cpu 4 --memory 6 --disk 30     # MIT-licensed Docker Desktop alternative
IMAGE_TAG=dev ./scripts/kind-cluster.sh       # cluster + ingress-nginx + deploy
```

The ingress lands on `localhost:8080` — macOS won't let a non-root process bind port 80,
so the script publishes 8080/8443 by default. On Linux, `HTTP_PORT=80 HTTPS_PORT=443
./scripts/kind-cluster.sh` gives you clean URLs.

```bash
# no sudo needed — the Host header is what the ingress routes on
curl -H 'Host: hello-world.local' http://127.0.0.1:8080/api/hello

# or, for a browsable URL: http://hello-world.local:8080
echo "127.0.0.1 hello-world.local" | sudo tee -a /etc/hosts
```

Against an existing cluster:

```bash
kubectl apply -k k8s/
kubectl -n hello-world rollout status deployment/hello-world-frontend
kubectl -n hello-world get pod,svc,ingress
```

Nothing here needs registry credentials if the GHCR package is public, which is the
recommended setup — see [Credentials](#credentials-what-each-job-actually-needs) for the
private-package alternative.

### What the manifests give you

- **Deployment** — 2 replicas, rolling update with `maxUnavailable: 0`, startup/liveness/
  readiness probes, CPU+memory requests and limits, `preStop` sleep so the ingress drains
  the pod before it dies, topology spread across nodes.
- **Service** — ClusterIP on port 80 → container port 3000.
- **Ingress** — `ingressClassName: nginx`, host-based routing, TLS block ready to
  uncomment once cert-manager is installed.
- **HPA** — scales 2→6 pods at 70% CPU. `kind-cluster.sh` installs metrics-server, without
  which the HPA reads `cpu: <unknown>` and never scales.
- **PodDisruptionBudget** — keeps at least 1 pod up during node drains.

## 4. Or deploy with Helm

The chart deploys the same app from the same image; pick whichever fits. The manifests
are not going anywhere.

```bash
brew install helm

# Release name matches the chart name on purpose: it collapses the generated
# resource names to "hello-world-frontend" instead of stuttering.
helm upgrade --install hello-world-frontend helm/hello-world-frontend \
  --namespace hello-world --create-namespace \
  --set image.tag=dev --wait

helm test hello-world-frontend -n hello-world    # curls /api/hello from inside the cluster
```

Or use the wrapper, which does the install and the tests together:

```bash
./scripts/helm-deploy.sh                              # defaults
IMAGE_TAG=abc1234 ./scripts/helm-deploy.sh            # pin a build
VALUES=helm/values-prod.yaml ./scripts/helm-deploy.sh # environment overrides
DRY_RUN=1 ./scripts/helm-deploy.sh                    # render and validate only
```

Everyday operations:

```bash
helm diff upgrade hello-world-frontend helm/hello-world-frontend   # needs helm-diff plugin
helm history hello-world-frontend -n hello-world
helm rollback hello-world-frontend 1 -n hello-world
helm uninstall hello-world-frontend -n hello-world
```

### Values worth knowing

Full list with comments in [helm/hello-world-frontend/values.yaml](helm/hello-world-frontend/values.yaml).

| Value | Default | Notes |
| --- | --- | --- |
| `image.tag` | `""` | Falls back to `Chart.appVersion`. CI sets this per build. |
| `replicaCount` | `2` | **Ignored when `autoscaling.enabled`** — see the footgun below. |
| `autoscaling.enabled` | `true` | Omits `spec.replicas` so the HPA owns the count. |
| `ingress.hosts[0].host` | `hello-world.local` | Set to your real domain. |
| `ingress.tls` | `[]` | Fill in with cert-manager for HTTPS. |
| `config.appMessage` | `Hello World` | Rendered into the ConfigMap. |
| `restartOnConfigChange` | `true` | Checksum annotation rolls pods on config edits. |
| `preStopSleepSeconds` | `5` | Ingress drain window. `0` disables. |
| `imagePullSecrets` | `[]` | `[{name: ghcr-pull}]` for a private package. |

> **Footgun worth knowing.** With `autoscaling.enabled: true` the chart omits
> `spec.replicas` so Helm and the HPA don't fight on every upgrade. On a cluster with no
> metrics source the HPA can't act, so you get **1 pod, not 2**. Either install
> metrics-server or deploy with `--set autoscaling.enabled=false --set replicaCount=2`.

### Manifests vs Helm

Rendered output was compared field by field. Everything functional matches: rollout
strategy, all three probes, both security contexts, resources, volumes, topology spread,
service ports, ingress rules, ConfigMap data, HPA thresholds, PDB. Three intentional
differences:

| | `k8s/` | `helm/` |
| --- | --- | --- |
| ConfigMap name | `hello-world-config` | release-scoped, `hello-world-frontend` |
| Ingress backend port | by name (`http`) | by number (`80`) — Helm convention |
| `spec.replicas` | `2`, explicit | omitted, HPA owns it |

Verify for yourself:

```bash
kubectl kustomize k8s/ > /tmp/raw.yaml
helm template hello-world-frontend helm/hello-world-frontend -n hello-world > /tmp/helm.yaml
diff <(grep -v 'app.kubernetes.io\|helm.sh' /tmp/raw.yaml) \
     <(grep -v 'app.kubernetes.io\|helm.sh' /tmp/helm.yaml)
```

Don't run both into the same namespace — the object names collide and Helm will refuse to
adopt resources it didn't create.

## 5. Push to GitHub

The repo exists and `origin` is already configured, so this is only an auth question.

**Use SSH, not a token.** There's no expiry to track, no scope to over-grant, and the key
is revocable on its own:

```bash
ssh-keygen -t ed25519 -C "laptop"
gh ssh-key add ~/.ssh/id_ed25519.pub          # or paste it at github.com/settings/keys
git remote set-url origin git@github.com:sriindus/zero-to-ingress.git
git push -u origin main
```

Over HTTPS instead, put the token in the macOS keychain — never in a file in the repo, and
never in a command that lands in `~/.zsh_history`:

```bash
git config --global credential.helper osxkeychain
git push -u origin main
# Username: sriindus
# Password: paste the personal access token (not your account password)
```

The keychain caches it after the first push, so later pushes are silent.

For `gh` itself, prefer the browser flow over pasting a token — you end up with a
revocable OAuth grant instead of a credential to manage:

```bash
gh auth login          # choose "Login with a web browser"
```

[scripts/github-init.sh](scripts/github-init.sh) handles the create-and-push case from
scratch, for the next project.

### Credentials: what each job actually needs

Because this repo is public, most of these need nothing at all. One token, in one place,
is enough for the whole pipeline.

| Job | Credential | Notes |
| --- | --- | --- |
| `git push` from your laptop | **SSH key** | No token, no expiry. See above. |
| Jenkins clones the repo | **none** | Public repo — anonymous HTTPS clone works. |
| Jenkins pushes to GHCR | **classic PAT, `write:packages`** | The only token required. |
| Cluster pulls the image | **none** | Make the package public; public packages pull anonymously. |

[GitHub Packages only supports classic tokens][ghcr-auth] — fine-grained tokens do not
cover Packages, so this one place can't be fine-grained. Keep it narrow instead:

- Scopes: `write:packages` and `read:packages`. **Not** `repo`, not `workflow`, not
  anything under `admin:`.
- Set a 90-day expiry. Never "no expiration".
- Name it `jenkins-ghcr` so the last-used column on
  [github.com/settings/tokens](https://github.com/settings/tokens) means something.
- It lives in the Jenkins `ghcr-credentials` credential and nowhere else.

Be aware of the blast radius: a classic `write:packages` token can write **every** package
on the account, not just this one. That's inherent to classic scopes and the reason for the
short expiry. On a real project, a dedicated bot account holding the CI token keeps a CI
leak away from your personal identity.

After the first image push, make the package public at
`github.com/users/sriindus/packages/container/hello-world-frontend/settings`. The cluster
then needs no pull secret, and the `ImagePullBackOff` failure mode disappears entirely.

If you keep the package private instead, the cluster needs a read-only token:

```bash
kubectl -n hello-world create secret docker-registry ghcr-pull \
  --docker-server=ghcr.io --docker-username=sriindus --docker-password=$READ_ONLY_PAT
# manifests: add imagePullSecrets to k8s/deployment.yaml
# helm:      --set 'imagePullSecrets[0].name=ghcr-pull'
```

One more storage note: `docker login` writes credentials to `~/.docker/config.json` as
**base64, which is encoding and not encryption**. Add `"credsStore": "osxkeychain"` to that
file to keep them in the keychain instead.

[ghcr-auth]: https://docs.github.com/en/packages/working-with-a-github-packages-registry/working-with-the-container-registry

### Repository protections in effect

The repo is public, so it is already read-only to everyone but the owner — forks and pull
requests are the only way in, and merging is the maintainer's call. On top of that:

| Setting | State | Effect |
| --- | --- | --- |
| Force pushes to `main` | blocked | `git push --force` is rejected |
| Deleting `main` | blocked | the branch cannot be removed |
| Applies to admins | yes | the two rules above cover the owner too |
| Pull requests / approvals | not required | direct pushes to `main` still work |
| Secret scanning + push protection | enabled | a commit containing a token is refused |
| Dependabot alerts | enabled | notifies on vulnerable dependencies |

Reproduce on a fork of your own:

```bash
gh api -X PUT repos/OWNER/REPO/branches/main/protection --input - <<'JSON'
{"required_status_checks":null,"enforce_admins":true,
 "required_pull_request_reviews":null,"restrictions":null,
 "allow_force_pushes":false,"allow_deletions":false}
JSON
gh api -X PUT repos/OWNER/REPO/vulnerability-alerts
```

To force-push in an emergency, lift protection, push, then restore it:

```bash
gh api -X DELETE repos/sriindus/zero-to-ingress/branches/main/protection
```

## 6. Jenkins pipeline

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
| `ghcr-credentials` | Username with password | `sriindus` + the `jenkins-ghcr` classic PAT ([scopes](#credentials-what-each-job-actually-needs)) |
| `kubeconfig` | Secret file | your cluster's kubeconfig |

No git credential is needed — the repo is public, so Jenkins clones it anonymously. Leave
the credential field empty when configuring the job source.

Both of these are secret material at rest: Jenkins encrypts `credentials.xml` with a key
under `$JENKINS_HOME/secrets/`, so a backup of the `jenkins_home` volume carries the token
and the kubeconfig together. Treat that volume accordingly.

Create a **Multibranch Pipeline** job pointed at your GitHub repo. Jenkins finds the
`Jenkinsfile` automatically and runs:

1. **Checkout** — resolves the short SHA used as the image tag
2. **Install & Test** — `npm ci && npm test` inside `node:22-alpine`
3. **Lint Manifests** — `kubectl kustomize k8s/` must render
4. **Build & Push Image** — `docker build` + push `:<sha>` and `:latest` to GHCR
5. **Deploy** — `kustomize edit set image` then `kubectl apply -k`, waits on rollout (main only)
6. **Smoke Test** — in-cluster `curl` against `/api/hello` (main only)

For webhook builds, point GitHub at `http://<jenkins-host>/github-webhook/`.

The pipeline deploys with kustomize. [jenkins/Dockerfile](jenkins/Dockerfile) also
installs `helm`, so switching the deploy stage to the chart is just a matter of replacing
that stage's shell body:

```groovy
sh '''
  helm upgrade --install hello-world-frontend helm/hello-world-frontend \
    --namespace "$K8S_NAMESPACE" --create-namespace \
    --set image.tag="$IMAGE_TAG" --wait --timeout 180s
  helm test hello-world-frontend --namespace "$K8S_NAMESPACE"
'''
```

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
- **`ImagePullBackOff`** — the image isn't pushed yet, or a pull secret is missing for
  the private GHCR package.
- **HPA shows `<unknown>`** — install metrics-server.

## License

[MIT](LICENSE) — use it, fork it, modify it. Every dependency is open source too; see the
table at the top.
