variable "project_id" {
  type        = string
  description = "GCP project ID."
}

variable "region" {
  type        = string
  description = "GKE + Artifact Registry region."
  default     = "us-central1"
}

variable "cluster_name" {
  type    = string
  default = "golden"
}

variable "network" {
  type    = string
  default = "default"
}

variable "subnetwork" {
  type    = string
  default = "default"
}

variable "gke_release_channel" {
  type    = string
  default = "REGULAR"
}

variable "node_machine_type" {
  type    = string
  default = "e2-standard-4"
}

variable "min_nodes" {
  type    = number
  default = 1
}

variable "max_nodes" {
  type    = number
  default = 3
}

variable "golden_repo_name" {
  type        = string
  description = "Artifact Registry repo holding the mirrored Chainguard (golden) images."
  default     = "golden"
}

variable "apps_repo_name" {
  type        = string
  description = "Artifact Registry repo holding in-house app images."
  default     = "apps"
}

variable "github_repo" {
  type        = string
  description = "owner/repo allowed to federate via Workload Identity (CI: renovate, image build/push)."
  default     = "cartyc/app-delivery"
}

variable "kyverno_namespace" {
  type    = string
  default = "kyverno"
}

# --- Private cluster (images pulled from GAR, nodes have no public IPs) ---
variable "private_cluster" {
  type        = bool
  description = "Private nodes (no external IPs) + Cloud NAT for egress. Images come from GAR."
  default     = true
}

variable "master_ipv4_cidr" {
  type        = string
  description = "Control-plane private IP range (/28) when private_cluster is true."
  default     = "172.16.0.0/28"
}

variable "master_authorized_cidrs" {
  type = list(object({
    cidr_block   = string
    display_name = string
  }))
  description = "CIDRs allowed to reach the (public) control-plane endpoint. Empty = open; set to your admin/CI ranges."
  default     = []
}

# --- GKE Security Posture (built-in compliance/misconfig + workload-vuln dashboards) ---
variable "security_posture_mode" {
  type        = string
  description = "DISABLED | BASIC | ENTERPRISE (misconfiguration scanning)."
  default     = "BASIC"
}

variable "security_posture_vulnerability_mode" {
  type        = string
  description = "VULNERABILITY_DISABLED | VULNERABILITY_BASIC | VULNERABILITY_ENTERPRISE (workload vuln scanning)."
  default     = "VULNERABILITY_BASIC"
}

# --- Resource names (defaults keep it working; override per fork/org) ---
variable "node_pool_name" {
  type    = string
  default = "primary"
}

variable "wif_pool_id" {
  type    = string
  default = "github-actions"
}

variable "wif_provider_id" {
  type    = string
  default = "github"
}

variable "ci_service_account_id" {
  type    = string
  default = "app-delivery-ci"
}

variable "kyverno_reader_service_account_id" {
  type    = string
  default = "kyverno-ar-reader"
}

variable "kyverno_controller_ksas" {
  type        = list(string)
  description = "Kyverno KSAs that do image verification (bound to the AR-reader GSA)."
  default = [
    "kyverno-admission-controller",
    "kyverno-background-controller",
  ]
}
