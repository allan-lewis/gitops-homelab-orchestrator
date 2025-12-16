variable "proxmox_url" {
  type    = string
  default = "${env("PVE_ACCESS_HOST")}/api2/json"
}

variable "proxmox_username" {
  type    = string
  default = env("PM_TOKEN_ID")
}

variable "proxmox_token" {
  type    = string
  default = env("PM_TOKEN_SECRET")
}

variable "node" {
  type    = string
  default = env("PVE_NODE")
}

variable "bridge" {
  type    = string
  default = "vmbr0"
}

variable "storage_vm" {
  type    = string
  default = "ssd0"
}

variable "storage_iso" {
  type    = string
  default = "local"
}

variable "arch_iso_url" {
  type    = string
  default = ""
}

variable "arch_iso_sha256" {
  type    = string
  default = ""
}

variable "arch_iso_file" {
  type    = string
  default = "local:iso/archlinux-custom-2025.11.07-x86_64.iso"
}

variable "vm_cores" {
  type    = number
  default = 2
}

variable "vm_memory_mb" {
  type    = number
  default = 2048
}

variable "disk_gb" {
  type    = number
  default = 32
}

variable "template_prefix" {
  type    = string
  default = "arch-"
}

variable "template_name" {
  type    = string
  default = ""
}

variable "vm_id" {
  type    = number
  default = 0 # 0 = let Proxmox assign one, but allows CLI override
}

locals {
  # If template_name is set, use it; otherwise prefix + YYYYMMDD date stamp.
  computed_template_name = (
    var.template_name != ""
    ? var.template_name
    : format("%s%s", var.template_prefix, formatdate("YYYYMMDD", timestamp()))
  )
}
