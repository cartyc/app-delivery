#!/usr/bin/env bash
# One-time initializer: replace the demo placeholders with your real values.
# Rewrites tracked files in place (safe literal replacement via perl quotemeta).
# Run once on a fresh clone, review `git diff`, then commit.
#
#   ./scripts/setup.sh \
#     --github   OWNER/REPO \
#     --domain    apps.example.com \
#     [--registry-owner ghcr-owner] \       # ghcr.io namespace (default: OWNER from --github)
#     [--golden-repo golden] [--apps-repo apps] \
#     [--gcp-project my-gcp-project] [--gcp-region us-central1] \  # terraform example only
#     [--dev-cluster golden-dev] [--prod-cluster golden-prod] \
#     [--dry-run]
#
# Registries become ghcr.io/<registry-owner>/<golden-repo> and /<apps-repo>
# (private GitHub packages, pulled with the ghcr-pull secret). A user account's
# package settings live at github.com/users/<owner>/packages; for an
# organization use github.com/orgs/<owner>/packages instead.
set -euo pipefail
cd "$(dirname "$0")/.."

# --- defaults ---
GITHUB="" DOMAIN="" REG_OWNER="" GCP_PROJECT="" GCP_REGION=""
GOLDEN_REPO="golden" APPS_REPO="apps"
DEV_CLUSTER="golden-dev" PROD_CLUSTER="golden-prod"
DRY_RUN="false"

usage() { sed -n '2,19p' "$0"; exit "${1:-0}"; }

while [ $# -gt 0 ]; do
  case "$1" in
    --github)       GITHUB="$2"; shift 2;;
    --domain)       DOMAIN="$2"; shift 2;;
    --registry-owner) REG_OWNER="$2"; shift 2;;
    --gcp-project)  GCP_PROJECT="$2"; shift 2;;
    --gcp-region)   GCP_REGION="$2"; shift 2;;
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
[ -n "$GITHUB" ] || missing="$missing --github"
[ -n "$DOMAIN" ] || missing="$missing --domain"
if [ -n "$missing" ]; then echo "missing required:$missing" >&2; usage 1; fi

case "$GITHUB" in */*) : ;; *) echo "--github must be OWNER/REPO" >&2; exit 1;; esac
[ -n "$REG_OWNER" ] || REG_OWNER="${GITHUB%%/*}"
# OCI repository names must be lowercase.
REG_OWNER="$(printf '%s' "$REG_OWNER" | tr '[:upper:]' '[:lower:]')"

# from -> to (order matters: most specific first)
PAIRS=(
  "ghcr.io/cartyc/golden|ghcr.io/${REG_OWNER}/${GOLDEN_REPO}"
  "ghcr.io/cartyc/apps|ghcr.io/${REG_OWNER}/${APPS_REPO}"
  "golden%2F|${GOLDEN_REPO}%2F"
  "apps%2F|${APPS_REPO}%2F"
  "users/cartyc/packages|users/${REG_OWNER}/packages"
  "cluster: golden-dev|cluster: ${DEV_CLUSTER}"
  "cluster: golden-prod|cluster: ${PROD_CLUSTER}"
  "cartyc/app-delivery|${GITHUB}"
  "example.com|${DOMAIN}"
)
[ -n "$GCP_PROJECT" ] && PAIRS+=("project_id  = \"gc-golden-demo\"|project_id  = \"${GCP_PROJECT}\"")
[ -n "$GCP_REGION" ] && PAIRS+=("region      = \"us-central1\"|region      = \"${GCP_REGION}\"")

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
