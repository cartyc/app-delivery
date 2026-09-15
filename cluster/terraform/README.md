# cluster/terraform — GKE provisioning

Stands up the GKE cluster + the GCP plumbing app-delivery needs:

- **GKE cluster** (VPC-native, **private nodes**, Workload Identity, shielded
  auto-repair/upgrade node pool with autoscaling) + a least-privilege node SA.
- **Private nodes + Cloud NAT** (`private_cluster = true`): nodes have no public
  IPs. Images pull from Artifact Registry (Private Google Access); NAT covers the
  remaining public egress ArgoCD needs (Git + upstream chart repos). Set
  `private_cluster = false` for a public demo cluster.
- **GKE Security Posture** (`BASIC` by default): misconfiguration + workload
  vulnerability scanning, surfaced in the built-in Security Posture dashboard.
- **Artifact Registry** repos: `golden` (cgr-sync mirror of Chainguard images)
  and `apps` (in-house images), with node read + CI write IAM.
- **Workload Identity federation** for GitHub Actions (Renovate + image
  build/push) — no service-account keys.
- **Kyverno → Artifact Registry reader** GSA + WI binding, so the signature
  policy can fetch signatures from the private registry.

## Use
```bash
cd cluster/terraform
cp terraform.tfvars.example terraform.tfvars   # edit project_id, region, github_repo
terraform init
terraform plan
terraform apply
```
Prereqs: enable the `container`, `artifactregistry`, `iam`, and
`iamcredentials` APIs; run as a principal with project admin. Configure a GCS
backend in `versions.tf` for shared state.

## Outputs → the rest of the system
| Output | Where it goes |
|---|---|
| `golden_registry` | `goldenRegistry` in `config/environments/*.yaml` + `config/thirdparty/*.yaml` |
| `apps_registry` | `appsRegistry` in `config/environments/*.yaml` |
| `wif_provider` | Renovate secret `GCP_WIF_PROVIDER` |
| `ci_service_account` | Renovate secret `GCP_SA_EMAIL` |
| `kyverno_reader_service_account` | annotate the Kyverno KSAs `iam.gke.io/gcp-service-account` |
| `cluster_get_credentials` | run it to get kubeconfig, then `cluster/bootstrap/` |

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
- **Private Google Access** must be enabled on the node subnet for image pulls
  to stay off NAT; Cloud NAT is the fallback path.
