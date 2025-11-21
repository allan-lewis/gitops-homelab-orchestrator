locals {
  # Load golden host spec from JSON
  arch_devops_hosts = jsondecode(file("${path.module}/../../infra/arch/devops/spec/hosts.json")).hosts

  # Logical template refs -> actual manifest files
  template_manifests = {
    "arch/devops/stable" = "${path.module}/../../infra/arch/devops/spec/vm-template-stable.json"
    # "arch/devops/canary" = "${path.module}/../../infra/arch/devops/artifacts/template-canary.json"
    # etc, later…
  }

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

      manifest = jsondecode(file(local.template_manifests[host.terraform.template_ref]))
    }
  }
}
