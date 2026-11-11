# Kyverno admission policies

The **in-cluster twin** of the CI conftest gate. CI catches violations pre-merge;
Kyverno catches them at admission (and at runtime for anything applied outside
this repo). Two policies:

| Policy | What | Scope |
|---|---|---|
| `restrict-to-golden-registry` | Every image must come from `ghcr.io/<owner>/golden/` or `ghcr.io/<owner>/apps/` | Namespaces labelled `enforcement: golden` (app namespaces) — GKE/system namespaces untouched |
| `verify-golden-image-signatures` | cosign **keyless** verify golden images against your org's Chainguard identity (`issuer.enforce.dev`) | Image reference `…/golden/*`, cluster-wide — non-golden images ignored |

## Staged as Audit → Enforce
Both ship with `validationFailureAction: Audit` (report only). After deploying,
check the Policy Reports (`kubectl get polr,cpolr -A`) show no unexpected
violations, then flip to `Enforce`. Same discipline as the golden-image registry
policies (never enforce blind).

## Prerequisites
- **Kyverno** installs itself via the platform-charts lane
  (`config/platform-charts/kyverno.yaml`) at sync-wave `-20`, so its
  ClusterPolicy CRDs exist before these policies (`platform/`, wave `0`) sync.
- **Org UIDP via env var (not committed).** The signature policy reads your org
  UIDP from a ConfigMap (`golden-signing-config` in the `kyverno` namespace) via
  a Kyverno `context` — so no org identifier is in Git. Create it from your env:
  ```bash
  CHAINGUARD_ORG_UIDP=<your-org-uidp> ./scripts/apply-signing-config.sh
  ```
  Kyverno's ServiceAccount needs `get`/`list` on that ConfigMap.

## Signature verification notes
- Golden images keep their Chainguard signatures through `cgr-sync`, which
  mirrors them as cosign `sha256-<digest>.sig` / `.att` tags beside each image
  in `ghcr.io/<owner>/golden`. So they verify against
  `issuer: https://issuer.enforce.dev` and your org's signing identities, as on
  cgr.dev.
- The golden packages are **private**, so Kyverno reads signatures with the
  `ghcr-pull` secret in the `kyverno` namespace (`--imagePullSecrets=ghcr-pull`,
  set by `config/platform-charts/kyverno.yaml`; see `docs/PULL-SECRET.md`).
- `golden/static` comes from Chainguard's public catalog, signed by a different
  identity. It's a build-time base for `apps/hello` and never runs as a pod,
  so the policy never sees it. Don't run it directly: it would fail
  verification.
- In-house `apps/*` images are built by your pipeline — add a second
  `verifyImages` rule matching `…/apps/*` against your CI's signing identity once
  you sign them.
- Verification uses the public Sigstore trust root; if your org runs a private
  Sigstore, set `roots`/`rekor` in the policy.
