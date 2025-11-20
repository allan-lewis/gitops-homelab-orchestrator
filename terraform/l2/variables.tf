# --- Proxmox connection variables (from environment) ---

variable "pve_access_host" {
  description = "Base Proxmox API host, e.g. https://proxmox.allanshomelab.com"
  type        = string
}

variable "pm_token_id" {
  description = "Proxmox API token ID"
  type        = string
}

variable "pm_token_secret" {
  description = "Proxmox API token secret"
  type        = string
}

variable "pm_tls_insecure" {
  description = "Set true to skip TLS verification"
  type        = bool
  default     = false
}

# --- VM defaults ---

variable "storage" {
  description = "Storage ID for VM disks"
  type        = string
  default     = "local-lvm"
}

variable "scsihw" {
  description = "SCSI controller type"
  type        = string
  default     = "virtio-scsi-pci"
}

variable "bridge" {
  description = "Default network bridge"
  type        = string
  default     = "vmbr0"
}

variable "ci_user" {
  description = "Default cloud-init user"
  type        = string
  default     = "lab"
}

variable "proxmox_vm_public_key" {
  description = "Public SSH key injected from environment (TF_VAR_PROXMOX_VM_PUBLIC_KEY)"
  type        = string
}
