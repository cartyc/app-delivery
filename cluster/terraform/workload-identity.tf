# --- CI federation: GitHub Actions -> GCP via Workload Identity (no SA keys) ---
# Feeds renovate.yml (GCP_WIF_PROVIDER, GCP_SA_EMAIL) and any build/push job.
resource "google_iam_workload_identity_pool" "github" {
  workload_identity_pool_id = var.wif_pool_id
  display_name              = "GitHub Actions"
}

resource "google_iam_workload_identity_pool_provider" "github" {
  workload_identity_pool_id          = google_iam_workload_identity_pool.github.workload_identity_pool_id
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
  account_id   = var.ci_service_account_id
  display_name = "app-delivery CI (Renovate + image build/push)"
}

resource "google_service_account_iam_member" "ci_wif" {
  service_account_id = google_service_account.ci.name
  role               = "roles/iam.workloadIdentityUser"
  member             = "principalSet://iam.googleapis.com/${google_iam_workload_identity_pool.github.name}/attribute.repository/${var.github_repo}"
}

# --- Kyverno -> Artifact Registry read (to fetch signatures) via Workload Identity ---
# Bind the in-cluster Kyverno KSAs to a GSA with reader on the golden repo.
resource "google_service_account" "kyverno_reader" {
  account_id   = var.kyverno_reader_service_account_id
  display_name = "Kyverno Artifact Registry reader (signature verification)"
}

resource "google_artifact_registry_repository_iam_member" "kyverno_golden_reader" {
  location   = var.region
  repository = google_artifact_registry_repository.golden.repository_id
  role       = "roles/artifactregistry.reader"
  member     = "serviceAccount:${google_service_account.kyverno_reader.email}"
}

# Kyverno runs several controllers; bind the ones that do image verification.
resource "google_service_account_iam_member" "kyverno_wi" {
  for_each           = toset(var.kyverno_controller_ksas)
  service_account_id = google_service_account.kyverno_reader.name
  role               = "roles/iam.workloadIdentityUser"
  member             = "serviceAccount:${var.project_id}.svc.id.goog[${var.kyverno_namespace}/${each.value}]"
}
