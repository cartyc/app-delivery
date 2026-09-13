# Third-party Helm lane — redis (example)

Pattern for running third-party software on golden images **without vendoring
the chart**:

- The ArgoCD Application (`platform/argocd/applications/thirdparty-redis.yaml`)
  is **multi-source**: chart from the upstream Helm repo, values from `values.yaml`
  in *this* repo.
- `values.yaml` overrides `global.imageRegistry` (and image repo/tag) to the
  golden Artifact Registry mirror, so no upstream `docker.io/bitnami` image is
  pulled.

## Gated in CI
`scripts/validate.sh` (and CI) reads `chart.env`, runs `helm template` with
`values.yaml`, and applies the **image-source gate** to the rendered output — so
a third-party chart can only ship golden-registry images, same as in-house apps.
(Workload hardening is the chart's concern, tuned via values + enforced at
admission by Kyverno, so it's not blocked here.) Verified: the golden-override
render passes; stock `docker.io/bitnami` images are rejected.

## Caveats
- **Chart ↔ image compatibility:** a plain Chainguard image may have a different
  entrypoint than the chart expects. Use the Chainguard **`-bitnami`** variant
  (e.g. `redis-bitnami`) for Bitnami charts, or add a command override.
- **Bitnami "Secure Images" guard:** Bitnami charts (2025+) refuse non-Bitnami
  registries unless `global.security.allowInsecureImages: true` — set in
  `values.yaml`, since we deliberately run the golden mirror.
- **Secrets** (e.g. `redis-auth`) are provided out-of-band — never commit them.
