# cluster/terraform — GKE provisioning

Stands up the GKE cluster + the GCP plumbing app-delivery needs:

- **GKE cluster** (VPC-native, **private nodes**, Workload Identity, shielded
  auto-repair/upgrade node pool with autoscaling) + a least-privilege node SA.
- **Private nodes + Cloud NAT** (`private_cluster = true`): nodes have no public
  IPs. Images pull from private ghcr.io (`ghcr.io/<owner>/golden` and `/apps`)
  through the NAT, with the `ghcr-pull` secret that bootstrap creates
  (`docs/PULL-SECRET.md`). The NAT also covers ArgoCD's Git + chart egress. Set
  `private_cluster = false` for a public demo cluster.
- **GKE Security Posture** (`BASIC` by default): misconfiguration + workload
  vulnerability scanning, surfaced in the built-in Security Posture dashboard.

**Optional, off by default.** These are for a fork that mirrors into Google
Artifact Registry instead of ghcr.io:

| Variable (default `false`) | Creates |
|---|---|
| `enable_artifact_registry` | Artifact Registry repos `golden` + `apps`, node read IAM, and the Kyverno → AR reader GSA + Workload Identity binding |
| `enable_github_wif` | Workload Identity Federation for GitHub Actions + the CI service account (with `enable_artifact_registry`, CI write/read on the repos) |

## Use
```bash
cd cluster/terraform
cp terraform.tfvars.example terraform.tfvars   # edit project_id, region, github_repo
terraform init
terraform plan
terraform apply
```
Prereqs: enable the `container` API (plus `artifactregistry`, `iam` and
`iamcredentials` if you turn on the optional pieces); run as a principal with project admin. Configure a GCS
backend in `versions.tf` for shared state.

## Outputs → the rest of the system
| Output | Where it goes |
|---|---|
| `cluster_get_credentials` | run it to get kubeconfig, then `cluster/bootstrap/` |
| `golden_registry`, `apps_registry` | `enable_artifact_registry` only (else `null`): `goldenRegistry` / `appsRegistry` in `config/` |
| `wif_provider`, `ci_service_account` | `enable_github_wif` only (else `null`): CI secrets for a GAR-based fork |
| `kyverno_reader_service_account` | `enable_artifact_registry` only (else `null`): annotate the Kyverno KSAs `iam.gke.io/gcp-service-account` |

## Notes
- **Service mesh:** this provisions the cluster; install Istio (or enable GKE
  managed ASM via the Fleet API) in the bootstrap step. Kept out of Terraform so
  you can choose self-managed Istio vs managed ASM.
- `terraform.tfvars` and state are gitignored — never commit them.
- **Private-cluster access:** the control-plane keeps a *public* endpoint
  (`enable_private_endpoint = false`) but you should restrict it with
  `master_authorized_cidrs` (your admin/CI IPs). `bootstrap.sh` / `kubectl` /
  ArgoCD must connect from an allowed range. For a fully-private endpoint, set
  `enable_private_endpoint = true` and reach it via a bastion/VPN.
- With `enable_artifact_registry`, enable **Private Google Access** on the node
  subnet so GAR pulls stay off NAT. ghcr.io pulls always use the NAT.
