# --- OPTIONAL (enable_github_wif, default false): GitHub Actions -> GCP via
# Workload Identity Federation. Only useful with enable_artifact_registry: the
# default ghcr.io registry needs no GCP identity (Renovate reads it with
# GITHUB_TOKEN). Feeds GCP_WIF_PROVIDER / GCP_SA_EMAIL for a GAR-based fork.
resource "google_iam_workload_identity_pool" "github" {
  count                     = var.enable_github_wif ? 1 : 0
  workload_identity_pool_id = var.wif_pool_id
  display_name              = "GitHub Actions"
}

resource "google_iam_workload_identity_pool_provider" "github" {
  count                              = var.enable_github_wif ? 1 : 0
  workload_identity_pool_id          = google_iam_workload_identity_pool.github[0].workload_identity_pool_id
  workload_identity_pool_provider_id = var.wif_provider_id
  display_name                       = "GitHub OIDC"

  oidc {
    issuer_uri = "https://token.actions.githubusercontent.com"
  }
  attribute_mapping = {
    "google.subject"       = "assertion.sub"
    "attribute.repository" = "assertion.repository"
  }
  # Only this repo may federate.
  attribute_condition = "assertion.repository == \"${var.github_repo}\""
}

resource "google_service_account" "ci" {
  count        = var.enable_github_wif ? 1 : 0
  account_id   = var.ci_service_account_id
  display_name = "app-delivery CI (Renovate + image build/push)"
}

resource "google_service_account_iam_member" "ci_wif" {
  count              = var.enable_github_wif ? 1 : 0
  service_account_id = google_service_account.ci[0].name
  role               = "roles/iam.workloadIdentityUser"
  member             = "principalSet://iam.googleapis.com/${google_iam_workload_identity_pool.github[0].name}/attribute.repository/${var.github_repo}"
}

# --- Kyverno -> Artifact Registry read (to fetch signatures), only with
# enable_artifact_registry. With ghcr.io, Kyverno reads signatures with the
# `ghcr-pull` secret instead (config/platform-charts/kyverno.yaml).
resource "google_service_account" "kyverno_reader" {
  count        = local.ar
  account_id   = var.kyverno_reader_service_account_id
  display_name = "Kyverno Artifact Registry reader (signature verification)"
}

resource "google_artifact_registry_repository_iam_member" "kyverno_golden_reader" {
  count      = local.ar
  location   = var.region
  repository = google_artifact_registry_repository.golden[0].repository_id
  role       = "roles/artifactregistry.reader"
  member     = "serviceAccount:${google_service_account.kyverno_reader[0].email}"
}

# Kyverno runs several controllers; bind the ones that do image verification.
resource "google_service_account_iam_member" "kyverno_wi" {
  for_each           = var.enable_artifact_registry ? toset(var.kyverno_controller_ksas) : toset([])
  service_account_id = google_service_account.kyverno_reader[0].name
  role               = "roles/iam.workloadIdentityUser"
  member             = "serviceAccount:${var.project_id}.svc.id.goog[${var.kyverno_namespace}/${each.value}]"
}
