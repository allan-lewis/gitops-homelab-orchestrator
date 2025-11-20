# Compose an inventory map from module results + declared VM specs
locals {
  # Build a normalized inventory per host from local.vms + module outputs
  inventory = {
    for name, spec in local.vms : name => {
      vm_id    = try(module.arch[name].vm_id, null)
      ip       = try(module.arch[name].ip_address, "")
      node     = spec.node

      # use ssh_user from the golden spec (hosts.json via local.vms)
      ssh_user = spec.ssh_user

      tags     = spec.tags
    }
  }

  inventory_dir  = "${path.module}/../../artifacts/l2_inventory"
  inventory_json = jsonencode(local.inventory)
  inventory_yaml = yamlencode(local.inventory)
}

# Ensure output directory exists before writing files
resource "null_resource" "inventory_dir" {
  triggers = {
    path = local.inventory_dir
  }

  provisioner "local-exec" {
    command = "mkdir -p ${local.inventory_dir}"
  }
}

# Write JSON inventory
resource "local_file" "inventory_json" {
  content         = local.inventory_json
  filename        = "${local.inventory_dir}/inventory.json"
  file_permission = "0644"

  depends_on = [null_resource.inventory_dir]
}

# Write YAML inventory
resource "local_file" "inventory_yaml" {
  content         = local.inventory_yaml
  filename        = "${local.inventory_dir}/inventory.yaml"
  file_permission = "0644"

  depends_on = [null_resource.inventory_dir]
}

# Optional: expose paths for quick reference in CI logs
output "l2_inventory_paths" {
  value = {
    json = local_file.inventory_json.filename
    yaml = local_file.inventory_yaml.filename
  }
}
