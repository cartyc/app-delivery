# cluster/bootstrap — platform install + GitOps hand-off

Run after `cluster/terraform` has provisioned the cluster and you've fetched
credentials (`terraform output cluster_get_credentials`).

```bash
export GOLDEN_REGISTRY="$(terraform -chdir=cluster/terraform output -raw golden_registry)"
./cluster/bootstrap/bootstrap.sh
```

`GOLDEN_REGISTRY` (the terraform output / your `config/` `goldenRegistry`) is
injected into the ArgoCD image repositories at install time — it isn't hardcoded
in `argocd-values.yaml`.

What it does:
1. Installs **ArgoCD** on golden images (`argocd-values.yaml`).
2. Applies the **AppProject** + **app-of-apps** — from there ArgoCD reconciles
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
- Annotate the Kyverno KSAs with the `kyverno_reader_service_account` Terraform
  output (Workload Identity → Artifact Registry read for signatures).
- Flip the Kyverno policies `Audit → Enforce` once Policy Reports are clean.
