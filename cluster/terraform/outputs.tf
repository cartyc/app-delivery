# These outputs feed the rest of the system — see cluster/terraform/README.md.
output "cluster_name" {
  value = google_container_cluster.primary.name
}

output "cluster_get_credentials" {
  description = "Command to fetch kubeconfig."
  value       = "gcloud container clusters get-credentials ${google_container_cluster.primary.name} --region ${var.region} --project ${var.project_id}"
}

output "golden_registry" {
  description = "Artifact Registry golden repo (enable_artifact_registry only; null otherwise — the default is ghcr.io/<owner>/golden)."
  value       = var.enable_artifact_registry ? "${var.region}-docker.pkg.dev/${var.project_id}/${var.golden_repo_name}" : null
}

output "apps_registry" {
  description = "Artifact Registry apps repo (enable_artifact_registry only; null otherwise — the default is ghcr.io/<owner>/apps)."
  value       = var.enable_artifact_registry ? "${var.region}-docker.pkg.dev/${var.project_id}/${var.apps_repo_name}" : null
}

output "wif_provider" {
  description = "GCP_WIF_PROVIDER for a GAR-based fork (enable_github_wif only)."
  value       = var.enable_github_wif ? google_iam_workload_identity_pool_provider.github[0].name : null
}

output "ci_service_account" {
  description = "GCP_SA_EMAIL for a GAR-based fork (enable_github_wif only)."
  value       = var.enable_github_wif ? google_service_account.ci[0].email : null
}

output "kyverno_reader_service_account" {
  description = "Annotate the Kyverno KSAs with iam.gke.io/gcp-service-account = this (enable_artifact_registry only)."
  value       = var.enable_artifact_registry ? google_service_account.kyverno_reader[0].email : null
}
