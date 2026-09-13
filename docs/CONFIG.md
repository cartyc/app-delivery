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
