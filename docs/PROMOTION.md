# Promotion: dev → prod

Images flow one way — build once, promote by digest.

1. **Build + push** the app image to the private apps registry,
   `ghcr.io/cartyc/apps/<app>` (`FROM` a golden base — see the app's
   `Dockerfile`). Tag it (e.g. `0.2.0`). See *Publishing app images* below.
2. **Dev** pins the tag in `config/environments/dev.yaml` (`apps.<app>.tag`);
   `<app>-dev` auto-syncs. Verify in `demo-dev`.
3. **Promote:** capture the digest that ran in dev and set it in
   `config/environments/prod.yaml` under `apps.<app>.digest`. Prod pins by
   **digest**, never a moving tag.
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

## Publishing app images (private by default)

`ghcr.io/cartyc/apps/<app>` packages must be **private**, like the golden
mirror. This repository is public, and GitHub documents that a package a
workflow first creates with `GITHUB_TOKEN` "inherits the visibility and
permissions model of the repository". So a push from this repo's Actions to a
package that doesn't exist yet would create it **public**, and a public
package can't be made private again. golden-image hit exactly this, and now
guards against it (`goldenctl catalog guard`).

There is no publish workflow here yet. Push from your machine: a package first
pushed from the command line is private.

```bash
gh auth refresh -h github.com -s write:packages
gh auth token | docker login ghcr.io -u <github-user> --password-stdin
docker build --build-arg GOLDEN_REGISTRY=ghcr.io/cartyc/golden \
  -t ghcr.io/cartyc/apps/hello:0.2.0 apps/hello
docker push ghcr.io/cartyc/apps/hello:0.2.0
gh api /users/cartyc/packages/container/apps%2Fhello --jq .visibility   # must say: private
docker logout ghcr.io && gh auth refresh -h github.com -r write:packages
```

A CI publish workflow added later must:
- push only to packages already pre-created as private (golden-image's
  *Pre-create the golden packages (private)* runbook, with `apps/<app>` names);
- run the same guard (anonymous `tags/list` must fail; the job's token must
  read the package) before any push;
- push with `GITHUB_TOKEN` (`packages: write`) after granting this repository
  **Write** under each package's Manage Actions access.
