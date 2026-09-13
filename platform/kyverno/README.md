# Kyverno admission policies

The **in-cluster twin** of the CI conftest gate. CI catches violations pre-merge;
Kyverno catches them at admission (and at runtime for anything applied outside
this repo). Two policies:

| Policy | What | Scope |
|---|---|---|
| `restrict-to-golden-registry` | Every image must come from the golden registry | Namespaces labelled `enforcement: golden` (app namespaces) — GKE/system namespaces untouched |
| `verify-golden-image-signatures` | cosign **keyless** verify golden images against your org's Chainguard identity (`issuer.enforce.dev`) | Image reference `…/golden/*`, cluster-wide — non-golden images ignored |

## Staged as Audit → Enforce
Both ship with `validationFailureAction: Audit` (report only). After deploying,
check the Policy Reports (`kubectl get polr,cpolr -A`) show no unexpected
violations, then flip to `Enforce`. Same discipline as the golden-image registry
policies (never enforce blind).

## Prerequisites
- **Kyverno installed** (`https://kyverno.io/docs/installation/`) — the CRDs must
  exist before these ClusterPolicies sync. (Install it on Chainguard `kyverno`
  images via the upstream chart, following the third-party lane.)
- **Org UIDP via env var (not committed).** The signature policy reads your org
  UIDP from a ConfigMap (`golden-signing-config` in the `kyverno` namespace) via
  a Kyverno `context` — so no org identifier is in Git. Create it from your env:
  ```bash
  CHAINGUARD_ORG_UIDP=<your-org-uidp> ./scripts/apply-signing-config.sh
  ```
  Kyverno's ServiceAccount needs `get`/`list` on that ConfigMap.

## Signature verification notes
- Golden images keep their Chainguard signatures through `cgr-sync` (it preserves
  signatures/attestations), so they verify against
  `issuer: https://issuer.enforce.dev` + your org's signing identities.
- In-house `apps/*` images are built by your pipeline — add a second
  `verifyImages` rule matching `…/apps/*` against your CI's signing identity once
  you sign them.
- Verification uses the public Sigstore trust root; if your org runs a private
  Sigstore, set `roots`/`rekor` in the policy.
