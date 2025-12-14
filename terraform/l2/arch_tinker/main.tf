locals {
  # Path to this persona's hosts.json spec
  hosts_json_path = "${path.module}/../../../infra/os/arch/personas/tinker/spec/terraform.json"

  # Logical template refs → manifest JSON files for this persona
  template_manifest_map = {
    "arch/tinker/stable" = "${path.module}/../../../infra/os/arch/spec/vm-template-stable.json"
    # Add canary/etc here later if needed
  }
}

module "factory" {
  source = "../modules/common_vm_factory"

  # Spec inputs
  hosts_json_path       = local.hosts_json_path
  template_manifest_map = local.template_manifest_map

  # Infra defaults (passed down to cloudinit)
  storage = var.storage
  scsihw  = var.scsihw
  bridge  = var.bridge
  agent_enabled = var.agent_enabled

  # Cloud-init settings
  ci_user             = var.ci_user
  ssh_authorized_keys = [var.proxmox_vm_public_key]
}
