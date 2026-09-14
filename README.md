# Platform Admin K8s Config

Intent of this repo is to show a potential delivery path for K8s configs to a target cluster. This demo using GKE but it can use a target K8s Cluster of your choice.

This is meant to run as a compliment to the [`golden-image`](https://github.com/cartyc/golden-image) repo where we control the flow of images into our trusted container Registry.

## What lives here

```
cluster/                     provision + bootstrap the target cluster
  terraform/                  GKE + Workload Identity + Artifact Registry (IaC)
  bootstrap/                  install ArgoCD on golden images → hand off to app-of-apps
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

Stand up the target GKE cluster and its platform, then GitOps takes over:

```bash
cd cluster/terraform && cp terraform.tfvars.example terraform.tfvars   # edit
terraform init && terraform apply          # GKE + WIF + Artifact Registry
eval "$(terraform output -raw cluster_get_credentials)"                # kubeconfig
export GOLDEN_REGISTRY="$(terraform output -raw golden_registry)"      # inject registry (not hardcoded)
cd ../.. && ./cluster/bootstrap/bootstrap.sh                           # ArgoCD → app-of-apps
```

Terraform outputs feed the rest: `golden_registry`/`apps_registry` → `config/`,
`wif_provider`/`ci_service_account` → Renovate secrets, `kyverno_reader_service_account`
→ the Kyverno KSA annotation. See `cluster/terraform/README.md` +
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

## GKE notes

- **Registry:** the golden Artifact Registry mirror (cgr-sync's `DEST_REGISTRY`),
  set in `config/environments/*.yaml`. The conftest allowlist is derived from it.
- **Ingress:** Istio `Gateway` (ASM-compatible). Swap to the GKE Gateway API +
  Google-managed certs if you prefer; the app VirtualServices stay the same shape.
- **Workload Identity:** annotate a ServiceAccount with
  `iam.gke.io/gcp-service-account` when an app needs Google APIs (see
  `apps/hello/base/serviceaccount.yaml`).

## Validate locally

```bash
./scripts/validate.sh   # kustomize build → kubeconform → conftest
```
