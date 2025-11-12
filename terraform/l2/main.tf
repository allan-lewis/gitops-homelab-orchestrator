# Arch VMs via cloud-init (static IPs enforced by ipconfig0 input)
module "arch" {
  source = "./modules/common_vm_cloudinit"

  for_each = var.vms

  name      = each.key
  node      = each.value.node
  clone     = local.image_template
  cores     = each.value.cores
  memory_mb = each.value.memory_mb
  disk_gb   = each.value.disk_gb

  bridge    = var.bridge
  storage   = var.storage
  scsihw    = var.scsihw
  ipconfig0 = each.value.ipconfig0
  tags      = each.value.tags

  ci_user             = var.ci_user
  ssh_authorized_keys = var.ssh_authorized_keys
}
