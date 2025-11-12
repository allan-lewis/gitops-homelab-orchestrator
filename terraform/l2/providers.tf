terraform {
  required_version = ">= 1.6.0"
  required_providers {
    proxmox = {
      source  = "Telmate/proxmox"
      version = "~> 2.9.11"
    }
    local = {
      source  = "hashicorp/local"
      version = "~> 2.5"
    }
  }
}

provider "proxmox" {
  pm_api_url          = local.pm_api_url
  pm_api_token_id     = var.pm_token_id
  pm_api_token_secret = var.pm_token_secret
  pm_tls_insecure     = var.pm_tls_insecure
}
