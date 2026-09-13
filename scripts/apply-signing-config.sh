#!/usr/bin/env bash
# Create/update the ConfigMap the Kyverno signature policy reads the org UIDP
# from — sourced from an ENV VAR, so the UIDP is never committed to Git.
#
#   CHAINGUARD_ORG_UIDP=<your-org-uidp> ./scripts/apply-signing-config.sh
#
# Run once at bootstrap (and whenever the UIDP changes). Requires kubectl context
# pointed at the target cluster; Kyverno must be installed (kyverno namespace).
set -euo pipefail

: "${CHAINGUARD_ORG_UIDP:?set CHAINGUARD_ORG_UIDP (your Chainguard org UIDP)}"
NS="${KYVERNO_NAMESPACE:-kyverno}"

kubectl create configmap golden-signing-config \
  --namespace "$NS" \
  --from-literal=orgUidp="$CHAINGUARD_ORG_UIDP" \
  --dry-run=client -o yaml | kubectl apply -f -

echo "golden-signing-config applied in namespace $NS (orgUidp from \$CHAINGUARD_ORG_UIDP)."
