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
Self-hosted because the in-house app images live in **private** ghcr.io packages.
Renovate reads their tags with the job's own `GITHUB_TOKEN` (`packages: read`),
injected as a masked `RENOVATE_HOST_RULES` entry for `ghcr.io`. There is no
stored registry credential, no Google Cloud identity, and no `cgr.dev` login:
nothing Renovate manages lives on `cgr.dev` (Dockerfile golden bases are left
alone, see above).

### Setup (one-time, your side)
- Secret `RENOVATE_TOKEN` (GitHub App token or fine-grained PAT with contents +
  pull-requests write) to open PRs.
- For each in-house app package (`ghcr.io/cartyc/apps/<app>`), open
  `https://github.com/users/cartyc/packages/container/apps%2F<app>/settings`.
  Under **Manage Actions access**, add `cartyc/app-delivery` with the **Read**
  role. Without it, the job's `GITHUB_TOKEN` gets 403 and Renovate sees no
  tags.

## The loop

```
golden-image publishes tag  ->  Renovate PR here  ->  Validate gate (conftest
golden-registry + kubeconform + helm render)  ->  merge  ->  dev auto-syncs
->  promote to prod by digest (docs/PROMOTION.md)
```
