# These outputs feed the rest of the system — see cluster/terraform/README.md.
output "cluster_name" {
  value = google_container_cluster.primary.name
}

output "cluster_get_credentials" {
  description = "Command to fetch kubeconfig."
  value       = "gcloud container clusters get-credentials ${google_container_cluster.primary.name} --region ${var.region} --project ${var.project_id}"
}

output "golden_registry" {
  description = "Set as goldenRegistry in config/environments/*.yaml + config/thirdparty/*.yaml."
  value       = "${var.region}-docker.pkg.dev/${var.project_id}/${var.golden_repo_name}"
}

output "apps_registry" {
  description = "Set as appsRegistry in config/environments/*.yaml."
  value       = "${var.region}-docker.pkg.dev/${var.project_id}/${var.apps_repo_name}"
}

output "wif_provider" {
  description = "Renovate secret GCP_WIF_PROVIDER."
  value       = google_iam_workload_identity_pool_provider.github.name
}

output "ci_service_account" {
  description = "Renovate secret GCP_SA_EMAIL."
  value       = google_service_account.ci.email
}

output "kyverno_reader_service_account" {
  description = "Annotate the Kyverno KSAs with iam.gke.io/gcp-service-account = this."
  value       = google_service_account.kyverno_reader.email
}
