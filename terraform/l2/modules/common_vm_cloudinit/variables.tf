variable "name" {
  description = "VM hostname/name"
  type        = string
}

variable "node" {
  description = "Proxmox node name (e.g., shardik)"
  type        = string
}

variable "clone_vmid" {
  description = "Template VMID to clone (from L1)"
  type        = number
}

variable "cores" {
  description = "vCPU cores"
  type        = number
}

variable "memory_mb" {
  description = "Memory in MiB"
  type        = number
}

variable "disk_gb" {
  description = "Boot disk size in GiB"
  type        = number
}

variable "storage" {
  description = "Datastore/storage ID for the boot disk"
  type        = string
}

variable "scsihw" {
  description = "SCSI controller model (e.g., virtio-scsi-pci)"
  type        = string
  default     = "virtio-scsi-pci"
}

variable "bridge" {
  description = "Bridge to attach NIC to (e.g., vmbr0)"
  type        = string
  default     = "vmbr0"
}

variable "tags" {
  description = "List of Proxmox tags"
  type        = list(string)
  default     = []
}

variable "ipconfig0" {
  description = "Static IP/gateway in cloud-init style: ip=10.0.0.21/24,gw=10.0.0.1"
  type        = string
}

variable "ci_user" {
  description = "Default SSH user for cloud-init"
  type        = string
  default     = "lab"
}

variable "ssh_authorized_keys" {
  description = "SSH public keys for the default user"
  type        = list(string)
  default     = []
}

variable "agent_enabled" {
  description = "Whether to enable the QEMU agent inside the VM"
  type        = bool
}
