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
apps/<app>/                 in-house apps (native Kustomize)
  base/                       Deployment, Service, ServiceAccount
  overlays/{dev,prod}/        env pins: image, replicas, hostname, env
  istio/                      VirtualService, AuthorizationPolicy
third-party/<chart>/         values for 3rd-party Helm charts (images -> golden)
platform/
  namespaces/                 namespaces + PSA + istio-injection
  istio/                      shared ingress Gateway + mesh STRICT mTLS
  argocd/                     AppProject, app-of-apps, child Applications  ← all ArgoCD config lives here
environments/{dev,prod}.yaml  per-env knobs (project, region, registry, domain)
policy/
  conftest/                   Rego gate (golden-registry-only + hardening)
  data/registries.yaml        approved registry prefixes
.github/workflows/validate.yml  render → kubeconform → conftest
scripts/validate.sh          run the gate locally
```

## The golden-registry gate (why this repo has teeth)

`policy/conftest/image_source.rego` fails the build if **any** container image
isn't from an approved golden registry (`policy/data/registries.yaml`) or isn't
pinned. It's the delivery-side mirror of golden-image's registry policies:

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
Application, each app (`hello-dev`, `hello-prod`), and each third-party chart —
all from Git. Dev auto-syncs; **prod is promote-by-merge + manual sync**.

## Add an in-house app

1. Copy `apps/hello/` to `apps/<yourapp>/`; adjust the Deployment/Service, the
   Istio host, and the overlay image pins to your golden `apps/` image.
2. Build it **FROM a golden base** (see `apps/hello/Dockerfile`) and push to the
   golden `apps/` registry.
3. Add `hello-dev.yaml`/`hello-prod.yaml`-style Applications under
   `platform/argocd/applications/`.
4. `./scripts/validate.sh` — the gate must pass (golden registry, pinned, hardened).

## Third-party Helm on golden images

See `platform/argocd/applications/thirdparty-redis.yaml` + `third-party/redis/`:
a multi-source ArgoCD Application pulls the upstream chart but takes its values
**from this repo**, overriding every image to the golden registry. Verify
chart↔image compatibility (use Chainguard `-bitnami` variants where the chart
expects the Bitnami entrypoint).

CI renders every third-party chart (`helm template` from `chart.env` + `values.yaml`)
and runs the **image-source gate** on the output — so a chart can only ship
golden-registry images too, not just the in-house apps.

## GKE notes

- **Registry:** the golden Artifact Registry mirror (cgr-sync's `DEST_REGISTRY`).
  Keep `policy/data/registries.yaml` in sync with it.
- **Ingress:** Istio `Gateway` (ASM-compatible). Swap to the GKE Gateway API +
  Google-managed certs if you prefer; the app VirtualServices stay the same shape.
- **Workload Identity:** annotate a ServiceAccount with
  `iam.gke.io/gcp-service-account` when an app needs Google APIs (see
  `apps/hello/base/serviceaccount.yaml`).

## Validate locally

```bash
./scripts/validate.sh   # kustomize build → kubeconform → conftest
```
