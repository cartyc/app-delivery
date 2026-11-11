#!/usr/bin/env bash
# Bootstrap a freshly-provisioned cluster (kind, or GKE from cluster/terraform):
#   1. create the `ghcr-pull` image pull secret from a token YOU supply
#   2. install ArgoCD on golden images
#   3. hand off to the app-of-apps (GitOps takes over)
#
# Run once kubectl points at the new cluster (`kind create cluster`, or
# `gcloud container clusters get-credentials ...`). The token (read:packages)
# is read from stdin and never stored in the repo — see docs/PULL-SECRET.md:
#
#   printf '%s' "$TOKEN" | GHCR_USERNAME=<github-user> ./cluster/bootstrap/bootstrap.sh
#
# Set SKIP_PULL_SECRET=1 to reuse a pull secret you've already applied.
set -euo pipefail
cd "$(dirname "$0")/../.." # repo root

for t in kubectl helm yq base64; do
  command -v "$t" >/dev/null || { echo "missing required tool: $t" >&2; exit 1; }
done

# Golden registry (private ghcr.io mirror of the Chainguard images, filled by
# golden-image) — from the env, default from config/environments/dev.yaml.
GOLDEN_REGISTRY="${GOLDEN_REGISTRY:-$(yq -r '.goldenRegistry' config/environments/dev.yaml)}"
ARGOCD_CHART_VERSION="${ARGOCD_CHART_VERSION:-10.11.7}" # ships ArgoCD v3.5.7 (matches golden image)

if [ "${SKIP_PULL_SECRET:-}" != "1" ]; then
  echo "==> Image pull secret (ghcr-pull) in every namespace that pulls private images"
  ./scripts/apply-pull-secret.sh
fi

echo "==> Prerequisites"
cat <<'PRE'
  cert-manager + Kyverno now install themselves via the platform-charts lane
  (GitOps, sync-waved) once the app-of-apps below is applied — no manual step.
  Istio is still a manual prerequisite (its own follow-up):
    - Istio (base + istiod + ingress gateway) OR GKE managed ASM
PRE

echo "==> Installing ArgoCD (golden images) -> namespace argocd"
helm repo add argo https://argoproj.github.io/argo-helm >/dev/null
helm repo update argo >/dev/null
helm upgrade --install argocd argo/argo-cd \
  --namespace argocd --create-namespace \
  --version "$ARGOCD_CHART_VERSION" \
  -f cluster/bootstrap/argocd-values.yaml \
  --set global.image.repository="${GOLDEN_REGISTRY}/argocd" \
  --set 'global.imagePullSecrets[0].name=ghcr-pull' \
  --set redis.image.repository="${GOLDEN_REGISTRY}/redis"
kubectl -n argocd rollout status deploy/argocd-server --timeout=300s

echo "==> Handing off to GitOps (AppProject + app-of-apps)"
kubectl apply -f platform/argocd/appproject.yaml
kubectl apply -f platform/argocd/app-of-apps.yaml

cat <<'NEXT'

Done — ArgoCD now reconciles platform + apps from Git. Finish setup:
  - Kyverno signature policy config (org UIDP from your env var):
      CHAINGUARD_ORG_UIDP=<uidp> ./scripts/apply-signing-config.sh
  - Rotate the pull-secret token before it expires (docs/PULL-SECRET.md):
      printf '%s' "$NEW_TOKEN" | GHCR_USERNAME=<github-user> ./scripts/apply-pull-secret.sh
  - ArgoCD admin password:
      kubectl -n argocd get secret argocd-initial-admin-secret \
        -o jsonpath='{.data.password}' | base64 -d ; echo
NEXT
