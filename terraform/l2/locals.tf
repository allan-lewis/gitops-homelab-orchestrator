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
}