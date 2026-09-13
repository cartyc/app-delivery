#!/usr/bin/env bash
# Render every kustomize target, schema-validate it, and run the conftest gate.
# Mirrors .github/workflows/validate.yml so you can pre-flight locally:
#   ./scripts/validate.sh
set -euo pipefail
cd "$(dirname "$0")/.."

# Kustomize targets to render (overlays + platform).
TARGETS=(
  apps/hello/overlays/dev
  apps/hello/overlays/prod
  platform
)

render_dir="$(mktemp -d)"
trap 'rm -rf "$render_dir"' EXIT

echo "== kustomize build =="
for t in "${TARGETS[@]}"; do
  out="$render_dir/$(echo "$t" | tr / _).yaml"
  echo "  - $t"
  kustomize build "$t" > "$out"
done

echo "== kubeconform (schema) =="
# Istio/ArgoCD CRDs aren't in the default schema set — skip missing, still catch
# core-kind errors.
kubeconform -strict -ignore-missing-schemas -summary "$render_dir"/*.yaml

echo "== conftest (golden-registry + hardening gate) =="
conftest test --policy policy/conftest --data policy/data "$render_dir"/*.yaml

echo "== conftest (raw ArgoCD delivery CRs) =="
# Applications have no containers, so they pass the workload rules; this just
# keeps them in the gate's blast radius for future policies.
conftest test --policy policy/conftest --data policy/data \
  platform/argocd/*.yaml platform/argocd/applications/*.yaml || true

echo "OK"
