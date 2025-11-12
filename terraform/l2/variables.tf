# --- Proxmox access via environment (mapped as TF_VAR_* by your shell/CI) ---
#   PVE_ACCESS_HOST  -> TF_VAR_pve_access_host (e.g., https://proxmox.allanshomelab.com)
#   PM_TOKEN_ID      -> TF_VAR_pm_token_id     (e.g., gitops@pve!gitops)
#   PM_TOKEN_SECRET  -> TF_VAR_pm_token_secret

variable "pve_access_host" {
  description = "Base Proxmox host URL (no API suffix)"
  type        = string
  default     = ""
}

variable "pm_token_id" {
  description = "Proxmox API token ID"
  type        = string
  sensitive   = true
  default     = ""
}

variable "pm_token_secret" {
  description = "Proxmox API token secret"
  type        = string
  sensitive   = true
  default     = ""
}

variable "pm_tls_insecure" {
  description = "If true, skip TLS verification. Use false for valid certs."
  type        = bool
  default     = false
}

# --- L1 image manifest produced by Packer (JSON) ---
variable "l1_manifest_path" {
  description = "Path to the L1 image manifest JSON (e.g., artifacts/l1_images/arch-base-*.json)"
  type        = string
}

# --- Cloud-init defaults (Arch) ---
variable "ci_user" {
  description = "Default user configured by cloud-init"
  type        = string
  default     = "lab"
}

variable "ssh_authorized_keys" {
  description = "SSH public keys injected via cloud-init"
  type        = list(string)
  default     = []
}

# --- Proxmox VM placement/sizing defaults (override per-VM in vms map) ---
variable "bridge" {
  description = "Proxmox bridge name"
  type        = string
  default     = "vmbr0"
}

variable "storage" {
  description = "Proxmox storage for disks"
  type        = string
  default     = "local-lvm"
}

variable "scsihw" {
  description = "SCSI controller model"
  type        = string
  default     = "virtio-scsi-pci"
}

# --- Declarative set of Arch VMs to create (STATIC IPs REQUIRED) ---
# ipconfig0 must look like: "ip=10.0.0.21/24,gw=10.0.0.1"
variable "vms" {
  description = "Map of Arch VMs keyed by hostname"
  type = map(object({
    node      = string
    cores     = number
    memory_mb = number
    disk_gb   = number
    tags      = list(string)
    ipconfig0 = string
  }))
}
