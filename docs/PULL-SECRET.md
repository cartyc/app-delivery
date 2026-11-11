# Image pull secret (`ghcr-pull`)

Every image the cluster runs comes from a **private** GitHub Container Registry
namespace:

- `ghcr.io/cartyc/golden/<image>`: Chainguard images mirrored by
  [golden-image](https://github.com/cartyc/golden-image) (Argo CD, redis,
  cert-manager, Kyverno, kube-state-metrics).
- `ghcr.io/cartyc/apps/<app>`: the in-house apps (`hello`, `api`).

The cluster pulls them with one `kubernetes.io/dockerconfigjson` Secret named
`ghcr-pull`, created at bootstrap from a token **you** supply. The token is
never committed and never minted by this repo. The same flow works on kind and
on GKE, because nothing depends on the node's cloud identity.

## 1. Create a read-only token

ghcr.io accepts only a **personal access token (classic)**. GitHub's
[Container registry docs](https://docs.github.com/en/packages/working-with-a-github-packages-registry/working-with-the-container-registry)
say "GitHub Packages only supports authentication using a personal access
token (classic)", so a fine-grained token won't work here.

1. Go to **Settings → Developer settings → Personal access tokens → Tokens
   (classic) → Generate new token (classic)**.
2. Select **only** `read:packages`. It's enough to pull, and it can't push,
   delete or change package visibility.
3. Set an expiry (for example 90 days) and note the date: it's your rotation
   reminder.

The token's owner needs read access to the packages. The package owner always
has it. For anyone else, add them to each package's access settings (Read).

Prefer a dedicated machine account as the owner over your personal account if
the cluster outlives the demo: the token can then read only what that account
was granted.

## 2. Create the Secret (bootstrap)

`cluster/bootstrap/bootstrap.sh` calls `scripts/apply-pull-secret.sh` first.
Pass the token on stdin, never as a flag:

```bash
# paste at the hidden prompt:
GHCR_USERNAME=<github-user> ./cluster/bootstrap/bootstrap.sh

# or pipe it from a password manager / file you control:
op read op://vault/ghcr-read/token | GHCR_USERNAME=<github-user> ./cluster/bootstrap/bootstrap.sh
```

The script writes the dockerconfigjson to a 0600 temp file (deleted on exit),
so the token isn't in argv or your shell history. It creates `ghcr-pull`
in each namespace that pulls a private image, creating any namespace that
doesn't exist yet:

| Namespace | Pulls |
|---|---|
| `argocd` | Argo CD + redis (bootstrap Helm install) |
| `cert-manager` | cert-manager (platform-charts lane) |
| `kyverno` | Kyverno; it also reads golden **signatures** with this secret |
| `kube-system` | kube-state-metrics (third-party lane) |
| `demo-dev`, `demo-prod` | the in-house apps |

Override the list with `PULL_SECRET_NAMESPACES`, the name with
`PULL_SECRET_NAME` (the manifests reference `ghcr-pull`), or the host with
`GHCR_REGISTRY`.

## 3. How workloads reference it

Each lane uses the narrowest reference available:

- **Charts** set the chart's own pull-secret value. A chart creates its own
  ServiceAccounts, so patching a default ServiceAccount wouldn't reach them,
  and each chart keeps the value at a different path. So each `config/` file
  names the path (`imagePullSecretsParam`) and the secret (`imagePullSecrets`),
  and the ApplicationSet and `validate.sh` render
  `<imagePullSecretsParam>[N].name`:
  - cert-manager and Kyverno use `global.imagePullSecrets`. Kyverno's top-level
    `imagePullSecrets` is a different thing: a map of credentials it would
    create itself.
  - kube-state-metrics uses `imagePullSecrets`.
  - Argo CD: `bootstrap.sh` sets `global.imagePullSecrets[0].name`.
- **Kyverno signature checks** read golden images' cosign `.sig`/`.att` tags
  from the private registry, using the same secret
  (`existingImagePullSecrets[0]: ghcr-pull` →
  `--imagePullSecrets=ghcr-pull`).
- **In-house apps** list it on their own ServiceAccount
  (`apps/*/base/serviceaccount.yaml`). Every pod running as that account
  inherits it, so the Deployments stay generic. Patching the namespace's
  `default` ServiceAccount would also reach pods that don't need registry
  access.

`scripts/validate.sh` fails if any chart workload (or the ServiceAccount it runs
as) or an app ServiceAccount is missing `ghcr-pull`.

## 4. Rotate

Rotate before the token expires, or at once if it leaks:

1. Create a new token (step 1).
2. Re-apply. This updates the Secret in place in every namespace:
   ```bash
   GHCR_USERNAME=<github-user> ./scripts/apply-pull-secret.sh
   ```
   Running pods keep running. The kubelet reads the Secret on each new pull,
   so restarts, rescheduling and new rollouts use the new token. Nothing needs
   restarting.
3. Optional check: restart a deployment so it pulls again, e.g.
   `kubectl -n demo-dev rollout restart deploy/hello`. Watch for
   `ErrImagePull`/`401`.
4. Delete the old token in GitHub (**Tokens (classic) → Delete**).

If a pull fails with `401` or `403`, the token has expired or lacks
`read:packages`, or its owner can't read that package.

## kind vs GKE

- **kind:** `kind create cluster`, then run bootstrap. Nothing else is needed.
- **GKE** (`cluster/terraform`): same steps. Private nodes reach ghcr.io
  through the Cloud NAT that Terraform creates. The Artifact Registry and
  Workload Identity Federation pieces are off by default
  (`enable_artifact_registry`, `enable_github_wif`) and aren't used by the
  ghcr.io flow.
