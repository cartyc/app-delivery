# Artifact Registry: the golden mirror (cgr-sync destination) + in-house apps.
# These are the registries app-delivery's config points at.
resource "google_artifact_registry_repository" "golden" {
  location      = var.region
  repository_id = var.golden_repo_name
  format        = "DOCKER"
  description   = "Mirrored Chainguard (golden) images — cgr-sync destination."
}

resource "google_artifact_registry_repository" "apps" {
  location      = var.region
  repository_id = var.apps_repo_name
  format        = "DOCKER"
  description   = "In-house application images built FROM golden bases."
}

# GKE nodes pull from both repos.
resource "google_artifact_registry_repository_iam_member" "nodes_golden" {
  location   = var.region
  repository = google_artifact_registry_repository.golden.repository_id
  role       = "roles/artifactregistry.reader"
  member     = "serviceAccount:${google_service_account.nodes.email}"
}

resource "google_artifact_registry_repository_iam_member" "nodes_apps" {
  location   = var.region
  repository = google_artifact_registry_repository.apps.repository_id
  role       = "roles/artifactregistry.reader"
  member     = "serviceAccount:${google_service_account.nodes.email}"
}

# CI writes app images (build/push) and reads for Renovate tag lookups.
resource "google_artifact_registry_repository_iam_member" "ci_apps_writer" {
  location   = var.region
  repository = google_artifact_registry_repository.apps.repository_id
  role       = "roles/artifactregistry.writer"
  member     = "serviceAccount:${google_service_account.ci.email}"
}

resource "google_artifact_registry_repository_iam_member" "ci_golden_reader" {
  location   = var.region
  repository = google_artifact_registry_repository.golden.repository_id
  role       = "roles/artifactregistry.reader"
  member     = "serviceAccount:${google_service_account.ci.email}"
}
