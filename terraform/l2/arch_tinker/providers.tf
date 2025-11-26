terraform {
  required_version = ">= 1.6.0"

  required_providers {
    proxmox = {
      source  = "bpg/proxmox"
      version = ">= 0.86.0"
    }
    local = {
      source  = "hashicorp/local"
      version = "~> 2.5"
    }
  }
}

# Build the full API endpoint from your host (via TF_VAR_pve_access_host)
locals {
  pve_api_url = "${chomp(var.pve_access_host)}/api2/json"
}

# bpg/proxmox provider
# api_token must be "<TOKEN_ID>=<TOKEN_SECRET>"
provider "proxmox" {
  endpoint  = local.pve_api_url
  api_token = "${var.pm_token_id}=${var.pm_token_secret}"
  insecure  = var.pm_tls_insecure
}
