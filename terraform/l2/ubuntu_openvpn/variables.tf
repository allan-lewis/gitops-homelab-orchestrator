#
# Proxmox provider variables
#

variable "pve_access_host" {
  description = "Base URL for Proxmox API (e.g., https://shardik.hosts.allanshomelab.com)"
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
  description = "Allow insecure TLS for Proxmox API (set true for self-signed certs)"
  type        = bool
  default     = false
}

#
# Persona-level VM configuration defaults
#

variable "storage" {
  description = "Proxmox datastore/storage ID for the boot disk"
  type        = string
  default     = "ssd0"
}

variable "scsihw" {
  description = "SCSI controller model"
  type        = string
  default     = "virtio-scsi-pci"
}

variable "bridge" {
  description = "Network bridge to connect VMs to"
  type        = string
  default     = "vmbr0"
}

variable "ci_user" {
  description = "Default cloud-init username for all hosts in this persona"
  type        = string
  default     = "lab"
}

variable "proxmox_vm_public_key" {
  description = "SSH public key to inject for the default user"
  type        = string
}

variable "agent_enabled" {
  description = "Whether to enable the QEMU guest agent for VMs in this environment"
  type        = bool
  default     = false
}
