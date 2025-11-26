variable "storage" {
  description = "Proxmox datastore/storage ID for the boot disk (e.g., local-lvm)"
  type        = string
  default     = "local-lvm"
}

variable "scsihw" {
  description = "SCSI controller model (e.g., virtio-scsi-pci)"
  type        = string
  default     = "virtio-scsi-pci"
}

variable "bridge" {
  description = "Bridge to attach NICs to (e.g., vmbr0)"
  type        = string
  default     = "vmbr0"
}

variable "ci_user" {
  description = "Default SSH user for cloud-init on this persona"
  type        = string
  default     = "lab"
}

variable "proxmox_vm_public_key" {
  description = "SSH public key to inject into all VMs for this persona"
  type        = string
}

variable "pve_access_host" {
  description = "Base URL for Proxmox API (e.g., https://polaris.hosts.allanshomelab.com)"
  type        = string
}

variable "pm_token_id" {
  description = "Proxmox API token ID (without secret)"
  type        = string
}

variable "pm_token_secret" {
  description = "Proxmox API token secret"
  type        = string
  sensitive   = true
}

variable "pm_tls_insecure" {
  description = "Allow insecure TLS for Proxmox API (set true if using self-signed certs)"
  type        = bool
  default     = false
}
