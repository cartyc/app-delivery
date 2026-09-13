# Third-party Helm lane — metrics-server (upstream example)

**Upstream charts only** — the project's own chart (here `kubernetes-sigs/
metrics-server`), not a vendor repackager (Bitnami etc.). Upstream charts expose
plain `image.repository` / `image.tag`, so pointing them at Chainguard images is
a clean per-component override — no `global.imageRegistry` and no vendor "Secure
Images" opt-in. This also makes the eventual "everything on Chainguard images"
migration a values change, not a chart fork.

## How it's wired
- `config/thirdparty/metrics-server-dev.yaml` — chart coords + `imageRepos`
  (chart image param → Chainguard image name; the ApplicationSet prefixes
  `goldenRegistry`) + `helmParams` (literal passthrough, e.g. the tag).
- `values.yaml` here — registry-agnostic settings only (replicas, resources).
- The `thirdparty-charts` ApplicationSet renders the upstream chart with these
  values + injected image params. CI (`scripts/validate.sh`) does the same and
  runs the **image-source gate** on the output.

## Adding another upstream chart
Copy the config file, set `chartRepo`/`chart`/`chartVersion`, map each image
param under `imageRepos` to its Chainguard image, add a values file. No manifest
or ApplicationSet edits. Prefer charts published by the project itself over
vendor repackagers.
