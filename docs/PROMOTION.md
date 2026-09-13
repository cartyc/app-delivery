# Promotion: dev → prod

Images flow one way — build once, promote by digest.

1. **Build + push** the app image to the golden `apps/` Artifact Registry
   (`FROM` a golden base — see the app's `Dockerfile`). Tag it (e.g. `0.2.0`).
2. **Dev** overlay pins the tag; `hello-dev` auto-syncs. Verify in `demo-dev`.
3. **Promote:** capture the digest that ran in dev and set it in
   `apps/<app>/overlays/prod/kustomization.yaml` under `images: [...].digest`.
   Prod pins by **digest**, never a moving tag.
4. Open a PR — the Validate gate must pass (golden registry, pinned, hardened).
5. Merge, then **manually sync** `hello-prod` in ArgoCD (prod is not auto-synced).

## Why digest-in-prod
A tag can be re-pushed; a digest can't. Promoting the exact digest that passed
dev guarantees prod runs the identical, golden-built artifact — and keeps the
supply chain honest end-to-end (cgr-sync → golden-image → app-delivery).

## Get the running digest
```bash
kubectl -n demo-dev get deploy hello \
  -o jsonpath='{.spec.template.spec.containers[0].image}'
# or the resolved digest from the ReplicaSet / image status
```
