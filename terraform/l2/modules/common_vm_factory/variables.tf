variable "hosts_json_path" {
  description = "Path to the persona's hosts.json spec file"
  type        = string
}

variable "template_manifest_map" {
  description = <<EOT
Map of template_ref => manifest path (JSON) for L1 templates.
The factory will use this to look up clone VMIDs and other metadata.
Example:
{
  "arch/devops/stable" = "artifacts/arch/devops/template-manifest-stable.json",
  "arch/devops/canary" = "artifacts/arch/devops/template-manifest-canary.json"
}
EOT
  type = map(string)
}

variable "ci_user" {
  description = "Default SSH user for cloud-init (overrides per-host if needed)"
  type        = string
  default     = "lab"
}

variable "ssh_authorized_keys" {
  description = "SSH public keys to inject for the default user on all hosts (unless overridden)"
  type        = list(string)
  default     = []
}

variable "storage" {
  description = "Datastore/storage ID for the boot disk (passed through to common_vm_cloudinit)"
  type        = string
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

variable "agent_enabled" {
  description = "Whether to enable the QEMU guest agent for VMs in this environment"
  type        = bool
}