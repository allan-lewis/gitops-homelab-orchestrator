variable "name" {
  type = string
}

variable "node" {
  type = string
}

variable "clone" {
  type = string
}

variable "cores" {
  type = number
}

variable "memory_mb" {
  type = number
}

variable "disk_gb" {
  type = number
}

variable "bridge" {
  type = string
}

variable "storage" {
  type = string
}

variable "scsihw" {
  type    = string
  default = "virtio-scsi-pci"
}

variable "ipconfig0" {
  type = string
}

variable "tags" {
  type    = list(string)
  default = []
}

variable "ci_user" {
  type = string
}

variable "ssh_authorized_keys" {
  type = list(string)
}
