# Third-party Helm lane — redis (example)

Pattern for running third-party software on golden images **without vendoring
the chart**:

- The ArgoCD Application (`platform/argocd/applications/thirdparty-redis.yaml`)
  is **multi-source**: chart from the upstream Helm repo, values from `values.yaml`
  in *this* repo.
- `values.yaml` overrides `global.imageRegistry` (and image repo/tag) to the
  golden Artifact Registry mirror, so no upstream `docker.io/bitnami` image is
  pulled.

## Caveats
- **Chart ↔ image compatibility:** a plain Chainguard image may have a different
  entrypoint than the chart expects. Use the Chainguard **`-bitnami`** variant
  (e.g. `redis-bitnami`) for Bitnami charts, or add a command override.
- **The conftest gate doesn't see rendered Helm** unless you render it in CI.
  For full coverage, add a `helm template`-based render of third-party charts to
  `scripts/validate.sh` (TODO), or rely on in-cluster Kyverno admission.
- **Secrets** (e.g. `redis-auth`) are provided out-of-band — never commit them.
