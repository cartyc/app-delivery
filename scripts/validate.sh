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
  apps/api/overlays/dev
  apps/api/overlays/prod
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

echo "== helm render + image gate (third-party charts) =="
# Render each third-party chart with its in-repo values, then apply the
# IMAGE-SOURCE gate only: third-party images must still come from the golden
# registry. Workload hardening is the chart's concern (tuned via values +
# enforced at admission by Kyverno), so we don't block on it here.
shopt -s nullglob
tp_rendered=()
for envfile in third-party/*/chart.env; do
  dir="$(dirname "$envfile")"
  name="$(basename "$dir")"
  # shellcheck disable=SC1090
  CHART_REPO="" CHART_NAME="" CHART_VERSION="" RELEASE="" NAMESPACE="default"
  . "$envfile"
  out="$render_dir/thirdparty_${name}.yaml"
  echo "  - $name ($CHART_NAME $CHART_VERSION)"
  if [ "${CHART_REPO#oci://}" != "$CHART_REPO" ]; then
    helm template "$RELEASE" "${CHART_REPO}/${CHART_NAME}" --version "$CHART_VERSION" \
      -n "$NAMESPACE" -f "$dir/values.yaml" > "$out"
  else
    helm template "$RELEASE" "$CHART_NAME" --repo "$CHART_REPO" --version "$CHART_VERSION" \
      -n "$NAMESPACE" -f "$dir/values.yaml" > "$out"
  fi
  tp_rendered+=("$out")
done
if [ ${#tp_rendered[@]} -gt 0 ]; then
  conftest test --policy policy/conftest/image_source.rego --data policy/data "${tp_rendered[@]}"
fi

echo "OK"
