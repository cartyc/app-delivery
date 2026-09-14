provider "google" {
  project = var.project_id
  region  = var.region
}

provider "google-beta" {
  project = var.project_id
  region  = var.region
}

# --- GKE cluster: VPC-native, Workload Identity, shielded nodes ---
resource "google_container_cluster" "primary" {
  name     = var.cluster_name
  location = var.region

  # Manage node pools separately (below).
  remove_default_node_pool = true
  initial_node_count       = 1

  networking_mode = "VPC_NATIVE"
  network         = var.network
  subnetwork      = var.subnetwork
  ip_allocation_policy {}

  release_channel {
    channel = var.gke_release_channel
  }

  # Workload Identity: lets KSAs impersonate GSAs (used for app GCP access +
  # Kyverno reading signatures from Artifact Registry).
  workload_identity_config {
    workload_pool = "${var.project_id}.svc.id.goog"
  }

  # Demo convenience — set true (or remove) for production clusters.
  deletion_protection = false
}

resource "google_service_account" "nodes" {
  account_id   = "${var.cluster_name}-nodes"
  display_name = "GKE node service account for ${var.cluster_name}"
}

# Least-privilege node roles (logging/monitoring); Artifact Registry read is
# granted per-repo in artifact-registry.tf.
resource "google_project_iam_member" "nodes" {
  for_each = toset([
    "roles/logging.logWriter",
    "roles/monitoring.metricWriter",
    "roles/monitoring.viewer",
    "roles/stackdriver.resourceMetadata.writer",
  ])
  project = var.project_id
  role    = each.value
  member  = "serviceAccount:${google_service_account.nodes.email}"
}

resource "google_container_node_pool" "primary" {
  name     = var.node_pool_name
  cluster  = google_container_cluster.primary.id
  location = var.region

  autoscaling {
    min_node_count = var.min_nodes
    max_node_count = var.max_nodes
  }

  node_config {
    machine_type    = var.node_machine_type
    service_account = google_service_account.nodes.email
    oauth_scopes    = ["https://www.googleapis.com/auth/cloud-platform"]

    workload_metadata_config {
      mode = "GKE_METADATA" # required for Workload Identity
    }
    shielded_instance_config {
      enable_secure_boot          = true
      enable_integrity_monitoring = true
    }
    labels = {
      cluster = var.cluster_name
    }
  }

  management {
    auto_repair  = true
    auto_upgrade = true
  }
}
