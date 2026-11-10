# Platform Admin K8s Config

Intent of this repo is to show a potential delivery path for K8s configs to a target cluster. This demo uses GKE or kind, but it can use a target K8s cluster of your choice.

This is meant to run as a complement to the [`golden-image`](https://github.com/cartyc/golden-image) repo, where we control the flow of images into our trusted container registry: private GitHub packages at `ghcr.io/cartyc/golden/<image>`. In-house app images live beside them at `ghcr.io/cartyc/apps/<app>`. The cluster pulls both with one `ghcr-pull` image pull secret created at bootstrap ([docs/PULL-SECRET.md](docs/PULL-SECRET.md)).

## What lives here

```
cluster/                     provision + bootstrap the target cluster
  terraform/                  GKE (IaC); Artifact Registry + GitHub WIF optional, off by default
  bootstrap/                  pull secret + ArgoCD on golden images → hand off to app-of-apps
config/                      ← the ONLY files a fork edits (see docs/CONFIG.md)
  environments/{dev,prod}.yaml  per-env: registry, domain, namespace, per-app image pin
  thirdparty/<name>-<env>.yaml  one file per third-party (app) chart instance
  platform-charts/<name>.yaml   cluster prerequisites (cert-manager, Kyverno) — sync-waved
apps/<app>/                 in-house apps (GENERIC — no registry/domain baked in)
  base/                       Deployment (image NAME only), Service, ServiceAccount
  overlays/{dev,prod}/        env-only bits: replicas, APP_ENV (+ prod PDB)
  istio/                      VirtualService (placeholder host), AuthorizationPolicy
third-party/<chart>/         registry-agnostic Helm values (registry injected)
platform/
  namespaces/                 namespaces + PSA + istio-injection
  istio/                      shared ingress Gateway + mesh STRICT mTLS
  argocd/                     AppProject, app-of-apps, ApplicationSets  ← all ArgoCD config lives here
policy/conftest/             Rego gate (golden-registry-only + hardening)
.github/workflows/validate.yml  render (from config) → kubeconform → conftest
scripts/validate.sh          run the gate locally
scripts/apply-pull-secret.sh create/rotate the ghcr-pull secret from your token (stdin)
```


## The golden-registry gate

`policy/conftest/image_source.rego` fails the build if **any** container image
isn't from an approved golden registry (the allowlist is generated from `config/`
at gate time) or isn't pinned. It's the delivery-side mirror of golden-image's
registry policies:

- **golden-image** decides *what approved images exist*.
- **app-delivery** enforces *only those get deployed* — at PR time (conftest) and
  at admission (Kyverno, `platform/kyverno/`).

Plus baseline hardening (`workload_security.rego`): `runAsNonRoot`, no privilege
escalation, resources set.

### In-cluster enforcement (Kyverno)
`platform/kyverno/` carries the admission twin of the CI gate:
**`restrict-to-golden-registry`** (images in golden-enforced namespaces must come
from the golden registry) and **`verify-golden-image-signatures`** (cosign
keyless verification of golden images against your org's Chainguard identity —
[Chainguard's Kyverno guide](https://edu.chainguard.dev/chainguard/containers/security-and-compliance/enforcement/kyverno/#verify-image-signatures)).
Both stage as **Audit**, flip to **Enforce** once Policy Reports are clean. Needs
Kyverno installed; the signature policy reads your org UIDP from a ConfigMap
created out of Git from `$CHAINGUARD_ORG_UIDP` (`scripts/apply-signing-config.sh`).
See `platform/kyverno/README.md`.

## Cluster: provision + bootstrap

Stand up the target cluster (kind or GKE) and its platform, then GitOps takes
over. Bootstrap needs a GitHub **classic** token with only `read:packages`
([docs/PULL-SECRET.md](docs/PULL-SECRET.md)); it's read from stdin, never
committed.

```bash
# kind
kind create cluster --name golden
# …or GKE
cd cluster/terraform && cp terraform.tfvars.example terraform.tfvars   # edit
terraform init && terraform apply                                      # GKE
eval "$(terraform output -raw cluster_get_credentials)" && cd ../..    # kubeconfig

# both: ghcr-pull secret (token at the hidden prompt) → ArgoCD → app-of-apps
GHCR_USERNAME=<github-user> ./cluster/bootstrap/bootstrap.sh
```

The golden registry defaults to `goldenRegistry` in
`config/environments/dev.yaml`. See `cluster/terraform/README.md` +
`cluster/bootstrap/README.md`.

## ArgoCD (app-of-apps)

All delivery CRs live here. Bootstrap once (or via `cluster/bootstrap`):

```bash
kubectl apply -f platform/argocd/appproject.yaml
kubectl apply -f platform/argocd/app-of-apps.yaml
```

`app-of-apps` then syncs `platform/argocd/applications/` — the `platform`
Application plus two **ApplicationSets** (`inhouse-apps`, `thirdparty-charts`)
that fan out one Application per (app × env) / chart from `config/`. Dev
auto-syncs; **prod is promote-by-merge + manual sync** (`autosync: false`).

## Add an in-house app

1. Copy `apps/hello/` to `apps/<yourapp>/` (stays generic — image NAME only, no
   registry/domain). Build it **FROM a golden base** (see `apps/hello/Dockerfile`).
2. Add `- app: <yourapp>` to the list generator in
   `platform/argocd/applications/appset-inhouse.yaml`.
3. Add the image pin under `apps:` in each `config/environments/<env>.yaml`.
4. `./scripts/validate.sh` — the gate must pass (golden registry, pinned, hardened).

## Cluster notes

- **Registry:** the private golden mirror (cgr-sync's `DEST_REGISTRY`,
  `ghcr.io/cartyc/golden`) plus `ghcr.io/cartyc/apps`, set in
  `config/environments/*.yaml`. The conftest allowlist is derived from them, so
  anything else is rejected: Docker Hub, `cgr.dev` directly, and the old
  Artifact Registry mirror.
- **Ingress:** Istio `Gateway` (ASM-compatible). Swap to the GKE Gateway API +
  Google-managed certs if you prefer; the app VirtualServices stay the same shape.
- **Workload Identity (GKE):** annotate a ServiceAccount with
  `iam.gke.io/gcp-service-account` when an app needs Google APIs (see
  `apps/hello/base/serviceaccount.yaml`).

## Validate locally

```bash
./scripts/validate.sh   # kustomize build → kubeconform → conftest (+ helm render gates)
```

Besides the per-app/env and chart renders, it renders the Argo CD bootstrap
install. It checks that every chart workload pulls with `ghcr-pull`, and runs
negative cases that must be rejected: Docker Hub, `:latest`, unpinned, `cgr.dev`
directly, the old Artifact Registry mirror, and a look-alike prefix.
