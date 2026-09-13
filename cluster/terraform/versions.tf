terraform {
  required_version = ">= 1.6"
  required_providers {
    google = {
      source  = "hashicorp/google"
      version = "~> 6.0"
    }
    google-beta = {
      source  = "hashicorp/google-beta"
      version = "~> 6.0"
    }
  }
  # Configure a remote backend (GCS) for real use, e.g.:
  # backend "gcs" { bucket = "my-tf-state"; prefix = "app-delivery/cluster" }
}
