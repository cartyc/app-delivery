# Cloud NAT for private nodes' egress. Golden images come from Artifact Registry
# via Private Google Access; NAT covers the remaining public egress ArgoCD needs
# (Git + upstream Helm chart repos). Only created for a private cluster.
resource "google_compute_router" "nat" {
  count   = var.private_cluster ? 1 : 0
  name    = "${var.cluster_name}-router"
  region  = var.region
  network = var.network
}

resource "google_compute_router_nat" "nat" {
  count                              = var.private_cluster ? 1 : 0
  name                               = "${var.cluster_name}-nat"
  router                             = google_compute_router.nat[0].name
  region                             = var.region
  nat_ip_allocate_option             = "AUTO_ONLY"
  source_subnetwork_ip_ranges_to_nat = "ALL_SUBNETWORKS_ALL_IP_RANGES"

  log_config {
    enable = true
    filter = "ERRORS_ONLY"
  }
}
