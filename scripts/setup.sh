#!/usr/bin/env bash
# One-time initializer: replace the demo placeholders with your real values.
# Rewrites tracked files in place (safe literal replacement via perl quotemeta).
# Run once on a fresh clone, review `git diff`, then commit.
#
#   ./scripts/setup.sh \
#     --github   OWNER/REPO \
#     --gar-region us-central1 \
#     --gar-project my-gcp-project \
#     --domain    apps.example.com \
#     [--cgr-org my-chainguard-org] \        # cgr.dev source org (default: gar-project)
#     [--cgr-org-uidp <uidp>] \              # org UIDP for the Kyverno signature policy

#     [--golden-repo golden] [--apps-repo apps] \
#     [--dev-cluster golden-dev] [--prod-cluster golden-prod] \
#     [--dry-run]
set -euo pipefail
cd "$(dirname "$0")/.."

# --- defaults ---
GITHUB="" GAR_REGION="" GAR_PROJECT="" DOMAIN="" CGR_ORG=""
CGR_ORG_UIDP="ORG_UIDP_PLACEHOLDER" # left as placeholder unless --cgr-org-uidp given
GOLDEN_REPO="golden" APPS_REPO="apps"
DEV_CLUSTER="golden-dev" PROD_CLUSTER="golden-prod"
DRY_RUN="false"

usage() { sed -n '2,16p' "$0"; exit "${1:-0}"; }

while [ $# -gt 0 ]; do
  case "$1" in
    --github)       GITHUB="$2"; shift 2;;
    --gar-region)   GAR_REGION="$2"; shift 2;;
    --gar-project)  GAR_PROJECT="$2"; shift 2;;
    --domain)       DOMAIN="$2"; shift 2;;
    --cgr-org)      CGR_ORG="$2"; shift 2;;
    --cgr-org-uidp) CGR_ORG_UIDP="$2"; shift 2;;
    --golden-repo)  GOLDEN_REPO="$2"; shift 2;;
    --apps-repo)    APPS_REPO="$2"; shift 2;;
    --dev-cluster)  DEV_CLUSTER="$2"; shift 2;;
    --prod-cluster) PROD_CLUSTER="$2"; shift 2;;
    --dry-run)      DRY_RUN="true"; shift;;
    -h|--help)      usage 0;;
    *) echo "unknown flag: $1" >&2; usage 1;;
  esac
done

# --- required ---
missing=""
[ -n "$GITHUB" ]      || missing="$missing --github"
[ -n "$GAR_REGION" ]  || missing="$missing --gar-region"
[ -n "$GAR_PROJECT" ] || missing="$missing --gar-project"
[ -n "$DOMAIN" ]      || missing="$missing --domain"
if [ -n "$missing" ]; then echo "missing required:$missing" >&2; usage 1; fi
[ -n "$CGR_ORG" ] || CGR_ORG="$GAR_PROJECT"

case "$GITHUB" in */*) : ;; *) echo "--github must be OWNER/REPO" >&2; exit 1;; esac

GAR="${GAR_REGION}-docker.pkg.dev/${GAR_PROJECT}"

# from -> to (order matters: most specific first)
PAIRS=(
  "us-central1-docker.pkg.dev/gc-golden-demo/golden|${GAR}/${GOLDEN_REPO}"
  "us-central1-docker.pkg.dev/gc-golden-demo/apps|${GAR}/${APPS_REPO}"
  "us-central1-docker.pkg.dev/gc-golden-demo|${GAR}"
  "cgr.dev/gc-golden-demo|cgr.dev/${CGR_ORG}"
  "cgrOrg: gc-golden-demo|cgrOrg: ${CGR_ORG}"
  "region: us-central1|region: ${GAR_REGION}"
  "project: gc-golden-demo|project: ${GAR_PROJECT}"
  "cluster: golden-dev|cluster: ${DEV_CLUSTER}"
  "cluster: golden-prod|cluster: ${PROD_CLUSTER}"
  "cartyc/app-delivery|${GITHUB}"
  "example.com|${DOMAIN}"
  "ORG_UIDP_PLACEHOLDER|${CGR_ORG_UIDP}"
)

# Every tracked text file except this script (which holds the placeholders).
FILES=()
while IFS= read -r f; do FILES+=("$f"); done < <(git ls-files | grep -v '^scripts/setup.sh$')

echo "Rewriting placeholders in ${#FILES[@]} files:"
for p in "${PAIRS[@]}"; do echo "  ${p%%|*}  ->  ${p#*|}"; done
echo

if [ "$DRY_RUN" = "true" ]; then
  echo "[dry-run] matches that would change:"
  for p in "${PAIRS[@]}"; do
    n=$(grep -rlF "${p%%|*}" "${FILES[@]}" 2>/dev/null | wc -l | tr -d ' ')
    echo "  ${p%%|*}: $n file(s)"
  done
  exit 0
fi

for p in "${PAIRS[@]}"; do
  FROM="${p%%|*}" TO="${p#*|}" perl -pi -e 'BEGIN{$f=$ENV{FROM};$t=$ENV{TO}} s/\Q$f\E/$t/g' "${FILES[@]}"
done

echo "Done. Review 'git diff', run ./scripts/validate.sh, then commit + push."
