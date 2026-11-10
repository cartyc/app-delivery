# OPTIONAL (enable_artifact_registry, default false): Artifact Registry repos
# for golden + apps images. The default registry is now private ghcr.io
# (ghcr.io/<owner>/golden and /apps, pulled with the `ghcr-pull` secret), so
# these exist only for a fork that mirrors into GAR instead.
locals {
  ar     = var.enable_artifact_registry ? 1 : 0
  ar_wif = var.enable_artifact_registry && var.enable_github_wif ? 1 : 0
}

resource "google_artifact_registry_repository" "golden" {
  count         = local.ar
  location      = var.region
  repository_id = var.golden_repo_name
  format        = "DOCKER"
  description   = "Mirrored Chainguard (golden) images — cgr-sync destination."
}

resource "google_artifact_registry_repository" "apps" {
  count         = local.ar
  location      = var.region
  repository_id = var.apps_repo_name
  format        = "DOCKER"
  description   = "In-house application images built FROM golden bases."
}

# GKE nodes pull from both repos.
resource "google_artifact_registry_repository_iam_member" "nodes_golden" {
  count      = local.ar
  location   = var.region
  repository = google_artifact_registry_repository.golden[0].repository_id
  role       = "roles/artifactregistry.reader"
  member     = "serviceAccount:${google_service_account.nodes.email}"
}

resource "google_artifact_registry_repository_iam_member" "nodes_apps" {
  count      = local.ar
  location   = var.region
  repository = google_artifact_registry_repository.apps[0].repository_id
  role       = "roles/artifactregistry.reader"
  member     = "serviceAccount:${google_service_account.nodes.email}"
}

# CI writes app images (build/push) and reads for Renovate tag lookups. Needs
# the GitHub WIF CI service account too.
resource "google_artifact_registry_repository_iam_member" "ci_apps_writer" {
  count      = local.ar_wif
  location   = var.region
  repository = google_artifact_registry_repository.apps[0].repository_id
  role       = "roles/artifactregistry.writer"
  member     = "serviceAccount:${google_service_account.ci[0].email}"
}

resource "google_artifact_registry_repository_iam_member" "ci_golden_reader" {
  count      = local.ar_wif
  location   = var.region
  repository = google_artifact_registry_repository.golden[0].repository_id
  role       = "roles/artifactregistry.reader"
  member     = "serviceAccount:${google_service_account.ci[0].email}"
}
