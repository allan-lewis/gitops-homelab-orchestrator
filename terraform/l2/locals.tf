locals {
  # Read the L1 manifest passed in via environment variable
  l1_manifest_raw = var.l1_manifest_json
  manifest        = jsondecode(local.l1_manifest_raw)

  # Canonical fields from the manifest (flat + config)
  template_name = local.manifest.name
  template_node = local.manifest.node
  template_vmid = tonumber(local.manifest.vmid)
  template_cfg  = try(local.manifest.config, {})

  # Useful for debugging/change detection
  manifest_hash = sha256(local.l1_manifest_raw)

  # Load golden host spec from JSON
  arch_devops_hosts = jsondecode(
    file("${path.module}/../../infra/arch/devops/spec/hosts.json")
  ).hosts

  # Transform host spec -> vms map expected by your existing module/resource
  vms = {
    for name, host in local.arch_devops_hosts :
    name => {
      # From terraform section in hosts.json
      node      = host.terraform.node
      cores     = host.terraform.cpu
      memory_mb = host.terraform.memory_mb
      disk_gb   = host.terraform.disk_gb

      # From tags + network fields
      tags      = host.tags
      ip        = host.ip
      ssh_user  = host.ssh_user

      ipconfig0 = host.terraform.ipconfig
    }
  }
}