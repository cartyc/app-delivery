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

  # Private nodes: no external IPs. Images pull from Artifact Registry (via
  # Private Google Access / Cloud NAT); public egress (charts, Git) goes through
  # the Cloud NAT in network.tf. Control-plane keeps a public endpoint, so
  # restrict it with master_authorized_cidrs.
  dynamic "private_cluster_config" {
    for_each = var.private_cluster ? [1] : []
    content {
      enable_private_nodes    = true
      enable_private_endpoint = false
      master_ipv4_cidr_block  = var.master_ipv4_cidr
    }
  }

  dynamic "master_authorized_networks_config" {
    for_each = length(var.master_authorized_cidrs) > 0 ? [1] : []
    content {
      dynamic "cidr_blocks" {
        for_each = var.master_authorized_cidrs
        content {
          cidr_block   = cidr_blocks.value.cidr_block
          display_name = cidr_blocks.value.display_name
        }
      }
    }
  }

  # GKE Security Posture: misconfiguration scanning + workload vulnerability
  # scanning, surfaced in the built-in Security Posture dashboard. BASIC is free.
  security_posture_config {
    mode               = var.security_posture_mode
    vulnerability_mode = var.security_posture_vulnerability_mode
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
