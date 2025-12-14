locals {
  # Load golden host spec from JSON (same structure as before)
  # {
  #   "hosts": {
  #     "host1": { ... },
  #     "host2": { ... }
  #   }
  # }
  hosts_raw = jsondecode(file(var.hosts_json_path))

  # Extract the hosts map (equivalent of local.arch_devops_hosts)
  hosts = local.hosts_raw.hosts

  # Logical template refs -> actual manifest files are now passed in
  # via var.template_manifest_map from the persona root.
  #
  # Example from root:
  # {
  #   "arch/devops/stable" = "infra/arch/spec/vm-template-stable.json"
  # }
  template_manifests = var.template_manifest_map

  # Transform host spec -> vms map expected by common_vm_cloudinit
  vms = {
    for name, host in local.hosts :
    name => {
      # From terraform section in hosts.json
      node      = host.terraform.node
      cores     = host.terraform.cpu
      memory_mb = host.terraform.memory_mb
      disk_gb   = host.terraform.disk_gb

      # From tags + network fields
      tags     = host.terraform.tags
      ip       = host.terraform.ip
      ssh_user = host.terraform.ssh_user

      # ipconfig string is already in the right format for cloudinit
      ipconfig0 = host.terraform.ipconfig

      # Decode the chosen template manifest (same as before, just
      # using template_manifests from a variable instead of hard-coding paths)
      manifest = jsondecode(file(local.template_manifests[host.terraform.template_ref]))
    }
  }

  # Placeholders for later steps (inventory + file paths)
  inventory           = {}
  inventory_json_path = ""
  inventory_yaml_path = ""
}

module "cloudinit" {
  source = "../common_vm_cloudinit"

  # Create one VM per entry in local.vms (same pattern as old root)
  for_each = local.vms

  # Guest agent
  agent_enabled = var.agent_enabled

  # Identity / placement
  name       = each.key
  node       = each.value.node
  clone_vmid = each.value.manifest.vmid

  # Sizing
  cores     = each.value.cores
  memory_mb = each.value.memory_mb
  disk_gb   = each.value.disk_gb

  # Infra defaults (passed through from factory vars)
  storage = var.storage
  scsihw  = var.scsihw
  bridge  = var.bridge

  # Metadata
  tags = each.value.tags

  # Cloud-init (static IPs)
  ipconfig0           = each.value.ipconfig0
  ci_user             = var.ci_user
  ssh_authorized_keys = var.ssh_authorized_keys
}
