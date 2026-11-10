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
  dom=$(yq -r '.baseDomain' "$envf")

  data="$render_dir/data-$env"
  mkdir -p "$data"
  # Only the private golden + apps registries. Nothing pulls from cgr.dev
  # directly: golden-image mirrors it into goldenRegistry.
  printf 'allowed_registries:\n  - "%s/"\n  - "%s/"\n' \
    "$goldenReg" "$appsReg" > "$data/registries.yaml"

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
  for k in $(yq -r '.registryParams // [] | .[]' "$tf"); do
    setargs+=(--set "$k=$goldenReg")
  done
  for k in $(yq -r '.helmParams // {} | keys | .[]' "$tf"); do
    v=$(yq -r ".helmParams.\"$k\"" "$tf")
    setargs+=(--set "$k=$v")
  done
  # pull secrets go under the chart's own value path (imagePullSecretsParam)
  psp=$(yq -r '.imagePullSecretsParam // "imagePullSecrets"' "$tf")
  i=0
  for s in $(yq -r '.imagePullSecrets // [] | .[]' "$tf"); do
    setargs+=(--set "$psp[$i].name=$s")
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

echo "== platform charts (helm render from config, image gate) =="
for pf in config/platform-charts/*.yaml; do
  [ -e "$pf" ] || continue
  name=$(yq -r '.name' "$pf")
  ns=$(yq -r '.namespace' "$pf")
  chartRepo=$(yq -r '.chartRepo' "$pf")
  chart=$(yq -r '.chart' "$pf")
  ver=$(yq -r '.chartVersion' "$pf")
  goldenReg=$(yq -r '.goldenRegistry' "$pf")
  out="$render_dir/pf-${name}.yaml"
  echo "  - $name ($chart $ver)"
  setargs=()
  for k in $(yq -r '.imageRepos // {} | keys | .[]' "$pf"); do
    v=$(yq -r ".imageRepos.\"$k\"" "$pf")
    setargs+=(--set "$k=$goldenReg/$v")
  done
  for k in $(yq -r '.registryParams // [] | .[]' "$pf"); do
    setargs+=(--set "$k=$goldenReg")
  done
  for k in $(yq -r '.helmParams // {} | keys | .[]' "$pf"); do
    v=$(yq -r ".helmParams.\"$k\"" "$pf")
    setargs+=(--set "$k=$v")
  done
  # pull secrets go under the chart's own value path (imagePullSecretsParam)
  psp=$(yq -r '.imagePullSecretsParam // "imagePullSecrets"' "$pf")
  i=0
  for s in $(yq -r '.imagePullSecrets // [] | .[]' "$pf"); do
    setargs+=(--set "$psp[$i].name=$s")
    i=$((i + 1))
  done
  helm template "$name" "$chart" --repo "$chartRepo" --version "$ver" -n "$ns" \
    "${setargs[@]}" > "$out"
  data="$render_dir/data-pf-$name"
  mkdir -p "$data"
  printf 'allowed_registries:\n  - "%s/"\n' "$goldenReg" > "$data/registries.yaml"
  conftest test --policy policy/conftest/image_source.rego --data "$data" "$out" || fail=1
done

echo "== argocd bootstrap (helm render as bootstrap.sh installs it, image gate) =="
argoVer=$(sed -n 's/^ARGOCD_CHART_VERSION="${ARGOCD_CHART_VERSION:-\([^}]*\)}".*/\1/p' cluster/bootstrap/bootstrap.sh)
goldenReg=$(yq -r '.goldenRegistry' config/environments/dev.yaml)
echo "  - argo-cd $argoVer -> $goldenReg"
helm template argocd argo-cd --repo https://argoproj.github.io/argo-helm --version "$argoVer" -n argocd \
  -f cluster/bootstrap/argocd-values.yaml \
  --set global.image.repository="$goldenReg/argocd" \
  --set redis.image.repository="$goldenReg/redis" \
  --set 'global.imagePullSecrets[0].name=ghcr-pull' > "$render_dir/argocd.yaml"
data="$render_dir/data-argocd"
mkdir -p "$data"
printf 'allowed_registries:\n  - "%s/"\n' "$goldenReg" > "$data/registries.yaml"
conftest test --policy policy/conftest/image_source.rego --data "$data" "$render_dir/argocd.yaml" || fail=1

echo "== pull secret: every chart workload pulls with ghcr-pull =="
# Charts create their own ServiceAccounts, so the secret must be on each pod
# spec (in-house apps carry it on their ServiceAccount instead). Helm test hooks
# are never applied by Argo CD, so they're skipped, like in the image gate.
for f in "$render_dir"/tp-*.yaml "$render_dir"/pf-*.yaml "$render_dir/argocd.yaml"; do
  # A pod passes if its own spec, or the chart-rendered ServiceAccount it runs
  # as, lists ghcr-pull (cert-manager puts it on its ServiceAccounts).
  sas=$(yq -N -r 'select(.kind == "ServiceAccount") | select((.imagePullSecrets // []) | any_c(.name == "ghcr-pull")) | .metadata.name' "$f" | tr '\n' ' ')
  missing=$(SAS=" $sas" yq -N -r '
    select(.kind == "Deployment" or .kind == "StatefulSet" or .kind == "DaemonSet" or .kind == "Job" or .kind == "CronJob")
    | select(((.metadata.annotations // {})["helm.sh/hook"] // "") | test("test") | not)
    | (.spec.template.spec // .spec.jobTemplate.spec.template.spec) as $p
    | select(($p.imagePullSecrets // []) | any_c(.name == "ghcr-pull") | not)
    | select(strenv(SAS) | contains(" " + ($p.serviceAccountName // "default") + " ") | not)
    | .kind + "/" + .metadata.name' "$f")
  if [ -n "$missing" ]; then
    echo "  FAIL $(basename "$f"): no ghcr-pull on: $(echo $missing)"; fail=1
  else
    echo "  ok   $(basename "$f")"
  fi
done
for sa in apps/*/base/serviceaccount.yaml; do
  if yq -e '.imagePullSecrets[] | select(.name == "ghcr-pull")' "$sa" >/dev/null 2>&1; then
    echo "  ok   $sa"
  else
    echo "  FAIL $sa: ServiceAccount has no ghcr-pull imagePullSecret"; fail=1
  fi
done

echo "== negative cases (the image gate must REJECT these) =="
# One pod per case, gated with the dev allowlist. Each must produce a deny;
# the last one is a positive control that must pass.
neg="$render_dir/negative"
mkdir -p "$neg"
goldenReg=$(yq -r '.goldenRegistry' config/environments/dev.yaml)
i=0
expect() { # expect <deny|pass> <image> <why>
  i=$((i + 1))
  f="$neg/case-$i.yaml"
  printf 'apiVersion: v1\nkind: Pod\nmetadata:\n  name: case-%s\nspec:\n  containers:\n    - name: c\n      image: %s\n' "$i" "$2" > "$f"
  if conftest test --policy policy/conftest/image_source.rego --data "$SHARED_DATA" "$f" >/dev/null 2>&1; then got=pass; else got=deny; fi
  if [ "$got" = "$1" ]; then echo "  ok   $1  $2  ($3)"; else echo "  FAIL expected $1, got $got: $2 ($3)"; fail=1; fi
}
expect deny docker.io/library/nginx:1.27 "public Docker Hub"
expect deny nginx:latest "unqualified + :latest"
expect deny us-central1-docker.pkg.dev/gc-golden-demo/golden/python:3.12 "old Artifact Registry mirror"
expect deny cgr.dev/chriscarty.com/python:3.12 "cgr.dev directly, bypassing the mirror"
expect deny "${goldenReg}-evil/python:3.12" "look-alike prefix"
expect deny "${goldenReg}/python:latest" "golden but :latest"
expect deny "${goldenReg}/python" "golden but unpinned"
expect pass "${goldenReg}/python:3.12" "positive control"

[ "$fail" -eq 0 ] && echo "OK" || { echo "FAILED"; exit 1; }
