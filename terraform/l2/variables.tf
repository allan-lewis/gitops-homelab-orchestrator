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

# --- L1 manifest path ---

variable "l1_manifest_path" {
  description = "Path to L1 manifest JSON produced by image build"
  type        = string
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

# variable "ssh_authorized_keys" {
#   description = "SSH keys for default user"
#   type        = list(string)
#   default     = []
# }

variable "proxmox_vm_public_key" {
  description = "Public SSH key injected from environment (TF_VAR_PROXMOX_VM_PUBLIC_KEY)"
  type        = string
}

# --- VM definitions (drives for_each in module) ---

variable "vms" {
  description = "Map of VMs to create, keyed by name"
  type = map(object({
    node      = string
    cores     = number
    memory_mb = number
    disk_gb   = number
    ipconfig0 = string
    tags      = list(string)
  }))
}
