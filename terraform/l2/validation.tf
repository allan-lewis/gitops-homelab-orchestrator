# Fail fast if the provided manifest doesn't match our schema (flat + config)
resource "null_resource" "validate_manifest" {
  # Re-run validation whenever the manifest changes
  triggers = {
    manifest_hash = local.manifest_hash
  }

  lifecycle {
    precondition {
      condition     = can(local.manifest.name) && length(trimspace(tostring(local.manifest.name))) > 0
      error_message = "Manifest must include a non-empty 'name' (template name)."
    }

    precondition {
      condition     = can(local.manifest.node) && length(trimspace(tostring(local.manifest.node))) > 0
      error_message = "Manifest must include a non-empty 'node' (template node)."
    }

    precondition {
      condition     = can(local.manifest.vmid) && tonumber(local.manifest.vmid) > 0
      error_message = "Manifest must include a positive numeric 'vmid' (template VMID)."
    }

    # If 'config' is present, ensure it's an object (map); allow it to be omitted.
    precondition {
      condition     = !can(local.manifest.config) || can(tomap(local.manifest.config))
      error_message = "Manifest 'config' must be a JSON object if present."
    }
  }
}
