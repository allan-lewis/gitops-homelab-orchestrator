locals {
  # Build full API URL from provided variable (populated by env var TF_VAR_pve_access_host)
  pm_api_url = "${chomp(var.pve_access_host)}/api2/json"

  # Read L1 manifest and extract template name
  l1_manifest_raw = file(var.l1_manifest_path)
  l1              = jsondecode(local.l1_manifest_raw)
  image_template = coalesce(
    try(local.l1.name, null),
    try(local.l1.data.name, null)
  )
}
