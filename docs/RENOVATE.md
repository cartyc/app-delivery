# Renovate — automated dependency bumps

Renovate opens PRs when a tracked image tag or chart version moves. Those PRs go
through the **same Validate gate** (golden-registry + hardening + helm render),
so automation can't smuggle in a non-golden image.

## What it manages

| Thing | Where | Manager | Behaviour |
|---|---|---|---|
| In-house app image tags | `config/environments/dev.yaml` (annotated `tag:`) | custom regex | Auto-bump, grouped as "in-house app images" |
| Third-party chart version | `config/thirdparty/*.yaml` (`chartVersion:`) | custom regex | Auto-bump, grouped as "third-party charts" |

## What it deliberately does **not** touch

- **prod image pins** (`config/environments/prod.yaml`, `apps.*.digest`) — prod
  is promoted by a human (`docs/PROMOTION.md`); those lines carry no Renovate
  annotation, so the custom manager skips them.
- **`Dockerfile` `FROM` golden bases** — those use **moving tags** so every
  build gets golden-image's daily rebuild; pinning them would fight that. The
  `dockerfile` manager is disabled.
- **The redis image tag in `third-party/redis/values.yaml`** — tied to chart
  compatibility + what Chainguard publishes; bump it with the chart, by hand.

## How it runs

Self-hosted via `.github/workflows/renovate.yml` (Mondays + `workflow_dispatch`).
Self-hosted because the images live in **private** registries — Renovate authenticates to:

- **Artifact Registry** via Workload Identity Federation (`google-github-actions/auth`),
- **cgr.dev** via `chainctl` (an org pull token),

and injects both as masked `RENOVATE_HOST_RULES` so it can read tags.

### Setup (one-time, your side)
Secrets: `RENOVATE_TOKEN` (GitHub App/PAT), `GCP_WIF_PROVIDER`, `GCP_SA_EMAIL`
(Artifact Registry reader), `CHAINGUARD_IDENTITY`, `CHAINGUARD_ORG_UIDP`.
Variable: `GAR_HOST` (e.g. `us-central1-docker.pkg.dev`).

> Reuses the WIF wiring from `passthrough-mirror` (golden-image) — same provider
> + a reader SA. If you haven't set WIF up yet, that's the shared prerequisite.

## The loop

```
golden-image publishes tag  ->  Renovate PR here  ->  Validate gate (conftest
golden-registry + kubeconform + helm render)  ->  merge  ->  dev auto-syncs
->  promote to prod by digest (docs/PROMOTION.md)
```
