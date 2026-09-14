# Configuration model (fork this repo cleanly)

Instance-specific values (registry, domain, project, cluster, image pins) live in
**`config/`** — nowhere else. The app manifests are generic; ArgoCD injects the
values at sync time via ApplicationSets, and CI mirrors that when it renders. So
forking is: edit `config/`, run the gate, push.

## The two config surfaces

### `config/environments/<env>.yaml` — in-house apps
One file per environment. Carries the env's registry, domain, namespace, cluster,
sync policy, and the per-app image pin (tag in dev, digest in prod).

The **`inhouse-apps` ApplicationSet** (matrix of the app list × these files)
creates one Application per (app × env) and:
- sets the image via `kustomize.images` → `<appsRegistry>/<app>:<tag>` (or `@<digest>`),
- patches the VirtualService host → `<app>.<baseDomain>`,
- targets `<server>` / `<namespace>`, with `autosync` controlling the sync policy.

### `config/thirdparty/<name>-<env>.yaml` — third-party charts (upstream only)
One file per chart instance: chart repo/version, values path, `goldenRegistry`,
an `imageRepos` map (chart image param → Chainguard image name), and literal
`helmParams`. The **`thirdparty-charts` ApplicationSet** renders the **upstream
project chart** (never a vendor repackager like Bitnami) with the in-repo values
and sets each image param to `<goldenRegistry>/<image>`. Because upstream charts
use plain `image.repository`/`image.tag`, the eventual move to Chainguard images
is just a values/param change — no chart fork.

## Why manifests stay generic
- `apps/*/base` uses an image **name only** (`apps/<app>:latest`) and a
  placeholder VirtualService host (`set-by-config.invalid`).
- Overlays carry env-only bits (replicas, `APP_ENV`, prod PDB) — no registry,
  namespace, or hostname.
- `third-party/*/values.yaml` is **registry-agnostic** (no `global.imageRegistry`).

Nothing in `apps/`, `platform/`, or `third-party/values` needs editing to adopt
this in your own org.

### `config/platform-charts/<name>.yaml` — cluster prerequisites
Upstream charts for cluster platform components (cert-manager, Kyverno) on
Chainguard images, delivered by the **`platform-charts` ApplicationSet** with a
`syncWave` (CRDs before consumers), ServerSideApply, and retry. Adds a
`registryParams` image style (set a param to *just* `goldenRegistry`) for charts
that split `image.registry`/`repository`. See `config/platform-charts/README.md`.
(Istio is a focused follow-up — its injection model doesn't fit the static gate.)

## Private registry (Chainguard images from your GAR, not cgr.dev)

Chainguard images are **mirrored into your private Artifact Registry** by
`cgr-sync` and pulled from there at runtime — nothing pulls from `cgr.dev`
directly. That's already how the configs work: `goldenRegistry` **is** your
private GAR, and every image (in-house, third-party, base) resolves under it.

What the configs additionally account for:
- **Pull auth.** Third-party config carries `imagePullSecrets: []` — the
  ApplicationSet maps them to the chart's `imagePullSecrets[N].name`. On GKE,
  in-project GAR pulls are authorized by the node service account, so this stays
  empty; set names for cross-project or non-GKE clusters. In-house apps use the
  same pattern on their ServiceAccount (see `apps/hello/base/serviceaccount.yaml`).
  If a chart uses a non-standard pull-secret key, put it in `helmParams`.
- **Kyverno signature reads.** Because signatures live in the private GAR, the
  Kyverno controller needs GAR **read** access to verify them — grant its service
  account Workload Identity (Artifact Registry Reader) or start it with
  `--imagePullSecrets`. See `platform/kyverno/verify-golden-signatures.yaml`.

## How CI stays honest
`scripts/validate.sh` reads the same `config/` files, renders each app/env exactly
as the ApplicationSet will (same image + host injection), **generates the conftest
allowlist from `config/`**, and gates. One source of truth, so the gate can't
drift from what actually deploys.

## Forking checklist
1. Edit `config/environments/*.yaml` and `config/thirdparty/*.yaml` (registry,
   domain, project, cgrOrg, repoURL, clusters, image pins).
2. Set the `repoURL` in the two ApplicationSets + `platform/argocd/appproject.yaml`
   + `app-of-apps.yaml` to your fork. (`scripts/setup.sh` does all of this from
   flags — see the README.)
3. `./scripts/validate.sh` → green.
4. Bootstrap ArgoCD (`kubectl apply -f platform/argocd/{appproject,app-of-apps}.yaml`).
