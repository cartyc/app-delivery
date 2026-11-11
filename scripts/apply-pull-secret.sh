#!/usr/bin/env bash
# Create or update the `ghcr-pull` image pull secret (kubernetes.io/dockerconfigjson)
# in every namespace that pulls golden or in-house app images from the PRIVATE
# ghcr.io registries. Works the same on kind and GKE: nothing depends on the
# node's cloud identity.
#
# The token is a GitHub token with the read:packages scope that YOU supply
# (docs/PULL-SECRET.md). It is read from stdin, never from a flag, so it
# doesn't land in your shell history or the process list, and it is never
# written to the repo:
#
#   printf '%s' "$TOKEN" | GHCR_USERNAME=<github-user> ./scripts/apply-pull-secret.sh
#   # or paste it at the prompt:
#   GHCR_USERNAME=<github-user> ./scripts/apply-pull-secret.sh
#
# Re-run with a new token to rotate: it updates the Secret in place in every
# namespace. Running pods keep running; new pulls use the new token.
#
# Env:
#   GHCR_USERNAME        GitHub user that owns the token (required)
#   GHCR_REGISTRY        registry host (default ghcr.io)
#   PULL_SECRET_NAME     Secret name (default ghcr-pull; the manifests and
#                        config/ files reference this name)
#   PULL_SECRET_NAMESPACES  space-separated namespaces (default below)
set -euo pipefail

: "${GHCR_USERNAME:?set GHCR_USERNAME (the GitHub user that owns the read:packages token)}"
REGISTRY="${GHCR_REGISTRY:-ghcr.io}"
NAME="${PULL_SECRET_NAME:-ghcr-pull}"
# argocd: Argo CD + redis. cert-manager, kyverno: platform charts. kube-system:
# kube-state-metrics. demo-dev, demo-prod: in-house apps.
NAMESPACES="${PULL_SECRET_NAMESPACES:-argocd cert-manager kyverno kube-system demo-dev demo-prod}"

if [ -t 0 ]; then
  printf 'read:packages token for %s (input hidden): ' "$GHCR_USERNAME" >&2
  IFS= read -rs TOKEN
  echo >&2
else
  IFS= read -r TOKEN || true
fi
[ -n "${TOKEN:-}" ] || { echo "no token on stdin" >&2; exit 1; }

# Build the dockerconfigjson in a private temp file (never in argv).
umask 077
tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT
auth="$(printf '%s:%s' "$GHCR_USERNAME" "$TOKEN" | base64 | tr -d '\n')"
unset TOKEN
printf '{"auths":{"%s":{"auth":"%s"}}}' "$REGISTRY" "$auth" > "$tmp/config.json"
unset auth

for ns in $NAMESPACES; do
  # Namespaces Argo CD later manages (via platform/ or CreateNamespace) are
  # created here only if missing, so the Secret exists before the first pull.
  kubectl get namespace "$ns" >/dev/null 2>&1 || kubectl create namespace "$ns" >/dev/null
  kubectl create secret generic "$NAME" \
    --namespace "$ns" \
    --type=kubernetes.io/dockerconfigjson \
    --from-file=.dockerconfigjson="$tmp/config.json" \
    --dry-run=client -o yaml | kubectl apply -f - >/dev/null
  echo "  $ns/$NAME applied"
done
echo "Pull secret $NAME for $REGISTRY applied in: $NAMESPACES"
