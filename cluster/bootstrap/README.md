# cluster/bootstrap — platform install + GitOps hand-off

Run once kubectl points at the new cluster: `kind create cluster`, or GKE via
`cluster/terraform` (`terraform output cluster_get_credentials`).

```bash
# token: a GitHub classic token with only read:packages (docs/PULL-SECRET.md),
# entered at the hidden prompt or piped on stdin — never a flag, never committed
GHCR_USERNAME=<github-user> ./cluster/bootstrap/bootstrap.sh
```

`GOLDEN_REGISTRY` defaults to `goldenRegistry` in `config/environments/dev.yaml`
(`ghcr.io/cartyc/golden`). It's injected into the ArgoCD image repositories at
install time, not hardcoded in `argocd-values.yaml`.

What it does:
1. Creates the **`ghcr-pull`** image pull secret (`scripts/apply-pull-secret.sh`)
   in `argocd`, `cert-manager`, `kyverno`, `kube-system`, `demo-dev` and
   `demo-prod`. Set `SKIP_PULL_SECRET=1` if you've already applied it.
2. Installs **ArgoCD** on golden images (`argocd-values.yaml`), pulling with
   `ghcr-pull`.
3. Applies the **AppProject** + **app-of-apps** — from there ArgoCD reconciles
   `platform/` (namespaces, Istio config, Kyverno policies) and the apps.

## Ordering / prerequisites
The platform config references CRDs from **Istio**, **Kyverno**, and
**cert-manager**. Install those (on golden images) as part of bootstrap — ArgoCD
retries until the CRDs exist, so a brief window of "Progressing" is expected.
Wiring these as third-party charts with ArgoCD **sync-waves** (so they land
before the policies/gateways that need them) is the next step ("deployment
details").

## After bootstrap
- `CHAINGUARD_ORG_UIDP=<uidp> ./scripts/apply-signing-config.sh` — the Kyverno
  signature policy's org UIDP (from your env, not committed).
- Rotate the pull-secret token before it expires: re-run
  `scripts/apply-pull-secret.sh` with the new token (`docs/PULL-SECRET.md`).
- Flip the Kyverno policies `Audit → Enforce` once Policy Reports are clean.
