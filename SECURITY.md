# Security

This is a **public reference example** of a GitOps app-delivery repo. It contains
no secrets: every credential is referenced as a GitHub Actions secret/variable,
and the manifests use placeholder identifiers you replace with your own via
`scripts/setup.sh`.

## Reporting a vulnerability

If you find a security issue in this example (e.g. a policy that fails open, or a
manifest that weakens the intended posture), please open a private report via
GitHub Security Advisories ("Report a vulnerability") rather than a public issue.

## Notes for anyone adopting this

- Never commit real credentials. Registry/GCP identifiers (project, region,
  domain) *do* end up in the manifests — that's expected for GitOps and is
  controlled by IAM, not secrecy. Actual tokens/keys stay in GitHub secrets.
- The `policy/conftest` gate and `renovate.json` are examples; review them
  against your own baseline before relying on them.
