# app-delivery

GitOps delivery of in-house applications — and the Kubernetes-native platform
config they need — running on **golden image artifacts**, targeting **GKE**.

This is the runtime end of a three-repo supply chain:

| Repo | Role |
|---|---|
| [`image-syncer`](https://github.com/cartyc/image-syncer) (`cgr-sync`) | Mirrors Chainguard images into your private registry (Artifact Registry). |
| [`golden-image`](https://github.com/cartyc/golden-image) | Platform-engineering **bakery**: catalog, registry/library policies, intake — produces the approved golden artifacts. |
| **`app-delivery`** (this repo) | Deploys in-house apps **onto** those golden artifacts, with Istio/ArgoCD/etc. config, and **enforces that only golden images ship**. |

> **Public reference repo.** No secrets are committed — credentials are GitHub
> Actions secrets/variables, and infra identifiers are placeholders you set with
> `scripts/setup.sh`. Registry/GCP/domain values *do* land in the manifests
> (GitOps needs them; access is IAM-controlled, not secret). Licensed Apache-2.0.

## What lives here

```
config/                      ← the ONLY files a fork edits (see docs/CONFIG.md)
  environments/{dev,prod}.yaml  per-env: registry, domain, namespace, per-app image pin
  thirdparty/<name>-<env>.yaml  one file per third-party chart instance
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

Registry + domain are **not** baked into the app manifests — the ApplicationSets
inject them from `config/` at sync time, and CI does the same when it renders.
So a fork changes `config/`, not dozens of manifests. See **[docs/CONFIG.md](docs/CONFIG.md)**.

## The golden-registry gate (why this repo has teeth)

`policy/conftest/image_source.rego` fails the build if **any** container image
isn't from an approved golden registry (the allowlist is generated from `config/`
at gate time) or isn't pinned. It's the delivery-side mirror of golden-image's
registry policies:

- **golden-image** decides *what approved images exist*.
- **app-delivery** enforces *only those get deployed* — at PR time (conftest) and,
  in-cluster, alongside your `cluster-ops` Kyverno admission policies.

Plus baseline hardening (`workload_security.rego`): `runAsNonRoot`, no privilege
escalation, resources set.

## ArgoCD (app-of-apps)

All delivery CRs live here (not in golden-image). Bootstrap once:

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

## Third-party Helm on golden images

Add a `config/thirdparty/<name>-<env>.yaml` (chart repo/version + `goldenRegistry`)
and drop registry-agnostic values in `third-party/<name>/values.yaml`. The
`thirdparty-charts` ApplicationSet renders the upstream chart with your in-repo
values and injects `global.imageRegistry` (+ the Bitnami "Secure Images" opt-in)
as Helm parameters. CI renders each chart and runs the **image-source gate** on
the output — so a chart can only ship golden-registry images too. Verify
chart↔image compatibility (use Chainguard `-bitnami` variants where needed).

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
