# Third-party Helm lane — kube-state-metrics (upstream example)

**Upstream charts only** — the project-adjacent chart (here `prometheus-community/
kube-state-metrics`), not a vendor repackager (Bitnami etc.). This keeps the
eventual "everything on Chainguard images" migration a values change, not a
chart fork.

> Why not metrics-server? It was the original example, but Chainguard doesn't
> publish a `metrics-server` image to this org, so the lane uses
> kube-state-metrics — an upstream-charted equivalent that *is* available as a
> golden image. Same wiring pattern.

## How it's wired
- `config/thirdparty/kube-state-metrics-dev.yaml` — chart coords + `registryParams`
  (`image.registry` → `goldenRegistry`) because this chart splits registry from
  repository; keeps the chart repository path so the golden mirror lives at
  `goldenRegistry/kube-state-metrics/kube-state-metrics`. Plus `helmParams`
  (literal passthrough, e.g. the tag). Charts with a *full* `image.repository`
  path instead use `imageRepos` (see `docs/CONFIG.md`).
- `values.yaml` here — registry-agnostic settings only (replicas, resources).
- The `thirdparty-charts` ApplicationSet renders the upstream chart with these
  values + injected image params. CI (`scripts/validate.sh`) does the same and
  runs the **image-source gate** on the output.

## Private registry pull auth
Chainguard images are pulled from your **private Artifact Registry** (via
`goldenRegistry`), not cgr.dev. Set `imagePullSecrets` in the config file for
cross-project/non-GKE clusters; on GKE with in-project GAR it stays empty (node
SA authorizes the pull). See `docs/CONFIG.md`.

## Adding another upstream chart
Copy the config file, set `chartRepo`/`chart`/`chartVersion`, point its image at
the Chainguard mirror (`imageRepos` for a full repository path, or
`registryParams` for a split registry/repository), add a values file. No manifest
or ApplicationSet edits. Prefer charts published by the project itself over
vendor repackagers.
