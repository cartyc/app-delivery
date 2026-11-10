# config/platform-charts — cluster prerequisites (upstream charts on golden images)

Cluster platform components (cert-manager, Kyverno, …) delivered by the
`platform-charts` ApplicationSet. Same upstream-chart-on-Chainguard-images idea
as the third-party lane, but with what cluster infra needs:

- **`syncWave`** → `argocd.argoproj.io/sync-wave` so CRDs land before consumers
  (e.g. cert-manager/Kyverno CRDs at wave `-20`, before `platform/` at wave `0`,
  before apps at wave `10`).
- **ServerSideApply + SkipDryRunOnMissingResource** sync options (cert-manager /
  Istio CRDs blow past the client-side apply annotation limit).
- **CreateNamespace + retry** (charts converge as their CRDs appear).

## Three image-override styles (charts differ)
| Field | Produces | Use for |
|---|---|---|
| `imageRepos: {param: name}` | `param = <goldenRegistry>/<name>` | charts with a full `image.repository` (cert-manager) |
| `registryParams: [param, …]` | `param = <goldenRegistry>` | charts that split `image.registry` + `repository` (Kyverno; each component's flat golden repository is set in `helmParams`) |
| `helmParams: {param: value}` | `param = value` (literal) | flags, tags, etc. |

`imagePullSecrets: [name, …]` maps to `<imagePullSecretsParam>[N].name` for the
private registry. The param is the chart's own value path:
`global.imagePullSecrets` for cert-manager and Kyverno, whose top-level
`imagePullSecrets` is a credentials map it would create itself. Both set
`ghcr-pull`, which bootstrap creates (`docs/PULL-SECRET.md`). CI (`scripts/validate.sh`) renders each chart the same way and runs the
golden-registry image gate — both cert-manager and Kyverno render fully golden
(verified).

## Included
- **cert-manager** (jetstack) — issues the gateway TLS cert (`platform/certs/`).
- **Kyverno** — the admission controller for `platform/kyverno/` ClusterPolicies.

## Not yet: Istio
Istio uses an `image: auto` injection sentinel on the gateway and a hardcoded
`busybox` init in istiod, which don't fit the static image gate — it needs
dedicated handling (explicit images / revision tags / gateway injection) and is
a focused follow-up. Until then it's the one manual bootstrap prerequisite.
