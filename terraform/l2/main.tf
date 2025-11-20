module "arch" {
  source = "./modules/common_vm_cloudinit"

  # Create one VM per entry in local.vms
  for_each = local.vms

  # Identity / placement
  name       = each.key
  node       = each.value.node
  clone_vmid = each.value.manifest.vmid

  # Sizing
  cores     = each.value.cores
  memory_mb = each.value.memory_mb
  disk_gb   = each.value.disk_gb

  # Infra defaults
  storage = var.storage
  scsihw  = var.scsihw
  bridge  = var.bridge

  # Metadata
  tags = each.value.tags 

  # Cloud-init (static IPs)
  ipconfig0           = each.value.ipconfig0
  ci_user             = var.ci_user
  ssh_authorized_keys = [var.proxmox_vm_public_key]
}
