#!/usr/bin/env bash
# Bootstrap a freshly-provisioned GKE cluster (see cluster/terraform):
#   1. install ArgoCD on golden images
#   2. hand off to the app-of-apps (GitOps takes over)
#
# Run after `gcloud container clusters get-credentials ...` points kubectl at the
# new cluster.
#
#   ./cluster/bootstrap/bootstrap.sh
set -euo pipefail
cd "$(dirname "$0")/../.." # repo root

# Golden registry (Chainguard-image mirror) — from the env, not hardcoded.
# Use the terraform output: GOLDEN_REGISTRY="$(terraform -chdir=cluster/terraform output -raw golden_registry)"
: "${GOLDEN_REGISTRY:?set GOLDEN_REGISTRY (e.g. terraform output golden_registry)}"
ARGOCD_CHART_VERSION="${ARGOCD_CHART_VERSION:-7.7.7}"

echo "==> Prerequisites"
cat <<'PRE'
  These provide CRDs the platform config depends on. Install them (on golden
  images) BEFORE or shortly after this script — ArgoCD will keep retrying until
  they exist. Wiring them as third-party charts with sync-waves is the next step.
    - Istio (base + istiod + ingress gateway) OR GKE managed ASM
    - Kyverno            (ClusterPolicy CRDs for platform/kyverno)
    - cert-manager       (gateway TLS cert)
PRE

echo "==> Installing ArgoCD (golden images) -> namespace argocd"
helm repo add argo https://argoproj.github.io/argo-helm >/dev/null
helm repo update argo >/dev/null
helm upgrade --install argocd argo/argo-cd \
  --namespace argocd --create-namespace \
  --version "$ARGOCD_CHART_VERSION" \
  -f cluster/bootstrap/argocd-values.yaml \
  --set global.image.repository="${GOLDEN_REGISTRY}/argocd" \
  --set redis.image.repository="${GOLDEN_REGISTRY}/redis"
kubectl -n argocd rollout status deploy/argocd-server --timeout=300s

echo "==> Handing off to GitOps (AppProject + app-of-apps)"
kubectl apply -f platform/argocd/appproject.yaml
kubectl apply -f platform/argocd/app-of-apps.yaml

cat <<'NEXT'

Done — ArgoCD now reconciles platform + apps from Git. Finish setup:
  - Kyverno signature policy config (org UIDP from your env var):
      CHAINGUARD_ORG_UIDP=<uidp> ./scripts/apply-signing-config.sh
  - Annotate the Kyverno KSAs with the kyverno_reader_service_account
    (terraform output) for Artifact Registry read.
  - ArgoCD admin password:
      kubectl -n argocd get secret argocd-initial-admin-secret \
        -o jsonpath='{.data.password}' | base64 -d ; echo
NEXT
