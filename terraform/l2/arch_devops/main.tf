locals {
  # Path to this persona's hosts.json spec
  hosts_json_path = "${path.module}/../../../infra/os/arch/personas/devops/spec/terraform.json"

  # Logical template refs → manifest JSON files
  template_manifest_map = {
    "arch/devops/stable" = "${path.module}/../../../infra/os/arch/spec/vm-template-stable.json"
    # "arch/devops/canary" = "${path.module}/../../../infra/os/arch/spec/vm-template-canary.json"
  }
}

module "factory" {
  source = "../modules/common_vm_factory"

  # Spec + template manifests
  hosts_json_path       = local.hosts_json_path
  template_manifest_map = local.template_manifest_map

  # Infra defaults (persona-level)
  storage = var.storage
  scsihw  = var.scsihw
  bridge  = var.bridge
  agent_enabled = var.agent_enabled

  # Cloud-init user + SSH keys applied to all hosts in this persona
  ci_user             = var.ci_user
  ssh_authorized_keys = [var.proxmox_vm_public_key]
}
