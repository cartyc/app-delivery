#!/usr/bin/env bash
# Render every app/env exactly as the ApplicationSets will (inject the golden
# registry + hostname from config/), then schema-validate and run the gate.
# The conftest allowlist is generated from config too, so there's one source of
# truth. Mirrors .github/workflows/validate.yml.
#
#   ./scripts/validate.sh
set -euo pipefail
cd "$(dirname "$0")/.."

for t in yq kustomize kubeconform conftest helm; do
  command -v "$t" >/dev/null || { echo "missing required tool: $t" >&2; exit 1; }
done

render_dir="$(mktemp -d)"
trap 'rm -rf "$render_dir"' EXIT
fail=0

echo "== in-house apps (render per-env config, then gate) =="
for envf in config/environments/*.yaml; do
  env=$(yq -r '.env' "$envf")
  ns=$(yq -r '.namespace' "$envf")
  goldenReg=$(yq -r '.goldenRegistry' "$envf")
  appsReg=$(yq -r '.appsRegistry' "$envf")
  org=$(yq -r '.cgrOrg' "$envf")
  dom=$(yq -r '.baseDomain' "$envf")

  data="$render_dir/data-$env"
  mkdir -p "$data"
  printf 'allowed_registries:\n  - "%s/"\n  - "%s/"\n  - "cgr.dev/%s/"\n' \
    "$goldenReg" "$appsReg" "$org" > "$data/registries.yaml"

  for app in $(yq -r '.apps | keys | .[]' "$envf"); do
    digest=$(yq -r ".apps.\"$app\".digest // \"\"" "$envf")
    tag=$(yq -r ".apps.\"$app\".tag // \"\"" "$envf")
    if [ -n "$digest" ]; then ref="$appsReg/$app@$digest"; else ref="$appsReg/$app:$tag"; fi
    out="$render_dir/${app}-${env}.yaml"
    echo "  - $app/$env  image=$ref  host=$app.$dom"
    kustomize build "apps/$app/overlays/$env" \
      | sed -e "s#image: apps/$app:latest#image: $ref#" \
            -e "s#set-by-config.invalid#$app.$dom#" > "$out"
    kubeconform -strict -ignore-missing-schemas -summary "$out" || fail=1
    conftest test --policy policy/conftest --data "$data" "$out" || fail=1
  done
  # reuse one env's allowlist for the image-less resources below
  SHARED_DATA="$data"
done

echo "== platform (namespaces + shared istio) =="
kustomize build platform > "$render_dir/platform.yaml"
kubeconform -strict -ignore-missing-schemas -summary "$render_dir/platform.yaml" || fail=1
conftest test --policy policy/conftest --data "$SHARED_DATA" "$render_dir/platform.yaml" || fail=1

echo "== ArgoCD delivery CRs (schema + policy; no images) =="
kubeconform -strict -ignore-missing-schemas -summary \
  platform/argocd/*.yaml platform/argocd/applications/*.yaml || fail=1
conftest test --policy policy/conftest --data "$SHARED_DATA" \
  platform/argocd/*.yaml platform/argocd/applications/*.yaml || true

echo "== third-party charts (helm render from config, image gate) =="
for tf in config/thirdparty/*.yaml; do
  [ -e "$tf" ] || continue
  name=$(yq -r '.name' "$tf")
  env=$(yq -r '.env' "$tf")
  ns=$(yq -r '.namespace' "$tf")
  chartRepo=$(yq -r '.chartRepo' "$tf")
  chart=$(yq -r '.chart' "$tf")
  ver=$(yq -r '.chartVersion' "$tf")
  vals=$(yq -r '.valuesPath' "$tf")
  goldenReg=$(yq -r '.goldenRegistry' "$tf")
  out="$render_dir/tp-${name}-${env}.yaml"
  echo "  - $name/$env ($chart $ver) -> $goldenReg"
  # Build --set args from config: imageRepos (prefixed with goldenRegistry) +
  # literal helmParams. Mirrors the thirdparty ApplicationSet exactly.
  setargs=()
  for k in $(yq -r '.imageRepos // {} | keys | .[]' "$tf"); do
    v=$(yq -r ".imageRepos.\"$k\"" "$tf")
    setargs+=(--set "$k=$goldenReg/$v")
  done
  for k in $(yq -r '.helmParams // {} | keys | .[]' "$tf"); do
    v=$(yq -r ".helmParams.\"$k\"" "$tf")
    setargs+=(--set "$k=$v")
  done
  i=0
  for s in $(yq -r '.imagePullSecrets // [] | .[]' "$tf"); do
    setargs+=(--set "imagePullSecrets[$i].name=$s")
    i=$((i + 1))
  done
  helm template "$name" "$chart" --repo "$chartRepo" --version "$ver" -n "$ns" -f "$vals" \
    "${setargs[@]}" > "$out"
  data="$render_dir/data-tp-$name"
  mkdir -p "$data"
  printf 'allowed_registries:\n  - "%s/"\n' "$goldenReg" > "$data/registries.yaml"
  # third-party gets the IMAGE-SOURCE gate only (provenance); hardening is the
  # chart's concern + Kyverno at admission.
  conftest test --policy policy/conftest/image_source.rego --data "$data" "$out" || fail=1
done

[ "$fail" -eq 0 ] && echo "OK" || { echo "FAILED"; exit 1; }
